import AppKit

enum Engine: String, Sendable {
    case chromium, firefox, safari, other

    var supportsPrivate: Bool { self == .chromium || self == .firefox }
}

enum ProfileLaunch: Hashable, Sendable {
    case chromium(folder: String)
    case firefox(name: String)
    case arguments(String)
    /// An Arc space, focused by AppleScript: by `id`, else by `title`, else by 1-based `index`.
    case arcSpace(id: String, title: String, index: Int)
}

struct BrowserProfile: Hashable, Sendable {
    var id: String
    var name: String
    var detail: String?
    var avatarPath: String?
    var color: UInt32?
    var launch: ProfileLaunch
    var isCustom = false
}

struct Browser: Hashable, Sendable {
    var bundleID: String
    var name: String
    var appURL: URL
    var engine: Engine
    var profiles: [BrowserProfile]
    /// Opens HTML files too, i.e. a real browser rather than an app that merely claims http(s).
    var opensHTML = true
}

/// A row in the picker / settings: a browser, optionally narrowed to one profile.
struct PickTarget: Hashable, Identifiable {
    var target: Target
    var browser: Browser
    var profile: BrowserProfile?

    var id: String { target.key }
    var title: String { browser.name }
    var subtitle: String? { profile.map { p in p.detail.map { "\(p.name) · \($0)" } ?? p.name } }
}

@MainActor
@Observable
final class BrowserCatalog {
    private(set) var browsers: [Browser] = []
    @ObservationIgnored private let store: ConfigStore
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]

    init(store: ConfigStore) { self.store = store }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let own = Bundle.main.bundleIdentifier ?? "com.echaouchna.browthere"
        Task.detached(priority: .utility) {
            let found = Discovery.discover(excluding: own)
            await MainActor.run {
                if found != self.browsers { self.browsers = found }
                self.refreshing = false
            }
        }
    }

    func browser(_ bundleID: String) -> Browser? { browsers.first { $0.bundleID == bundleID } }

    /// Links can arrive at launch before the background scan is done; scan inline then
    /// (tens of ms) so rules never fall back to "no profile".
    func loadIfNeeded() {
        guard browsers.isEmpty else { return }
        browsers = Discovery.discover(excluding: Bundle.main.bundleIdentifier ?? "com.echaouchna.browthere")
    }

    /// Browsers offered in the picker and settings.
    var listedBrowsers: [Browser] {
        store.config.includeNonBrowsers ? browsers : browsers.filter(\.opensHTML)
    }

    /// Detected + custom profiles for a browser, respecting settings.
    func profiles(for b: Browser) -> [BrowserProfile] {
        let cfg = store.config
        let detected = cfg.hideDetectedProfiles ? [] : b.profiles
        let custom = cfg.customProfiles.filter { $0.bundleID == b.bundleID }.map { c -> BrowserProfile in
            let launch: ProfileLaunch = switch c.style {
            case .chromiumFolder: .chromium(folder: c.value)
            case .firefoxName: .firefox(name: c.value)
            case .arguments: .arguments(c.value)
            case .arcSpace: .arcSpace(id: "", title: c.value, index: 0)
            }
            return BrowserProfile(id: "custom:\(c.id.uuidString)", name: c.name, launch: launch, isCustom: true)
        }
        return detected + custom
    }

    /// Every target, in the user's order (hidden ones included).
    var allTargets: [PickTarget] {
        var out: [PickTarget] = []
        for b in listedBrowsers {
            let ps = profiles(for: b)
            if ps.count >= 2 || ps.contains(where: \.isCustom) {
                out += ps.map { PickTarget(target: Target(bundleID: b.bundleID, profile: $0.id), browser: b, profile: $0) }
            } else {
                out.append(PickTarget(target: Target(bundleID: b.bundleID), browser: b, profile: nil))
            }
        }
        let order = store.config.targetOrder
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return out.enumerated().sorted { l, r in
            let a = rank[l.element.id] ?? (order.count + l.offset)
            let b = rank[r.element.id] ?? (order.count + r.offset)
            return a < b
        }.map(\.element)
    }

    var visibleTargets: [PickTarget] {
        let hidden = store.config.hiddenTargets
        return allTargets.filter { !hidden.contains($0.id) }
    }

    func resolve(_ t: Target) -> PickTarget? {
        if let b = browser(t.bundleID) {
            let p = t.profile.flatMap { id in profiles(for: b).first { $0.id == id } }
            if t.profile != nil && p == nil { return nil }
            return PickTarget(target: t, browser: b, profile: p)
        }
        // Not a browser (e.g. Zoom, Slack): any installed app can be a target.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: t.bundleID) else { return nil }
        let b = Browser(bundleID: t.bundleID, name: Discovery.displayName(url), appURL: url, engine: .other, profiles: [])
        return PickTarget(target: Target(bundleID: t.bundleID), browser: b, profile: nil)
    }

    func icon(for bundleID: String, size: CGFloat = 32) -> NSImage {
        let key = "\(bundleID)@\(size)"
        if let img = iconCache[key] { return img }
        let img: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            img = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            img = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        img.size = NSSize(width: size, height: size)
        iconCache[key] = img
        return img
    }

    func avatar(for p: BrowserProfile) -> NSImage? {
        guard let path = p.avatarPath else { return nil }
        if let img = iconCache[path] { return img }
        guard let img = NSImage(contentsOfFile: path) else { return nil }
        iconCache[path] = img
        return img
    }
}

