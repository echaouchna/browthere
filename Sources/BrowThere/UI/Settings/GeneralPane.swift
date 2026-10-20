import AppKit
import SwiftUI

/// Landing page: status card (like a server status) and the fallback for unmatched links.
struct OverviewPane: View {
    @Environment(ConfigStore.self) private var store
    @Environment(BrowserCatalog.self) private var catalog
    @State private var isDefault = DefaultBrowser.isDefault

    var body: some View {
        let rules = store.config.rules.filter(\.enabled).count
        let browsers = catalog.listedBrowsers.count
        let profiles = catalog.allTargets.filter { $0.profile != nil }.count
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BrowThere").font(.title3.weight(.semibold))
                        HStack(spacing: 6) {
                            Circle().fill(isDefault ? Color.brandMint : Color.brandAmber).frame(width: 8, height: 8)
                            Text(isDefault ? "Default browser" : "Not the default browser").foregroundStyle(.secondary)
                        }
                        Text(isDefault
                             ? "Routing links with \(rules) active \(rules == 1 ? "rule" : "rules") across \(browsers) browsers and \(profiles) profiles."
                             : "Links won't reach BrowThere until you make it your default browser.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !isDefault {
                        Button("Make Default…") { DefaultBrowser.makeDefault() }
                            .buttonStyle(.brand)
                    }
                }
                .padding(.vertical, 6)

                SettingRow(title: "Config file", subtitle: ConfigStore.fileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL]) } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    .help("Show in Finder")
                }
            }

            Section("When no rule matches") {
                SettingRow(title: "Open links in", subtitle: "Used for every link that none of your rules catch.") {
                    DefaultTargetPicker()
                }
                SettingRow(title: "Choose every time", subtitle: "Hold ⌥ Option while clicking a link to show the picker, whatever the rules say.") {
                    Text("⌥ + click").font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
        .themedForm()
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            isDefault = DefaultBrowser.isDefault
        }
    }
}

struct CleaningPane: View {
    @Environment(ConfigStore.self) private var store
    @State private var newParam = ""

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle(isOn: $store.config.unwrapRedirects) {
                    Text("Unwrap redirect links")
                    Text("Open the real destination of Outlook and Teams Safe Links, Google, Facebook, Instagram, Slack, LinkedIn and YouTube redirects, so rules see the actual site.")
                }
                Toggle(isOn: $store.config.stripTracking) {
                    Text("Remove tracking parameters")
                    Text("Drop utm_*, fbclid, gclid, msclkid, mc_eid and similar parameters, plus YouTube's si and is share IDs, before the link is opened.")
                }
            }

            Section {
                ForEach(store.config.customTrackingParams, id: \.self) { entry in
                    HStack {
                        Text(entry).font(.body.monospaced())
                        Spacer()
                        Text(scope(of: entry)).font(.callout).foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            store.config.customTrackingParams.removeAll { $0 == entry }
                        } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Remove")
                    }
                }
                HStack {
                    TextField("Parameter", text: $newParam, prompt: Text("ref, share_*, example.com:src"))
                        .font(.body.monospaced())
                        .labelsHidden()
                        .onSubmit(add)
                    Button("Add", action: add)
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                        .disabled(normalized(newParam).isEmpty)
                }
            } header: {
                Text("Your parameters")
            } footer: {
                Text("A name strips it everywhere, name* strips every parameter starting with it, and domain:name only on that site and its subdomains.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!store.config.stripTracking)
        }
        .themedForm()
    }

    private func normalized(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: " ", with: "")
    }

    private func add() {
        let entry = normalized(newParam)
        guard !entry.isEmpty else { return }
        if !store.config.customTrackingParams.contains(entry) { store.config.customTrackingParams.append(entry) }
        newParam = ""
    }

    private func scope(of entry: String) -> String {
        if let colon = entry.firstIndex(of: ":") { return "on \(entry[..<colon])" }
        return entry.hasSuffix("*") ? "starts with, everywhere" : "everywhere"
    }
}

struct GeneralPane: View {
    @Environment(ConfigStore.self) private var store
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    @State private var loginError: String?

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Startup") {
                Toggle(isOn: $launchAtLogin) {
                    Text("Open at login")
                    Text("Starts quietly in the background so links are routed right after you log in.")
                }
                .onChange(of: launchAtLogin) { _, on in
                    guard on != LoginItem.isEnabled else { return }
                    loginError = LoginItem.set(on)
                    refreshLoginItem()
                }
                if loginNeedsApproval {
                    SettingRow(title: "Waiting for approval", subtitle: "Allow BrowThere in System Settings → Login Items to finish turning this on.") {
                        Button("Open Login Items…") { LoginItem.openSystemSettings() }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                } else if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
            }

            Section("Menu bar") {
                Toggle(isOn: $store.config.showMenuBarIcon) {
                    Text("Show in menu bar")
                    Text(store.config.showMenuBarIcon
                         ? "Quick access to settings and opening the link on your clipboard."
                         : "Open BrowThere again from Finder or Spotlight to get back here.")
                }
            }

            Section("Picker") {
                SettingRow(title: "Search", subtitle: "Just start typing to filter browsers, profiles and account emails.") {
                    EmptyView()
                }
                SettingRow(title: "Remember a choice", subtitle: "⌘↩ or ⌘-click to always open that site there.") {
                    Text("⌘ ↩").font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                SettingRow(title: "Private window", subtitle: "⇧↩ or ⇧-click to open the link in a private window.") {
                    Text("⇧ ↩").font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                SettingRow(title: "Keyboard", subtitle: "⌘1–⌘9 pick directly, ↑↓ and ↩ select, ⌘C copies the link, esc clears the search or closes.") {
                    EmptyView()
                }
            }
        }
        .themedForm()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginItem()
        }
        .onAppear(perform: refreshLoginItem)
    }

    private func refreshLoginItem() {
        launchAtLogin = LoginItem.isEnabled || LoginItem.needsApproval
        loginNeedsApproval = LoginItem.needsApproval
    }
}
