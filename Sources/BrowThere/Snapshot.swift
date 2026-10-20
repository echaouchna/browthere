#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: renders the picker and every settings pane to PNGs, then quits.
extension AppDelegate {
    func snapshot(to dir: String) {
        // The app is always dark (see Theme), so there's a single pass.
        // A tool-launched process can't take focus, so windows claim to be key; otherwise
        // accent colors render gray, as in any inactive window.
        for suffix in ["dark"] {
            for pane in SettingsPane.allCases {
                let view = SettingsRoot(pane: pane)
                    .environment(store).environment(catalog).environment(RouterBox(router: router))
                let host = NSHostingController(rootView: view)
                host.sceneBridgingOptions = [.toolbars, .title]
                let window = SnapshotWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                                      styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                window.titlebarAppearsTransparent = true
                window.toolbarStyle = .unified
                window.contentViewController = host
                window.setContentSize(NSSize(width: 860, height: 600))
                window.makeKeyAndOrderFront(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                if let frameView = window.contentView?.superview { save(frameView, "\(dir)/settings-\(pane.rawValue)-\(suffix).png") }
                window.orderOut(nil)
            }
            if let rule = store.config.rules.dropFirst().first {
                let host = NSHostingView(rootView: RuleEditor(rule: rule, isNew: false) { _ in }.environment(catalog))
                let window = SnapshotWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                save(host, "\(dir)/rule-editor-\(suffix).png")
                window.orderOut(nil)
            }
            let picker = PickerController(url: URL(string: "https://github.com/echaouchna/browthere/pulls?q=is%3Aopen")!,
                                          catalog: catalog) { _, _ in }
            picker.show()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            if let v = picker.contentView { save(v, "\(dir)/picker-\(suffix).png") }
            picker.debugSearch("serv")
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            if let v = picker.contentView { save(v, "\(dir)/picker-search-\(suffix).png") }
            picker.close()
        }
        // The menu bar icon, at its real size and enlarged, on light and dark bars.
        for (size, scale) in [(18.0, 1.0), (18.0, 6.0)] {
            for (name, bar, ink) in [("light", NSColor(white: 0.93, alpha: 1), NSColor.black), ("dark", NSColor(white: 0.16, alpha: 1), NSColor.white)] {
                let px = Int(size * scale * 2)
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px + 16, pixelsHigh: px + 16, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                bar.setFill(); NSRect(x: 0, y: 0, width: px + 16, height: px + 16).fill()
                BrandGlyph.image(size: CGFloat(px), color: ink, lineWidth: 72).draw(in: NSRect(x: 8, y: 8, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/menubar-\(Int(scale))x-\(name).png"))
            }
        }
        NSApp.terminate(nil)
    }

    private final class SnapshotWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
    }

    private func save(_ view: NSView, _ path: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
