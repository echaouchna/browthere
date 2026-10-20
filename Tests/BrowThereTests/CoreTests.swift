import Foundation
import Testing
@testable import BrowThere

private func ctx(_ s: String, from app: String? = nil) -> LinkContext {
    LinkContext(url: URL(string: s)!, sourceApp: app)
}

private func rule(_ conditions: [Condition], all: Bool = true) -> Rule {
    Rule(matchAll: all, conditions: conditions, target: Target(bundleID: "com.google.Chrome"))
}

@Test func domainMatchesSubdomains() {
    let r = rule([Condition(field: .host, op: .isDomain, value: "*.GitHub.com")])
    #expect(RuleEngine.matches(r, ctx("https://github.com/a")))
    #expect(RuleEngine.matches(r, ctx("https://gist.github.com/a")))
    #expect(!RuleEngine.matches(r, ctx("https://notgithub.com/a")))
}

@Test func wildcardAndRegex() {
    let w = rule([Condition(field: .url, op: .wildcard, value: "https://*.zoom.us/j/*")])
    #expect(RuleEngine.matches(w, ctx("https://acme.zoom.us/j/123")))
    #expect(!RuleEngine.matches(w, ctx("https://acme.zoom.us/profile")))
    let re = rule([Condition(field: .path, op: .regex, value: "^/meet/\\d+$")])
    #expect(RuleEngine.matches(re, ctx("https://x.com/meet/42")))
    let bad = rule([Condition(field: .path, op: .regex, value: "([")])
    #expect(!RuleEngine.matches(bad, ctx("https://x.com/([")))
}

@Test func sourceAppAndAnyAll() {
    let conds = [Condition(field: .sourceApp, op: .equals, value: "com.tinyspeck.slackmacgap"),
                 Condition(field: .host, op: .isDomain, value: "atlassian.net")]
    #expect(!RuleEngine.matches(rule(conds), ctx("https://a.atlassian.net", from: "com.apple.mail")))
    #expect(RuleEngine.matches(rule(conds), ctx("https://a.atlassian.net", from: "com.tinyspeck.slackmacgap")))
    #expect(RuleEngine.matches(rule(conds, all: false), ctx("https://a.atlassian.net", from: "com.apple.mail")))
}

@Test func firstEnabledRuleWins() {
    var a = rule([Condition(field: .host, op: .isDomain, value: "example.com")]); a.name = "a"; a.enabled = false
    var b = rule([Condition(field: .host, op: .isDomain, value: "example.com")]); b.name = "b"
    var c = rule([Condition(field: .url, op: .contains, value: "example")]); c.name = "c"
    #expect(RuleEngine(rules: [a, b, c]).firstMatch(ctx("https://example.com"))?.name == "b")
    #expect(RuleEngine(rules: [rule([Condition(field: .host, op: .isDomain, value: "")])]).firstMatch(ctx("https://x.com")) == nil)
}

@Test func cleanerUnwrapsAndStrips() {
    let safe = URL(string: "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2Fx%3Futm_source%3Dmail%26id%3D1&data=abc")!
    #expect(URLCleaner.clean(safe, unwrap: true, strip: true).absoluteString == "https://github.com/x?id=1")
    let g = URL(string: "https://www.google.com/url?q=https://example.com/&sa=D")!
    #expect(URLCleaner.clean(g, unwrap: true, strip: false).absoluteString == "https://example.com/")
    let plain = URL(string: "https://example.com/?a=1&fbclid=zz")!
    #expect(URLCleaner.clean(plain, unwrap: false, strip: true).absoluteString == "https://example.com/?a=1")
    #expect(URLCleaner.clean(plain, unwrap: false, strip: false) == plain)
}

@Test func argumentTemplates() {
    #expect(Launcher.splitArguments("--profile-directory=\"Profile 2\" {url}", url: "U") == ["--profile-directory=Profile 2", "U"])
    #expect(Launcher.splitArguments("-P work", url: "U") == ["-P", "work", "U"])
}

@Test func parsesFirefoxProfilesIni() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try """
    [Install1]
    Default=Profiles/a
    [Profile1]
    Name=work
    Path=Profiles/b
    [Profile0]
    Name=default
    Path=Profiles/a
    [General]
    Version=2
    """.write(to: dir.appendingPathComponent("profiles.ini"), atomically: true, encoding: .utf8)
    #expect(Discovery.firefoxProfiles(dir).map(\.name) == ["work", "default"])
}

