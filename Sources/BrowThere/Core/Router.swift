import AppKit
import os

let routeLog = Logger(subsystem: "com.echaouchna.browthere", category: "route")

@MainActor
final class Router {
    private let store: ConfigStore
    private let catalog: BrowserCatalog
    private var engine = RuleEngine(rules: [])
    private var engineRevision = -1
    private var picker: PickerController?

    init(store: ConfigStore, catalog: BrowserCatalog) {
        self.store = store
        self.catalog = catalog
    }

    enum Decision: Equatable {
        case open(Target, rule: Rule?)
        case pick(rule: Rule?)
    }

    func decide(_ ctx: LinkContext) -> Decision {
        if engineRevision != store.revision {
            engine = RuleEngine(rules: store.config.rules)
            engineRevision = store.revision
        }
        if let rule = engine.firstMatch(ctx) {
            return rule.target.map { .open($0, rule: rule) } ?? .pick(rule: rule)
        }
        return store.config.defaultTarget.map { .open($0, rule: nil) } ?? .pick(rule: nil)
    }

    func route(_ raw: URL, sourceApp: String?) {
        catalog.loadIfNeeded()
        let cfg = store.config
        let url = URLCleaner.clean(raw, unwrap: cfg.unwrapRedirects, strip: cfg.stripTracking, custom: cfg.customTrackingParams)
        let forcePicker = NSEvent.modifierFlags.contains(.option)

        // Rules always look at the real destination, even when unwrapping for opening is off.
        let destination = cfg.unwrapRedirects ? url : URLCleaner.clean(raw, unwrap: true, strip: false)
        let decision = decide(LinkContext(url: destination, sourceApp: sourceApp))
        let ruleName = switch decision {
        case .open(_, let r), .pick(let r): r.map { $0.name.isEmpty ? ($0.conditions.first?.value ?? "?") : $0.name } ?? "(default)"
        }
        routeLog.notice("\(url.absoluteString, privacy: .public) from \(sourceApp ?? "?", privacy: .public) → rule \(ruleName, privacy: .public)")

        if !forcePicker, case .open(let target, _) = decision {
            if let pick = catalog.resolve(target), Launcher.open(url, in: pick) {
                routeLog.notice("opened in \(target.bundleID, privacy: .public) profile \(target.profile ?? "-", privacy: .public)")
                return
            }
            routeLog.error("target unavailable: \(target.bundleID, privacy: .public) profile \(target.profile ?? "-", privacy: .public)")
        }
        showPicker(url)
    }

    func showPicker(_ url: URL) {
        picker?.close()
        let p = PickerController(url: url, catalog: catalog) { [weak self] choice, remember in
            guard let self else { return }
            self.picker = nil
            guard let choice else { return }
            if remember { self.remember(choice.target, for: url) }
            Launcher.open(url, in: choice)
        }
        picker = p
        p.show()
        catalog.refresh()
    }

    /// ⌘-pick in the picker: always open this domain there.
    private func remember(_ target: Target, for url: URL) {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let rule = Rule(name: domain, conditions: [Condition(field: .host, op: .isDomain, value: domain)], target: target)
        store.config.rules.insert(rule, at: 0)
    }
}
