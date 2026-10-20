import AppKit

enum Launcher {
    /// Opens `url` in the app/profile described by `pick`. Returns false if the app is gone.
    @MainActor
    @discardableResult
    static func open(_ url: URL, in pick: PickTarget) -> Bool {
        let appURL = pick.browser.appURL
        guard FileManager.default.fileExists(atPath: appURL.path) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let script = arcScriptArguments(for: url, in: pick) {
            runArcScript(script) { ok in
                // No Automation permission, or the space is gone: still open it in Arc.
                if !ok { NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) }
            }
        } else if let args = arguments(for: url, in: pick) {
            // A fresh process hands its arguments to the running instance and exits,
            // which is the only way to target a profile in an already-running browser.
            config.arguments = args
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, err in
                if let err { NSLog("BrowThere: launch failed: \(err.localizedDescription)") }
            }
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, err in
                if let err { NSLog("BrowThere: open failed: \(err.localizedDescription)") }
            }
        }
        return true
    }

    /// Command-line arguments that target the pick's profile / private mode, or nil when a
    /// plain open is enough. None of them ask for a new window: a running browser adds a tab
    /// to that profile's existing window (on any Space) and only opens one if it has none.
    static func arguments(for url: URL, in pick: PickTarget) -> [String]? {
        guard pick.browser.bundleID != Discovery.arcBundleID else { return nil }
        let link = url.absoluteString
        let engine = pick.browser.engine
        let wantsPrivate = pick.target.privateWindow && engine.supportsPrivate
        switch pick.profile?.launch {
        case .chromium(let folder):
            return ["--profile-directory=\(folder)"] + (wantsPrivate ? ["--incognito"] : []) + [link]
        case .firefox(let name):
            return ["-P", name] + (wantsPrivate ? ["-private-window"] : ["-new-tab"]) + [link]
        case .arguments(let template):
            return splitArguments(template, url: link)
        case .arcSpace:
            return nil
        case nil where wantsPrivate:
            return engine == .chromium ? ["--incognito", link] : ["-private-window", link]
        case nil:
            return nil
        }
    }

    /// Arc has no command line for spaces, so spaces and private windows go through its
    /// AppleScript dictionary. Returns the script's argv: url, space id, title, index, private.
    static func arcScriptArguments(for url: URL, in pick: PickTarget) -> [String]? {
        guard pick.browser.bundleID == Discovery.arcBundleID else { return nil }
        let wantsPrivate = pick.target.privateWindow
        var space = ("", "", 0)
        if case .arcSpace(let id, let title, let index) = pick.profile?.launch { space = (id, title, index) }
        guard wantsPrivate || space != ("", "", 0) else { return nil }
        return [url.absoluteString, space.0, space.1, String(space.2), wantsPrivate ? "1" : "0"]
    }

    /// The link and names are passed as arguments, never spliced into the source.
    static let arcScript = """
        on run argv
            set theURL to item 1 of argv
            set spaceID to item 2 of argv
            set spaceTitle to item 3 of argv
            set spaceIndex to (item 4 of argv) as integer
            tell application id "company.thebrowser.Browser"
                if (item 5 of argv) is "1" then
                    make new window with properties {incognito:true}
                    tell front window to make new tab with properties {URL:theURL}
                else
                    if (count of windows) is 0 then make new window
                    tell front window
                        set found to false
                        if spaceID is not "" then
                            try
                                tell space id spaceID to focus
                                set found to true
                            end try
                        end if
                        if not found and spaceTitle is not "" then
                            try
                                tell space spaceTitle to focus
                                set found to true
                            end try
                        end if
                        if not found and spaceIndex > 0 then
                            try
                                tell space spaceIndex to focus
                                set found to true
                            end try
                        end if
                        if not found then error "Arc space not found: " & spaceTitle
                        make new tab with properties {URL:theURL}
                    end tell
                end if
                activate
            end tell
        end run
        """

    @MainActor
    private static func runArcScript(_ args: [String], done: @escaping @MainActor (Bool) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", arcScript] + args
        let errors = Pipe()
        p.standardError = errors
        p.standardOutput = FileHandle.nullDevice
        p.terminationHandler = { @Sendable proc in
            let ok = proc.terminationStatus == 0
            if !ok {
                let msg = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                routeLog.error("Arc script failed: \(msg, privacy: .public)")
            }
            DispatchQueue.main.async { done(ok) }
        }
        do { try p.run() } catch { done(false) }
    }

    /// Shell-like split honoring quotes; `{url}` is replaced (or the URL is appended).
    static func splitArguments(_ template: String, url: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quote: Character?
        var hasToken = false
        for ch in template {
            if let q = quote {
                if ch == q { quote = nil } else { cur.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch; hasToken = true
            } else if ch.isWhitespace {
                if hasToken || !cur.isEmpty { out.append(cur); cur = ""; hasToken = false }
            } else {
                cur.append(ch)
            }
        }
        if hasToken || !cur.isEmpty { out.append(cur) }
        if out.contains(where: { $0.contains("{url}") }) {
            return out.map { $0.replacingOccurrences(of: "{url}", with: url) }
        }
        return out + [url]
    }
}
