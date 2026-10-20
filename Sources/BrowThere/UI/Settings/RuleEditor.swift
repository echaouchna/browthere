import AppKit
import SwiftUI

struct RuleEditor: View {
    @Environment(BrowserCatalog.self) private var catalog
    @State var rule: Rule
    var isNew: Bool
    var done: (Rule?) -> Void
    @State private var sample = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: BrandGlyph.symbol, tint: .brandPink, size: 34)
                TextField("Rule name", text: $rule.name, prompt: Text(ruleTitle(rule)))
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                Toggle("Enabled", isOn: $rule.enabled).toggleStyle(BrandSwitchStyle())
            }
            .padding(20)

            Form {
                Section {
                    ForEach($rule.conditions) { $c in
                        ConditionRow(condition: $c, canDelete: rule.conditions.count > 1) {
                            rule.conditions.removeAll { $0.id == c.id }
                        }
                    }
                    Button {
                        rule.conditions.append(Condition())
                    } label: { Label("Add Condition", systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderless)
                } header: {
                    HStack {
                        Text("If")
                        if rule.conditions.count > 1 {
                            Picker("", selection: $rule.matchAll) {
                                Text("all").tag(true)
                                Text("any").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            Text("of these match")
                        }
                    }
                }

                Section("Then open in") {
                    TargetPicker(target: $rule.target, askLabel: "Show the picker")
                    if let t = rule.target, catalog.resolve(t)?.browser.engine.supportsPrivate == true {
                        PrivateWindowToggle(isOn: Binding(
                            get: { rule.target?.privateWindow ?? false },
                            set: { rule.target?.privateWindow = $0 }
                        ))
                    }
                }

                Section("Try it") {
                    HStack {
                        TextField("", text: $sample, prompt: Text("Paste a link to check this rule"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                        if let ok = sampleMatches {
                            Label(ok ? "Matches" : "No match", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(ok ? Color.brandMint : .secondary)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
            .themedForm()

            HStack {
                if !isNew {
                    Text("Changes apply right away when saved.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { done(nil) }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Rule" : "Save") { done(rule) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.brand)
                    .disabled(!rule.conditions.contains { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty })
            }
            .padding(20)
        }
        .frame(width: 620, height: 560)
        .background(Color.brandInk)
        .tint(.brandPink)
        .toggleStyle(BrandSwitchStyle())
    }

    private var sampleMatches: Bool? {
        let raw = sample.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, let url = URL(string: raw.contains("://") ? raw : "https://" + raw) else { return nil }
        // Source-app conditions can't be sampled; treat them as satisfied.
        var r = rule
        r.enabled = true
        let hasSource = r.conditions.contains { $0.field == .sourceApp }
        if hasSource {
            if r.matchAll { r.conditions.removeAll { $0.field == .sourceApp } }
            if r.conditions.isEmpty { return true }
        }
        return RuleEngine.matches(r, LinkContext(url: url, sourceApp: nil))
    }
}

private struct ConditionRow: View {
    @Binding var condition: Condition
    var canDelete: Bool
    var delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row
            if let siteHint {
                Text(siteHint)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 138)
            }
        }
    }

    /// Spells out what a site value covers, e.g. "gitlab.com and its subdomains, under /group".
    private var siteHint: String? {
        guard condition.op == .isDomain || condition.op == .isUnder,
              !condition.value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let (domain, path) = RuleEngine.parseSite(condition.value)
        guard !domain.isEmpty else { return nil }
        if let path { return "Matches \(domain) (and subdomains), only \(path) and pages below it" }
        return "Matches \(domain) and all its subdomains"
    }

    private var row: some View {
        HStack(spacing: 8) {
            Picker("", selection: $condition.field) {
                ForEach(ConditionField.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130, alignment: .leading)
            .onChange(of: condition.field) { _, f in
                if !f.operators.contains(condition.op) { condition.op = f.operators[0] }
                if f == .sourceApp || condition.value.contains(".") == false { condition.value = "" }
            }

            if condition.field == .sourceApp {
                Text("is").foregroundStyle(.secondary)
                SourceAppPicker(bundleID: Binding(
                    get: { condition.value.isEmpty ? nil : condition.value },
                    set: { condition.value = $0 ?? "" }
                ), emptyLabel: "Choose app…")
                Spacer()
            } else {
                Picker("", selection: $condition.op) {
                    ForEach(condition.field.operators, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150, alignment: .leading)

                TextField("", text: $condition.value, prompt: Text(placeholder))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .font(.body.monospaced())
                    .foregroundStyle(isInvalid ? .red : .primary)
                    .help(isInvalid ? "Invalid regular expression" : "")
            }

            Button(action: delete) {
                Image(systemName: "minus.circle.fill").foregroundStyle(canDelete ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canDelete)
        }
    }

    private var isInvalid: Bool {
        condition.op == .regex && !condition.value.isEmpty && !RuleEngine.isValidRegex(condition.value)
    }

    private var placeholder: String {
        switch (condition.field, condition.op) {
        case (.host, .isDomain): "github.com or gitlab.com/my-group"
        case (.url, .isUnder): "https://gitlab.com/my-group"
        case (.host, .wildcard): "*.atlassian.net"
        case (_, .regex): "^https://(www\\.)?zoom\\.us/j/"
        case (.url, .wildcard): "https://*.google.com/*/docs/*"
        case (.path, _): "/meet"
        default: "example.com"
        }
    }
}

/// Menu of running apps, plus "Choose…" to pick any app from disk.
struct SourceAppPicker: View {
    @Binding var bundleID: String?
    var emptyLabel: String

    var body: some View {
        Menu {
            if bundleID != nil {
                Button(emptyLabel) { bundleID = nil }
                Divider()
            }
            ForEach(runningApps, id: \.self) { id in
                Button {
                    bundleID = id
                } label: {
                    Label {
                        Text(appName(id))
                    } icon: {
                        Image(nsImage: smallIcon(id))
                    }
                }
            }
            Divider()
            Button("Choose…") { if let id = chooseApp() { bundleID = id } }
        } label: {
            if let id = bundleID {
                Label {
                    Text(appName(id))
                } icon: {
                    Image(nsImage: smallIcon(id))
                }
            } else {
                Text(emptyLabel)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var runningApps: [String] {
        let own = Bundle.main.bundleIdentifier
        let ids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { $0 != own }
        return Array(Set(ids)).sorted { appName($0).localizedCaseInsensitiveCompare(appName($1)) == .orderedAscending }
    }

    private func smallIcon(_ id: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return NSImage() }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 16, height: 16)
        return img
    }
}