@Test func parsesChromiumLocalState() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try """
    {"profile":{"profiles_order":["Profile 1","Default"],"info_cache":{
      "Default":{"name":"Personal","user_name":"me@x.com","profile_highlight_color":-16777216},
      "Profile 1":{"name":"Work","user_name":""}}}}
    """.write(to: dir.appendingPathComponent("Local State"), atomically: true, encoding: .utf8)
    let ps = Discovery.chromiumProfiles(dir)
    #expect(ps.map(\.id) == ["Profile 1", "Default"])
    #expect(ps[1].detail == "me@x.com" && ps[0].detail == nil)
    #expect(ps[1].launch == .chromium(folder: "Default"))
}

@Test func siteWithPathMatchesBySegment() {
    for (field, op) in [(ConditionField.host, ConditionOp.isDomain), (.url, .isUnder)] {
        let r = rule([Condition(field: field, op: op, value: "https://gitlab.com/my-group/")])
        #expect(RuleEngine.matches(r, ctx("https://gitlab.com/my-group")))
        #expect(RuleEngine.matches(r, ctx("https://gitlab.com/My-Group/team/repo/-/merge_requests/1?x=1")))
        #expect(RuleEngine.matches(r, ctx("https://www.gitlab.com/my-group/x")))
        #expect(!RuleEngine.matches(r, ctx("https://gitlab.com/my-group-old/x")))
        #expect(!RuleEngine.matches(r, ctx("https://gitlab.com/other-group")))
        #expect(!RuleEngine.matches(r, ctx("https://github.com/my-group")))
    }
    #expect(RuleEngine.parseSite("www.gitlab.com/a%20b/?q#f") == ("gitlab.com", "/a b"))
    let exact = rule([Condition(field: .host, op: .equals, value: "www.example.com")])
    #expect(RuleEngine.matches(exact, ctx("https://www.example.com/")))
}

@Test func unwrapsTeamsSafeLinks() {
    let teams = URL(string: "https://teams.public.onecdn.static.microsoft/evergreen-assets/safelinks/2/atp-safelinks.html?url=https%3A%2F%2Ftickets.example.com%2Fitem.do%3Fid%3D42%26rows%3D377&locale=en-us&dest=https%3A%2F%2Fteams.microsoft.com")!
    let out = URLCleaner.clean(teams, unwrap: true, strip: true)
    #expect(out.host == "tickets.example.com")
    #expect(out.absoluteString == "https://tickets.example.com/item.do?id=42&rows=377")
    let old = URL(string: "https://statics.teams.cdn.office.net/evergreen-assets/safelinks/1/atp-safelinks.html?url=https%3A%2F%2Fexample.com%2F")!
    #expect(URLCleaner.clean(old, unwrap: true, strip: false).absoluteString == "https://example.com/")
    // Ordinary pages that merely have a ?url= parameter are left alone.
    let normal = URL(string: "https://example.com/share?url=https%3A%2F%2Fother.com")!
    #expect(URLCleaner.clean(normal, unwrap: true, strip: false) == normal)
}

@Test func launchesReuseExistingWindows() {
    let url = URL(string: "https://example.com/a")!
    func pick(_ engine: Engine, _ launch: ProfileLaunch?, privately: Bool = false) -> PickTarget {
        let profile = launch.map { BrowserProfile(id: "p", name: "P", launch: $0) }
        return PickTarget(
            target: Target(bundleID: "x", profile: profile?.id, privateWindow: privately),
            browser: Browser(bundleID: "x", name: "X", appURL: URL(fileURLWithPath: "/x"), engine: engine, profiles: []),
            profile: profile)
    }
    let cases: [PickTarget] = [
        pick(.chromium, .chromium(folder: "Default")), pick(.chromium, .chromium(folder: "Profile 2"), privately: true),
        pick(.firefox, .firefox(name: "work")), pick(.firefox, .firefox(name: "work"), privately: true),
        pick(.chromium, nil, privately: true), pick(.firefox, nil, privately: true),
    ]
    for c in cases {
        let args = Launcher.arguments(for: url, in: c) ?? []
        #expect(!args.contains { $0.lowercased().contains("new-window") }, "\(args)")
        #expect(args.last == url.absoluteString)
    }
    #expect(Launcher.arguments(for: url, in: pick(.firefox, .firefox(name: "work")))?.contains("-new-tab") == true)
    // No profile, not private (Safari, or a browser as a whole): a plain open, which reuses the front window.
    #expect(Launcher.arguments(for: url, in: pick(.chromium, nil)) == nil)
    #expect(Launcher.arguments(for: url, in: pick(.safari, nil, privately: true)) == nil)
}

