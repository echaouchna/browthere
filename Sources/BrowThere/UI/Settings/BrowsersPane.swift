import SwiftUI

struct BrowsersPane: View {
    @Environment(ConfigStore.self) private var store
    @Environment(BrowserCatalog.self) private var catalog
    @State private var editing: CustomProfile?

    var body: some View {
        @Bindable var store = store
        let targets = catalog.allTargets
        Form {
            Section {
                ForEach(targets) { t in
                    TargetRow(pick: t, hidden: store.config.hiddenTargets.contains(t.id)) {
                        if store.config.hiddenTargets.contains(t.id) {
                            store.config.hiddenTargets.remove(t.id)
                        } else {
                            store.config.hiddenTargets.insert(t.id)
                        }
                    }
                }
                .onMove { from, to in
                    var keys = targets.map(\.id)
                    keys.move(fromOffsets: from, toOffset: to)
                    store.config.targetOrder = keys
                }
            } header: {
                Text("Picker")
            } footer: {
                Text("Drag to reorder what the picker shows. The first nine get the shortcuts ⌘1–⌘9.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                ForEach(catalog.listedBrowsers, id: \.bundleID) { b in
                    BrowserProfilesRow(browser: b) { editing = $0 }
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Profiles are read from Chrome, Edge, Brave, Vivaldi, Helium and other Chromium builds, Firefox, Zen and other Gecko browsers automatically. For anything else, add them by hand.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Detection") {
                Toggle(isOn: $store.config.hideDetectedProfiles) {
                    Text("Ignore detected profiles")
                    Text("Only use the profiles you added by hand.")
                }
                Toggle(isOn: $store.config.includeNonBrowsers) {
                    Text("Include apps that aren't browsers")
                    Text("Apps like ChatGPT or terminals also register for web links. Any app can still be a rule target.")
                }
            }
        }
        .themedForm()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { catalog.refresh() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .help("Look for new browsers and profiles")
            }
        }
        .sheet(item: $editing) { p in
            CustomProfileSheet(profile: p, isNew: !store.config.customProfiles.contains { $0.id == p.id }) { saved in
                if let saved {
                    if let i = store.config.customProfiles.firstIndex(where: { $0.id == saved.id }) {
                        store.config.customProfiles[i] = saved
                    } else {
                        store.config.customProfiles.append(saved)
                    }
                }
                editing = nil
            }
        }
    }
}

private struct TargetRow: View {
    var pick: PickTarget
    var hidden: Bool
    var toggle: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            TargetLabel(pick: pick)
                .opacity(hidden ? 0.4 : 1)
            if pick.profile?.isCustom == true {
                Text("Custom").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            Button(action: toggle) {
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .foregroundStyle(hidden ? Color.secondary : Color.brandPink)
                    .frame(width: 24)
            }
            .buttonStyle(.borderless)
            .help(hidden ? "Show in picker" : "Hide from picker")
        }
        .padding(.vertical, 2)
    }
}

private struct BrowserProfilesRow: View {
    @Environment(ConfigStore.self) private var store
    var browser: Browser
    var edit: (CustomProfile) -> Void

    var body: some View {
        let custom = store.config.customProfiles.filter { $0.bundleID == browser.bundleID }
        DisclosureGroup {
            if !browser.profiles.isEmpty {
                ForEach(browser.profiles, id: \.id) { p in
                    HStack {
                        ProfileBadge(profile: p, size: 18)
                        Text(p.name)
                        if let d = p.detail { Text(d).foregroundStyle(.secondary) }
                        Spacer()
                        Text("Detected").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(custom) { c in
                HStack {
                    ProfileBadge(profile: BrowserProfile(id: c.id.uuidString, name: c.name, launch: .arguments("")), size: 18)
                    Text(c.name)
                    Text(c.value).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Edit") { edit(c) }.buttonStyle(.borderless)
                    Button(role: .destructive) {
                        store.config.customProfiles.removeAll { $0.id == c.id }
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
            Button {
                edit(CustomProfile(bundleID: browser.bundleID, name: "", style: defaultStyle, value: ""))
            } label: { Label("Add Profile…", systemImage: "plus.circle") }
                .buttonStyle(.borderless)
        } label: {
            HStack(spacing: 10) {
                AppIconView(bundleID: browser.bundleID, size: 24)
                Text(browser.name).fontWeight(.medium)
                EngineBadge(engine: browser.engine)
                Spacer()
                Text(summary(custom.count)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var defaultStyle: ProfileLaunchStyle {
        if browser.bundleID == Discovery.arcBundleID { return .arcSpace }
        return switch browser.engine {
        case .chromium: .chromiumFolder
        case .firefox: .firefoxName
        default: .arguments
        }
    }

    private func summary(_ custom: Int) -> String {
        let n = browser.profiles.count + custom
        let noun = browser.bundleID == Discovery.arcBundleID ? "space" : "profile"
        if n == 0 { return browser.engine == .safari ? "Profiles not scriptable" : "No \(noun)s" }
        return n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }
}

private struct EngineBadge: View {
    var engine: Engine
    var body: some View {
        let (text, color): (String, Color) = switch engine {
        case .chromium: ("Chromium", .brandViolet)
        case .firefox: ("Gecko", .brandAmber)
        case .safari: ("WebKit", .brandMint)
        case .other: ("App", .gray)
        }
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct CustomProfileSheet: View {
    @Environment(BrowserCatalog.self) private var catalog
    @State var profile: CustomProfile
    var isNew: Bool
    var done: (CustomProfile?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AppIconView(bundleID: profile.bundleID, size: 40)
                VStack(alignment: .leading) {
                    Text(isNew ? "Add Profile" : "Edit Profile").font(.title3.weight(.semibold))
                    Text(catalog.browser(profile.bundleID)?.name ?? profile.bundleID).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Form {
                TextField("Name", text: $profile.name, prompt: Text("Work"))
                Picker("Launch with", selection: $profile.style) {
                    ForEach(ProfileLaunchStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField(valueLabel, text: $profile.value, prompt: Text(profile.style.placeholder))
                    .font(.body.monospaced())
            }
            .themedForm()
            .scrollDisabled(true)

            Text(help)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { done(nil) }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { done(profile) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.brand)
                    .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || profile.value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 460)
        .background(Color.brandInk)
        .tint(.brandPink)
    }

    private var valueLabel: String {
        switch profile.style {
        case .chromiumFolder: "Folder"
        case .firefoxName: "Profile"
        case .arguments: "Arguments"
        case .arcSpace: "Space"
        }
    }

    private var help: String {
        switch profile.style {
        case .chromiumFolder:
            "The folder name of the profile, e.g. “Default” or “Profile 2”. Find it at chrome://version → Profile Path."
        case .firefoxName:
            "The profile name as listed at about:profiles."
        case .arguments:
            "Arguments passed to a new instance of the app. {url} is replaced by the link; if it's missing the link is added at the end."
        case .arcSpace:
            "The space's name exactly as it appears in Arc's sidebar. Links open as a new tab in that space."
        }
    }
}
