import SwiftUI

struct RulesPane: View {
    @Environment(ConfigStore.self) private var store
    @Environment(BrowserCatalog.self) private var catalog
    @Environment(RouterBox.self) private var routerBox
    @State private var editing: Rule?
    @State private var testURL = ""
    @State private var testSource: String?

    var body: some View {
        @Bindable var store = store
        let decision = testDecision
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    TextField("Try a link", text: $testURL, prompt: Text("https://github.com/…"))
                        .textFieldStyle(.plain)
                    SourceAppPicker(bundleID: $testSource, emptyLabel: "Any app")
                }
                if let decision {
                    DecisionView(decision: decision)
                }
            } header: {
                Text("Test a link")
            }

            Section {
                if store.config.rules.isEmpty {
                    EmptyRules { editing = Rule() }
                }
                ForEach($store.config.rules) { $rule in
                    RuleRow(rule: $rule, highlighted: decision?.rule?.id == rule.id) { editing = rule }
                        .contextMenu {
                            Button("Edit…") { editing = rule }
                            Button("Duplicate") {
                                var copy = rule
                                copy.id = UUID()
                                copy.name = rule.name.isEmpty ? "" : rule.name + " copy"
                                if let i = store.config.rules.firstIndex(where: { $0.id == rule.id }) {
                                    store.config.rules.insert(copy, at: i + 1)
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { store.config.rules.removeAll { $0.id == rule.id } }
                        }
                }
                .onMove { store.config.rules.move(fromOffsets: $0, toOffset: $1) }
                FallbackRow(highlighted: decision != nil && decision?.rule == nil)
            } header: {
                Text("Checked top to bottom — the first match wins")
            } footer: {
                Text("Tip: ⌘-click a browser in the picker to create a rule for that site instantly.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .themedForm()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = Rule() } label: { Label("New Rule", systemImage: "plus") }
                    .help("New Rule")
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, isNew: !store.config.rules.contains { $0.id == rule.id }) { saved in
                if let saved {
                    if let i = store.config.rules.firstIndex(where: { $0.id == saved.id }) {
                        store.config.rules[i] = saved
                    } else {
                        store.config.rules.append(saved)
                    }
                }
                editing = nil
            }
        }
    }

    private var testDecision: TestDecision? {
        let raw = testURL.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, var url = URL(string: raw.contains("://") ? raw : "https://" + raw), url.host != nil else { return nil }
        url = URLCleaner.clean(url, unwrap: store.config.unwrapRedirects, strip: store.config.stripTracking, custom: store.config.customTrackingParams)
        _ = store.config // observe changes
        switch routerBox.router.decide(LinkContext(url: url, sourceApp: testSource)) {
        case .open(let t, let rule): return TestDecision(url: url, rule: rule, target: catalog.resolve(t), missing: catalog.resolve(t) == nil)
        case .pick(let rule): return TestDecision(url: url, rule: rule, target: nil, missing: false)
        }
    }
}

struct TestDecision {
    var url: URL
    var rule: Rule?
    var target: PickTarget?
    var missing: Bool
}

private struct DecisionView: View {
    var decision: TestDecision

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: decision.rule == nil ? "arrow.turn.down.right" : "checkmark.circle.fill")
                .foregroundStyle(decision.rule == nil ? Color.secondary : Color.brandMint)
            VStack(alignment: .leading, spacing: 2) {
                Text(decision.rule.map { "Matches “\(ruleTitle($0))”" } ?? "No rule matches — using the default")
                    .font(.callout.weight(.medium))
                Text(decision.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            if let t = decision.target {
                TargetLabel(pick: t, size: 22)
            } else if decision.missing {
                Label("App not installed → picker", systemImage: "exclamationmark.triangle").foregroundStyle(Color.brandAmber)
            } else {
                Label("Picker", systemImage: "rectangle.stack")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct EmptyRules: View {
    var add: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: BrandGlyph.image(size: 34, color: Theme.faint))
            Text("No rules yet").font(.headline)
            Text("Send work links to your work profile, meetings to Zoom, everything else to the picker.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Create a Rule", action: add).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct RuleRow: View {
    @Environment(BrowserCatalog.self) private var catalog
    @Binding var rule: Rule
    var highlighted: Bool
    var edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(BrandSwitchStyle(mini: true))
            VStack(alignment: .leading, spacing: 2) {
                Text(ruleTitle(rule)).fontWeight(.medium)
                Text(conditionSummary(rule)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .opacity(rule.enabled ? 1 : 0.5)
            Spacer()
            Group {
                if let t = rule.target, let pick = catalog.resolve(t) {
                    TargetLabel(pick: pick, size: 20)
                } else if rule.target != nil {
                    Label("Missing app", systemImage: "exclamationmark.triangle").foregroundStyle(Color.brandAmber)
                } else {
                    Label("Picker", systemImage: "rectangle.stack").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .opacity(rule.enabled ? 1 : 0.5)
            Button("Edit", action: edit).buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(highlighted ? Color.brandMint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
    }
}

/// Always-last row: where links go when no rule above matches.
private struct FallbackRow: View {
    var highlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Everything else").fontWeight(.medium)
                Text("When no rule above matches").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            DefaultTargetPicker()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(highlighted ? Color.brandMint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .moveDisabled(true)
    }
}

@MainActor
func ruleTitle(_ r: Rule) -> String {
    let name = r.name.trimmingCharacters(in: .whitespaces)
    if !name.isEmpty { return name }
    guard let c = r.conditions.first(where: { !$0.value.isEmpty }) else { return "Untitled rule" }
    return c.field == .sourceApp ? "From \(appName(c.value))" : c.value
}

@MainActor
func conditionSummary(_ r: Rule) -> String {
    let parts = r.conditions.filter { !$0.value.isEmpty }.map { c in
        let v = c.field == .sourceApp ? appName(c.value) : c.value
        return "\(c.field.label.lowercased()) \(c.op.label) \(v)"
    }
    if parts.isEmpty { return "No conditions — never matches" }
    return parts.joined(separator: r.matchAll ? " and " : " or ")
}
