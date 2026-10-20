import Foundation

struct LinkContext: Sendable {
    let url: URL
    let host: String
    let full: String
    let path: String
    let sourceApp: String?

    init(url: URL, sourceApp: String?) {
        self.url = url
        host = (url.host ?? "").lowercased()
        full = url.absoluteString
        path = url.path.isEmpty ? "/" : url.path
        self.sourceApp = sourceApp
    }
}

/// Rules compiled once per config revision so matching a link is just a few string compares.
struct RuleEngine {
    private struct Compiled {
        let rule: Rule
        let tests: [(LinkContext) -> Bool]
    }

    private let compiled: [Compiled]

    init(rules: [Rule]) {
        compiled = rules.filter(\.enabled).compactMap { rule in
            let tests = rule.conditions.compactMap(Self.compile)
            return tests.isEmpty ? nil : Compiled(rule: rule, tests: tests)
        }
    }

    func firstMatch(_ ctx: LinkContext) -> Rule? {
        compiled.first { c in
            c.rule.matchAll ? c.tests.allSatisfy { $0(ctx) } : c.tests.contains { $0(ctx) }
        }?.rule
    }

    static func matches(_ rule: Rule, _ ctx: LinkContext) -> Bool {
        RuleEngine(rules: [rule]).firstMatch(ctx) != nil
    }

    /// Splits "https://gitlab.com/my-group/" into ("gitlab.com", "/my-group").
    /// The path is nil when the value is just a domain.
    static func parseSite(_ raw: String) -> (domain: String, path: String?) {
        var v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = v.range(of: "://") { v = String(v[r.upperBound...]) }
        if let cut = v.firstIndex(where: { $0 == "?" || $0 == "#" }) { v = String(v[..<cut]) }
        let slash = v.firstIndex(of: "/") ?? v.endIndex
        // "www.x.com" should still cover x.com and its other subdomains.
        var domain = normalizeDomain(String(v[..<slash]))
        if domain.hasPrefix("www.") { domain.removeFirst(4) }
        var path = String(v[slash...]).lowercased()
        path = path.removingPercentEncoding ?? path
        while path.hasSuffix("/") { path.removeLast() }
        return (domain, path.isEmpty ? nil : path)
    }

    /// Accepts "github.com", "*.github.com", "https://github.com/foo".
    static func normalizeDomain(_ raw: String) -> String {
        var v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = v.range(of: "://") { v = String(v[r.upperBound...]) }
        if let slash = v.firstIndex(of: "/") { v = String(v[..<slash]) }
        if v.hasPrefix("*.") { v.removeFirst(2) }
        if v.hasPrefix(".") { v.removeFirst() }
        return v
    }

    private static func compile(_ c: Condition) -> ((LinkContext) -> Bool)? {
        let raw = c.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let get: @Sendable (LinkContext) -> String = switch c.field {
        case .host: { $0.host }
        case .url: { $0.full }
        case .path: { $0.path }
        case .sourceApp: { $0.sourceApp ?? "" }
        }
        let v = raw.lowercased()
        switch c.op {
        case .isDomain, .isUnder:
            // Domain incl. subdomains, plus an optional path matched by whole segments:
            // "gitlab.com/group" matches /group and /group/x, not /group-other.
            let (d, path) = parseSite(raw)
            let dotted = "." + d
            return { ctx in
                let h = ctx.host
                guard h == d || h.hasSuffix(dotted) else { return false }
                guard let path else { return true }
                let p = ctx.path.lowercased()
                return p == path || p.hasPrefix(path + "/")
            }
        case .equals:
            let target = c.field == .host ? normalizeDomain(raw) : v
            return { get($0).lowercased() == target }
        case .contains: return { get($0).lowercased().contains(v) }
        case .startsWith: return { get($0).lowercased().hasPrefix(v) }
        case .endsWith: return { get($0).lowercased().hasSuffix(v) }
        case .wildcard:
            let pattern = "^" + NSRegularExpression.escapedPattern(for: raw)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".") + "$"
            return regex(pattern, get)
        case .regex:
            return regex(raw, get)
        }
    }

    private static func regex(_ pattern: String, _ get: @escaping (LinkContext) -> String) -> ((LinkContext) -> Bool)? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return { ctx in
            let s = get(ctx)
            return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
    }

    static func isValidRegex(_ s: String) -> Bool {
        (try? NSRegularExpression(pattern: s)) != nil
    }
}
