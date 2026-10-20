import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onClose: () -> Void

    init(store: ConfigStore, catalog: BrowserCatalog, router: Router, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let root = SettingsRoot()
            .environment(store)
            .environment(catalog)
            .environment(RouterBox(router: router))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init()
        let host = NSHostingController(rootView: root)
        host.sceneBridgingOptions = [.toolbars, .title]
        window.title = "BrowThere"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.ink
        window.toolbarStyle = .unified
        window.contentViewController = host
        window.setContentSize(NSSize(width: 860, height: 600))
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("BrowThereSettings")
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window.contentViewController = nil
        onClose()
    }
}

@MainActor
@Observable
final class RouterBox {
    let router: Router
    init(router: Router) { self.router = router }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case overview, rules, browsers, cleaning, general, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "BrowThere"
        case .rules: "Rules"
        case .browsers: "Browsers & Profiles"
        case .cleaning: "Link Cleaning"
        case .general: "General"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .overview: BrandGlyph.symbol
        case .rules: "list.bullet.rectangle.fill"
        case .browsers: "globe"
        case .cleaning: "sparkles"
        case .general: "gearshape.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .overview: .brandViolet
        case .rules: .brandPink
        case .browsers: .brandViolet
        case .cleaning: .brandMint
        case .general: .brandFaint
        case .about: .brandViolet
        }
    }

    /// Words the sidebar search matches against, besides the title.
    var keywords: [String] {
        switch self {
        case .overview: ["status", "default browser", "fallback", "no rule", "everything else", "option", "picker"]
        case .rules: ["rule", "domain", "url", "path", "regex", "wildcard", "source app", "test", "match", "private"]
        case .browsers: ["browser", "profile", "picker", "order", "hide", "custom", "chrome", "helium", "firefox", "zen", "arc", "space"]
        case .cleaning: ["tracking", "utm", "redirect", "safe links", "outlook", "teams", "fbclid", "privacy", "youtube", "si", "parameter", "custom"]
        case .general: ["login", "startup", "menu bar", "config", "launch"]
        case .about: ["version", "memory"]
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || title.lowercased().contains(q) || keywords.contains { $0.contains(q) }
    }

    /// Sidebar groups, separated by a gap like System Settings.
    static let groups: [[SettingsPane]] = [[.rules, .browsers], [.cleaning, .general], [.about]]
}

struct SettingsRoot: View {
    @State private var history: [SettingsPane]
    @State private var position = 0
    @State private var search = ""

    init(pane: SettingsPane = .overview) { _history = State(initialValue: [pane]) }

    private var current: SettingsPane { history[position] }

    private var selection: Binding<SettingsPane?> {
        Binding(get: { current }, set: { if let p = $0 { go(p) } })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                if SettingsPane.overview.matches(search) {
                    StatusSidebarRow().tag(SettingsPane.overview)
                }
                ForEach(Array(SettingsPane.groups.enumerated()), id: \.offset) { _, group in
                    let shown = group.filter { $0.matches(search) }
                    if !shown.isEmpty {
                        Section {
                            ForEach(shown) { p in
                                Label {
                                    Text(p.title)
                                } icon: {
                                    IconTile(symbol: p.symbol, tint: p.tint, size: 24)
                                }
                                .padding(.vertical, 2)
                                .tag(p)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.brandSurface)
            .searchable(text: $search, placement: .sidebar, prompt: "Search Settings")
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 260)
        } detail: {
            detail
                .navigationTitle(current.title)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        ControlGroup {
                            Button { position -= 1 } label: { Image(systemName: "chevron.left") }
                                .disabled(position == 0)
                                .help("Back")
                            Button { position += 1 } label: { Image(systemName: "chevron.right") }
                                .disabled(position >= history.count - 1)
                                .help("Forward")
                        }
                        .controlGroupStyle(.navigation)
                    }
                }
        }
        .tint(.brandPink)
        .toggleStyle(BrandSwitchStyle())
    }

    @ViewBuilder private var detail: some View {
        switch current {
        case .overview: OverviewPane()
        case .rules: RulesPane()
        case .browsers: BrowsersPane()
        case .cleaning: CleaningPane()
        case .general: GeneralPane()
        case .about: AboutPane()
        }
    }

    private func go(_ pane: SettingsPane) {
        guard pane != current else { return }
        history = Array(history.prefix(position + 1)) + [pane]
        position = history.count - 1
    }
}

/// The big first row of the sidebar: app icon plus live default-browser status.
private struct StatusSidebarRow: View {
    @State private var isDefault = DefaultBrowser.isDefault

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("BrowThere").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(isDefault ? Color.brandMint : Color.brandAmber).frame(width: 6, height: 6)
                    Text(isDefault ? "Default browser" : "Not default").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            isDefault = DefaultBrowser.isDefault
        }
    }
}

/// System Settings–style colored rounded square with a white glyph.
struct IconTile: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 20

    var body: some View {
        Group {
            if symbol == BrandGlyph.symbol {
                Image(nsImage: BrandGlyph.image(size: size * 0.62, color: .white))
            } else {
                Image(systemName: symbol).font(.system(size: size * 0.52, weight: .semibold))
            }
        }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

/// A settings row: title and explanation on the left, control on the right.
struct SettingRow<Control: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 2)
    }
}

enum DefaultBrowser {
    static var isDefault: Bool {
        guard let probe = URL(string: "https://example.com"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
        return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    static func makeDefault() {
        let me = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "http") { _ in
            DispatchQueue.main.async {
                NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "https") { _ in }
            }
        }
    }
}
