import Foundation

enum URLCleaner {
    private static let trackingParams: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "mc_cid", "mc_eid", "igshid", "_hsenc", "_hsmi", "mkt_tok", "oly_anon_id", "oly_enc_id",
        "vero_id", "__s", "rb_clickid", "ref_src", "ref_url",
    ]

    /// Parameters that only mean tracking on some sites (elsewhere `si` or `is` can be real data).
    private static let siteParams: [(host: String, params: Set<String>)] = [
        ("youtube.com", ["si", "is"]),
        ("youtu.be", ["si", "is"]),
    ]

    /// host suffix -> query parameter holding the real destination.
    private static let redirectors: [(host: String, path: String?, param: String)] = [
        ("safelinks.protection.outlook.com", nil, "url"),
        ("google.com", "/url", "q"),
        ("google.com", "/url", "url"),
        ("l.facebook.com", "/l.php", "u"),
        ("lm.facebook.com", "/l.php", "u"),
        ("l.instagram.com", nil, "u"),
        ("l.threads.net", nil, "u"),
        ("youtube.com", "/redirect", "q"),
        ("slack-redir.net", "/link", "url"),
        ("linkedin.com", "/redir/redirect", "url"),
        ("out.reddit.com", nil, "url"),
        ("steamcommunity.com", "/linkfilter/", "url"),
        ("urldefense.com", nil, "u"),
    ]

    /// `custom` entries: `name`, `prefix*`, or `domain:name` (that domain and its subdomains).
    static func clean(_ url: URL, unwrap: Bool, strip: Bool, custom: [String] = []) -> URL {
        var url = url
        if unwrap {
            for _ in 0..<3 {
                guard let next = unwrapOnce(url) else { break }
                url = next
            }
        }
        if strip { url = stripTracking(url, custom: custom) }
        return url
    }

    private static func unwrapOnce(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        func destination(_ param: String) -> URL? {
            guard let v = comps.queryItems?.first(where: { $0.name == param })?.value,
                  let dest = URL(string: v), let s = dest.scheme?.lowercased(), s == "http" || s == "https"
            else { return nil }
            return dest
        }
        for r in redirectors where host == r.host || host.hasSuffix("." + r.host) {
            if let p = r.path, !url.path.hasPrefix(p) { continue }
            if let dest = destination(r.param) { return dest }
        }
        // Microsoft Safe Links keeps moving (Outlook, Teams' *.static.microsoft and
        // statics.teams.cdn.office.net …), but always says "safelinks" and uses ?url=.
        if host.contains("safelinks") || url.path.lowercased().contains("safelinks") {
            return destination("url")
        }
        return nil
    }

    private static func stripTracking(_ url: URL, custom: [String]) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems, !items.isEmpty else { return url }
        let host = url.host?.lowercased() ?? ""
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        var exact = trackingParams
        var prefixes = ["utm_"]
        for site in siteParams where on(site.host) { exact.formUnion(site.params) }
        for entry in custom {
            var name = entry.trimmingCharacters(in: .whitespaces).lowercased()
            if let colon = name.firstIndex(of: ":") {
                let domain = name[..<colon].trimmingCharacters(in: .whitespaces)
                guard on(domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain) else { continue }
                name = name[name.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            guard !name.isEmpty else { continue }
            if name.hasSuffix("*") { prefixes.append(String(name.dropLast())) } else { exact.insert(name) }
        }
        let kept = items.filter { item in
            let n = item.name.lowercased()
            return !(exact.contains(n) || prefixes.contains { !$0.isEmpty && n.hasPrefix($0) })
        }
        guard kept.count != items.count else { return url }
        comps.queryItems = kept.isEmpty ? nil : kept
        return comps.url ?? url
    }
}
