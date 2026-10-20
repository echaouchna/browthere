import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ConfigStore()
    lazy var catalog = BrowserCatalog(store: store)
    lazy var router = Router(store: store, catalog: catalog)
    private var statusItem: NSStatusItem?
    private var settings: SettingsWindowController?
    private var receivedURL = false
    /// Set when another copy is already running; we hand everything to it and quit.
    private var primary: NSRunningApplication?

    func applicationWillFinishLaunching(_ notification: Notification) {
        primary = Self.otherInstance()
        // Registered before launch finishes so the URL that launched us isn't missed,
        // and via Apple Events (not application(_:open:)) so we learn the sender app.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let primary {
            // Give a launch URL a moment to arrive, then bring up the running copy if none did.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if !self.receivedURL { Self.forward(nil, to: primary) }
                NSApp.terminate(nil)
            }
            return
        }
        NSApp.mainMenu = Self.makeMainMenu()
        catalog.refresh()
        updateStatusItem()
        store.onMenuBarToggle = { [weak self] in self?.updateStatusItem() }
        #if DEBUG
        if let dir = ProcessInfo.processInfo.environment["BROWTHERE_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.snapshot(to: dir) }
            return
        }
        #endif
        if store.isFirstLaunch && !receivedURL { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: s) else { return }
        receivedURL = true
        if let primary { Self.forward(url, to: primary); return }
        let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let source = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        router.route(url, sourceApp: source == Bundle.main.bundleIdentifier ? nil : source)
    }

    /// Local .html files when we're the default browser.
    func application(_ application: NSApplication, open urls: [URL]) {
        receivedURL = true
        if let primary { urls.forEach { Self.forward($0, to: primary) }; return }
        for url in urls { router.route(url, sourceApp: nil) }
    }

    // MARK: Main menu

    /// Text fields only get ⌘V/⌘C/⌘X/⌘A/⌘Z through Edit menu key equivalents,
    /// so even a menu-bar app needs a main menu.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide BrowThere", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit BrowThere", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "BrowThere", action: nil, keyEquivalent: "").submenu = app

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        NSApp.windowsMenu = window

        return main
    }

    // MARK: Single instance

    private static func otherInstance() -> NSRunningApplication? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BROWTHERE_SNAPSHOT"] != nil { return nil }
        #endif
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
            .min { ($0.launchDate ?? .distantFuture) < ($1.launchDate ?? .distantFuture) }
    }

    /// Hands a link (or a plain "reopen", which shows Settings) to the running copy.
    private static func forward(_ url: URL?, to app: NSRunningApplication) {
        guard let appURL = app.bundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = false
        if let url {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        }
    }

    // MARK: Menu bar

    private func updateStatusItem() {
        if store.config.showMenuBarIcon {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            // The app icon's fork as a template image, so it follows the menu bar's color.
            let img = BrandGlyph.image(size: 18, lineWidth: 72, template: true)
            img.accessibilityDescription = "BrowThere"
            item.button?.image = img
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Link from Clipboard", action: #selector(openClipboard), keyEquivalent: "").target = self
            menu.addItem(.separator())
            let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
            login.target = self
            login.tag = 1
            menu.delegate = self
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit BrowThere", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func openClipboard() {
        guard let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { NSSound.beep(); return }
        router.showPicker(url)
    }

    @objc private func openSettings() { showSettings() }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        if let err = LoginItem.set(!LoginItem.isEnabled) { NSLog("BrowThere: login item: \(err)") }
        if LoginItem.needsApproval { LoginItem.openSystemSettings() }
    }

    func showSettings() {
        catalog.refresh()
        if settings == nil {
            settings = SettingsWindowController(store: store, catalog: catalog, router: router) { [weak self] in
                // Drop the whole SwiftUI hierarchy when the window closes to give the memory back.
                self?.settings = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }
        NSApp.setActivationPolicy(.regular)
        settings?.show()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: 1)?.state = LoginItem.isEnabled ? .on : .off
    }
}