/// Filesystem / LaunchServices discovery. Runs off the main thread.
enum Discovery {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    static let chromiumDirs: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
        "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
        "com.microsoft.edgemac.Canary": "Microsoft Edge Canary",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.brave.Browser.beta": "BraveSoftware/Brave-Browser-Beta",
        "com.brave.Browser.nightly": "BraveSoftware/Brave-Browser-Nightly",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.vivaldi.Vivaldi.snapshot": "Vivaldi Snapshot",
        "net.imput.helium": "net.imput.helium",
        "org.chromium.Thorium": "Thorium",
        "com.naver.Whale": "Naver/Whale",
        "ru.yandex.desktop.yandex-browser": "Yandex/YandexBrowser",
        "ai.perplexity.comet": "Comet",
    ]

    static let firefoxDirs: [String: String] = [
        "org.mozilla.firefox": "Firefox",
        "org.mozilla.firefoxdeveloperedition": "Firefox",
        "org.mozilla.nightly": "Firefox",
        "app.zen-browser.zen": "zen",
        "net.waterfox.waterfox": "Waterfox",
        "one.ablaze.floorp": "Floorp",
        "io.gitlab.librewolf-community": "librewolf",
        "org.mozilla.librewolf": "librewolf",
    ]

    static let arcBundleID = "company.thebrowser.Browser"

    static func discover(excluding own: String) -> [Browser] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        var seen = Set<String>()
        var result: [Browser] = []
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: probe)
            .sorted { rank($0) < rank($1) }
        for url in apps {
            guard let id = Bundle(url: url)?.bundleIdentifier, id != own, seen.insert(id).inserted else { continue }
            let name = displayName(url)
            let (engine, profiles) = detect(bundleID: id, name: name, appURL: url)
            result.append(Browser(bundleID: id, name: name, appURL: url, engine: engine, profiles: profiles,
                                  opensHTML: isKnown(id) || declaresHTMLViewer(url)))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Real browsers list HTML as a document type they view; apps that merely
    /// grab http(s) links (chat apps, terminals) don't, or only as "Alternate".
    static func declaresHTMLViewer(_ appURL: URL) -> Bool {
        guard let types = Bundle(url: appURL)?.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]] else { return false }
        return types.contains { t in
            guard (t["LSHandlerRank"] as? String) != "Alternate" else { return false }
            let uti = (t["LSItemContentTypes"] as? [String]) ?? []
            let ext = (t["CFBundleTypeExtensions"] as? [String]) ?? []
            return uti.contains("public.html") || ext.contains { $0.lowercased() == "html" }
        }
    }

    /// Prefer copies in /Applications over ones in build folders, DMGs, etc.
    private static func rank(_ url: URL) -> Int {
        let p = url.path
        if p.hasPrefix("/Applications/") { return 0 }
        if p.hasPrefix("/System/") { return 1 }
        if p.contains("/Applications/") { return 2 }
        return 3
    }

    static func displayName(_ url: URL) -> String {
        let n = FileManager.default.displayName(atPath: url.path)
        return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
    }

    static func isKnown(_ id: String) -> Bool {
        id.hasPrefix("com.apple.Safari") || id == arcBundleID || chromiumDirs[id] != nil || firefoxDirs[id] != nil
    }

    static func detect(bundleID id: String, name: String, appURL: URL) -> (Engine, [BrowserProfile]) {
        if id == "com.apple.Safari" || id.hasPrefix("com.apple.Safari") { return (.safari, []) }
        if id == arcBundleID { return (.chromium, arcSpaces(support.appendingPathComponent("Arc/StorableSidebar.json"))) }
        if let dir = chromiumDirs[id] { return (.chromium, chromiumProfiles(support.appendingPathComponent(dir))) }
        if let dir = firefoxDirs[id] { return (.firefox, firefoxProfiles(support.appendingPathComponent(dir))) }

        // Unknown browser: guess the engine from the bundle, the data folder from common names.
        let fm = FileManager.default
        let candidates = [id, name, name.lowercased(), name.replacingOccurrences(of: " ", with: "")]
            .map { support.appendingPathComponent($0) }
        if fm.fileExists(atPath: appURL.appendingPathComponent("Contents/MacOS/XUL").path) {
            let dir = candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("profiles.ini").path) }
            return (.firefox, dir.map(firefoxProfiles) ?? [])
        }
        if let dir = candidates.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("Local State").path) }) {
            return (.chromium, chromiumProfiles(dir))
        }
        let frameworks = (try? fm.contentsOfDirectory(atPath: appURL.appendingPathComponent("Contents/Frameworks").path)) ?? []
        let isElectron = frameworks.contains("Electron Framework.framework")
        if !isElectron && frameworks.contains(where: { $0.hasSuffix(" Framework.framework") }) { return (.chromium, []) }
        return (.other, [])
    }

    static func chromiumProfiles(_ dir: URL) -> [BrowserProfile] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("Local State")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]]
        else { return [] }

        let order = (profile["profiles_order"] as? [String]) ?? cache.keys.sorted()
        let keys = order.filter { cache[$0] != nil } + cache.keys.filter { !order.contains($0) }.sorted()
        return keys.compactMap { folder in
            guard let e = cache[folder] else { return nil }
            let name = (e["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? folder
            let email = (e["user_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let pic = dir.appendingPathComponent(folder).appendingPathComponent("Google Profile Picture.png").path
            let colorNum = (e["default_avatar_fill_color"] ?? e["profile_highlight_color"]) as? NSNumber
            return BrowserProfile(
                id: folder, name: name, detail: email,
                avatarPath: FileManager.default.fileExists(atPath: pic) ? pic : nil,
                color: colorNum.map { UInt32(truncatingIfNeeded: $0.int64Value) },
                launch: .chromium(folder: folder)
            )
        }
    }

    /// Arc keeps its sidebar in StorableSidebar.json: `sidebar.containers[n].spaces` alternates
    /// space IDs and space objects ({id, title, profile…}), in sidebar order.
    static func arcSpaces(_ file: URL) -> [BrowserProfile] {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let containers = (json["sidebar"] as? [String: Any])?["containers"] as? [[String: Any]],
              let spaces = containers.lazy.compactMap({ $0["spaces"] as? [Any] }).first
        else { return [] }
        let objects = spaces.compactMap { $0 as? [String: Any] }.filter { $0["id"] is String }
        return objects.enumerated().map { i, s in
            let id = s["id"] as! String
            let title = (s["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return BrowserProfile(id: "space:\(id)", name: title ?? "Space \(i + 1)",
                                  launch: .arcSpace(id: id, title: title ?? "", index: i + 1))
        }
    }

    static func firefoxProfiles(_ dir: URL) -> [BrowserProfile] {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("profiles.ini"), encoding: .utf8) else { return [] }
        var sections: [[String: String]] = []
        var current: [String: String]?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                if let c = current { sections.append(c) }
                current = line.hasPrefix("[Profile") ? [:] : nil
            } else if let eq = line.firstIndex(of: "="), current != nil {
                current?[String(line[..<eq])] = String(line[line.index(after: eq)...])
            }
        }
        if let c = current { sections.append(c) }
        return sections.compactMap { s in
            guard let name = s["Name"], !name.isEmpty else { return nil }
            return BrowserProfile(id: name, name: name, launch: .firefox(name: name))
        }
    }
}
