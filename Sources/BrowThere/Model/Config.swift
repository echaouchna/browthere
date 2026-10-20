import Foundation

/// Where a link should go: an app, optionally a profile inside it.
struct Target: Codable, Hashable, Sendable {
    var bundleID: String
    /// Profile id as reported by `BrowserCatalog` (Chromium folder, Firefox profile name, or `custom:<uuid>`).
    var profile: String?
    var privateWindow: Bool = false

    init(bundleID: String, profile: String? = nil, privateWindow: Bool = false) {
        self.bundleID = bundleID
        self.profile = profile
        self.privateWindow = privateWindow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        profile = try c.decodeIfPresent(String.self, forKey: .profile)
        privateWindow = try c.decodeIfPresent(Bool.self, forKey: .privateWindow) ?? false
    }

    /// Identity used for ordering / hiding, ignores the private flag.
    var key: String { "\(bundleID)|\(profile ?? "")" }
}

enum ConditionField: String, Codable, CaseIterable, Sendable {
    case host, url, path, sourceApp

    var label: String {
        switch self {
        case .host: "Domain"
        case .url: "Full URL"
        case .path: "Path"
        case .sourceApp: "Opened from"
        }
    }

    var operators: [ConditionOp] {
        switch self {
        case .host: [.isDomain, .equals, .contains, .startsWith, .endsWith, .wildcard, .regex]
        case .url: [.isUnder, .contains, .equals, .startsWith, .endsWith, .wildcard, .regex]
        case .path: [.contains, .equals, .startsWith, .endsWith, .wildcard, .regex]
        case .sourceApp: [.equals]
        }
    }
}

enum ConditionOp: String, Codable, CaseIterable, Sendable {
    case isDomain, isUnder, equals, contains, startsWith, endsWith, wildcard, regex

    var label: String {
        switch self {
        case .isDomain: "is or is under"
        case .isUnder: "is under"
        case .equals: "is"
        case .contains: "contains"
        case .startsWith: "starts with"
        case .endsWith: "ends with"
        case .wildcard: "matches pattern"
        case .regex: "matches regex"
        }
    }
}

struct Condition: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var field: ConditionField = .host
    var op: ConditionOp = .isDomain
    var value: String = ""
}

struct Rule: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String = ""
    var enabled: Bool = true
    var matchAll: Bool = true
    var conditions: [Condition] = [Condition()]
    /// `nil` means "show the picker".
    var target: Target?
}

enum ProfileLaunchStyle: String, Codable, CaseIterable, Sendable {
    case chromiumFolder, firefoxName, arguments, arcSpace

    var label: String {
        switch self {
        case .chromiumFolder: "Chromium profile folder"
        case .firefoxName: "Firefox profile name"
        case .arguments: "Custom launch arguments"
        case .arcSpace: "Arc space name"
        }
    }

    var placeholder: String {
        switch self {
        case .chromiumFolder: "Profile 2"
        case .firefoxName: "work"
        case .arguments: "--profile-directory=Work {url}"
        case .arcSpace: "Work"
        }
    }
}

/// A profile the user added by hand, for browsers whose profiles can't be detected.
struct CustomProfile: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var bundleID: String
    var name: String
    var style: ProfileLaunchStyle
    var value: String
}

struct AppConfig: Codable, Sendable {
    var defaultTarget: Target?
    var showMenuBarIcon = true
    var stripTracking = true
    var unwrapRedirects = true
    /// Extra query parameters to strip: `name`, `prefix*` or `domain:name`.
    var customTrackingParams: [String] = []
    var hiddenTargets: Set<String> = []
    var targetOrder: [String] = []
    var hideDetectedProfiles = false
    /// Also list apps that open web links but aren't browsers (ChatGPT, terminals…).
    var includeNonBrowsers = false
    var customProfiles: [CustomProfile] = []
    var rules: [Rule] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        defaultTarget = try c.decodeIfPresent(Target.self, forKey: .defaultTarget)
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        stripTracking = try c.decodeIfPresent(Bool.self, forKey: .stripTracking) ?? d.stripTracking
        unwrapRedirects = try c.decodeIfPresent(Bool.self, forKey: .unwrapRedirects) ?? d.unwrapRedirects
        customTrackingParams = try c.decodeIfPresent([String].self, forKey: .customTrackingParams) ?? []
        hiddenTargets = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenTargets) ?? []
        targetOrder = try c.decodeIfPresent([String].self, forKey: .targetOrder) ?? []
        hideDetectedProfiles = try c.decodeIfPresent(Bool.self, forKey: .hideDetectedProfiles) ?? false
        includeNonBrowsers = try c.decodeIfPresent(Bool.self, forKey: .includeNonBrowsers) ?? false
        customProfiles = try c.decodeIfPresent([CustomProfile].self, forKey: .customProfiles) ?? []
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
    }
}

@MainActor
@Observable
final class ConfigStore {
    var config: AppConfig {
        didSet {
            revision &+= 1
            scheduleSave()
            if oldValue.showMenuBarIcon != config.showMenuBarIcon { onMenuBarToggle?() }
        }
    }

    /// Bumped on every change; lets the rule engine recompile lazily.
    @ObservationIgnored private(set) var revision = 0
    @ObservationIgnored let isFirstLaunch: Bool
    @ObservationIgnored var onMenuBarToggle: (() -> Void)?
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    static let fileURL: URL = {
        if let override = ProcessInfo.processInfo.environment["BROWTHERE_CONFIG"] {
            return URL(fileURLWithPath: override)
        }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BrowThere", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
            isFirstLaunch = false
        } else {
            config = AppConfig()
            isFirstLaunch = true
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = config
        let url = Self.fileURL
        // @Sendable keeps the closure off the MainActor: it runs on a background queue, and an
        // inherited MainActor isolation would trap there (Swift 6 checks it at runtime).
        let work = DispatchWorkItem { @Sendable in
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
        pendingSave = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