/// The debounced save runs off the main thread; it must not trip MainActor isolation checks.
@MainActor @Test func savesConfigInBackground() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("browthere-\(UUID().uuidString).json")
    setenv("BROWTHERE_CONFIG", file.path, 1)
    #expect(ConfigStore.fileURL == file)
    let store = ConfigStore()
    store.config.stripTracking.toggle()
    try await Task.sleep(for: .seconds(1))
    let saved = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: file))
    #expect(saved.stripTracking == store.config.stripTracking)
    try? FileManager.default.removeItem(at: file)
}

@Test func parsesArcSpaces() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("arc-\(UUID().uuidString).json")
    try Data("""
    {"sidebar":{"containers":[{"global":{}},{"spaces":[
      "A1",{"id":"A1","title":"Work","profile":{"default":true}},
      "B2",{"id":"B2","title":null,"profile":{"custom":{"_0":{"directoryBasename":"Profile 1"}}}}
    ],"items":[]}]}}
    """.utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let spaces = Discovery.arcSpaces(file)
    #expect(spaces.map(\.name) == ["Work", "Space 2"])
    #expect(spaces.map(\.id) == ["space:A1", "space:B2"])
    #expect(spaces[1].launch == .arcSpace(id: "B2", title: "", index: 2))
}

@Test func arcOpensSpacesByScript() {
    let url = URL(string: "https://example.com/a")!
    let arc = Browser(bundleID: Discovery.arcBundleID, name: "Arc", appURL: URL(fileURLWithPath: "/x"), engine: .chromium, profiles: [])
    let work = BrowserProfile(id: "space:A1", name: "Work", launch: .arcSpace(id: "A1", title: "Work", index: 1))
    let inSpace = PickTarget(target: Target(bundleID: arc.bundleID, profile: work.id), browser: arc, profile: work)
    #expect(Launcher.arcScriptArguments(for: url, in: inSpace) == [url.absoluteString, "A1", "Work", "1", "0"])
    #expect(Launcher.arguments(for: url, in: inSpace) == nil)
    // Private works without a space; plain Arc is a normal open.
    let privately = PickTarget(target: Target(bundleID: arc.bundleID, privateWindow: true), browser: arc, profile: nil)
    #expect(Launcher.arcScriptArguments(for: url, in: privately) == [url.absoluteString, "", "", "0", "1"])
    #expect(Launcher.arguments(for: url, in: privately) == nil)
    let plain = PickTarget(target: Target(bundleID: arc.bundleID), browser: arc, profile: nil)
    #expect(Launcher.arcScriptArguments(for: url, in: plain) == nil)
}

@Test func stripsSiteAndCustomTrackingParams() {
    func clean(_ s: String, _ custom: [String] = []) -> String {
        URLCleaner.clean(URL(string: s)!, unwrap: false, strip: true, custom: custom).absoluteString
    }
    #expect(clean("https://youtu.be/abc?si=XyZ&t=42") == "https://youtu.be/abc?t=42")
    #expect(clean("https://www.youtube.com/watch?v=abc&si=1&is=2") == "https://www.youtube.com/watch?v=abc")
    #expect(clean("https://music.youtube.com/watch?v=abc&si=1") == "https://music.youtube.com/watch?v=abc")
    // si/is are only tracking on YouTube.
    #expect(clean("https://example.com/?si=1&is=2") == "https://example.com/?si=1&is=2")
    #expect(clean("https://example.com/?ref=x&share_id=1&share_to=2&keep=1", ["Ref", "share_*"]) == "https://example.com/?keep=1")
    #expect(clean("https://shop.example.com/?src=x&q=1", ["example.com:src"]) == "https://shop.example.com/?q=1")
    #expect(clean("https://other.com/?src=x", ["example.com:src"]) == "https://other.com/?src=x")
    #expect(clean("https://other.com/?a=1", ["*"]) == "https://other.com/?a=1")
}
