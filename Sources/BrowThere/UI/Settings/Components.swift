import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppIconView: View {
    @Environment(BrowserCatalog.self) private var catalog
    var bundleID: String
    var size: CGFloat = 22

    var body: some View {
        Image(nsImage: catalog.icon(for: bundleID, size: 64))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct ProfileBadge: View {
    @Environment(BrowserCatalog.self) private var catalog
    var profile: BrowserProfile
    var size: CGFloat = 14

    var body: some View {
        Image(nsImage: catalog.avatar(for: profile) ?? PickerController.initialAvatar(profile.name, color: profile.color))
            .resizable()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
    }
}

/// Browser icon with the profile avatar tucked in the corner.
struct TargetIcon: View {
    var pick: PickTarget
    var size: CGFloat = 26

    var body: some View {
        AppIconView(bundleID: pick.browser.bundleID, size: size)
            .overlay(alignment: .bottomTrailing) {
                if let p = pick.profile {
                    ProfileBadge(profile: p, size: size * 0.52).offset(x: 3, y: 2)
                }
            }
    }
}

struct TargetLabel: View {
    var pick: PickTarget
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: 10) {
            TargetIcon(pick: pick, size: size)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(pick.title).fontWeight(.medium)
                    if pick.target.privateWindow {
                        Image(systemName: "eyeglasses").font(.caption).foregroundStyle(.secondary).help("Private window")
                    }
                }
                if let s = pick.subtitle {
                    Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .fixedSize()
        }
    }
}

/// Lets the user pick "Ask me", any browser/profile, or any other app.
struct TargetPicker: View {
    @Environment(BrowserCatalog.self) private var catalog
    @Binding var target: Target?
    var askLabel = "Show the picker"

    var body: some View {
        HStack(spacing: 10) {
            current
            menu
        }
    }

    @ViewBuilder private var current: some View {
        if let t = target, let pick = catalog.resolve(t) {
            TargetLabel(pick: pick, size: 22)
        } else if target != nil {
            Label("Missing app", systemImage: "exclamationmark.triangle").foregroundStyle(Color.brandAmber)
        } else {
            Label(askLabel, systemImage: "rectangle.stack").foregroundStyle(.secondary)
        }
    }

    private var menu: some View {
        Menu {
            Button { target = nil } label: { Label(askLabel, systemImage: "rectangle.stack") }
            Divider()
            ForEach(catalog.allTargets) { t in
                Button {
                    target = Target(bundleID: t.target.bundleID, profile: t.target.profile,
                                    privateWindow: target?.privateWindow ?? false)
                } label: {
                    Label {
                        Text(t.subtitle.map { "\(t.title) — \($0)" } ?? t.title)
                    } icon: {
                        Image(nsImage: catalog.icon(for: t.browser.bundleID, size: 16))
                    }
                }
            }
            Divider()
            Button("Other App…") {
                if let id = chooseApp() { target = Target(bundleID: id) }
            }
        } label: {
            Text("Change")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
    }
}

/// Full-width, self-explanatory switch for opening in incognito / private browsing.
struct PrivateWindowToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                Text("Open in a private window")
                Text("Incognito in Chromium browsers, Private Browsing in Firefox and Zen. History and cookies aren't kept.")
            } icon: {
                Image(systemName: "eyeglasses")
            }
        }
        .toggleStyle(BrandSwitchStyle())
    }
}

/// The fallback browser/profile used when no rule matches, with a private-window switch when supported.
struct DefaultTargetPicker: View {
    @Environment(ConfigStore.self) private var store
    @Environment(BrowserCatalog.self) private var catalog

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 12) {
            TargetPicker(target: $store.config.defaultTarget)
            if let t = store.config.defaultTarget, catalog.resolve(t)?.browser.engine.supportsPrivate == true {
                Toggle("Private window", isOn: Binding(
                    get: { store.config.defaultTarget?.privateWindow ?? false },
                    set: { store.config.defaultTarget?.privateWindow = $0 }
                ))
                .toggleStyle(.checkbox)
                .fixedSize()
            }
        }
    }
}

@MainActor
func chooseApp() -> String? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.prompt = "Choose"
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return Bundle(url: url)?.bundleIdentifier
}

@MainActor
func appName(_ bundleID: String) -> String {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map(Discovery.displayName) ?? bundleID
}
