import AppKit

/// Raycast-style command bar for choosing a browser. Pure AppKit so it shows instantly.
@MainActor
final class PickerController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    typealias Completion = (PickTarget?, _ remember: Bool) -> Void

    private let url: URL
    private let catalog: BrowserCatalog
    private var completion: Completion?
    private let targets: [PickTarget]
    private var rows: [PickerRow] = []
    /// Indices into `targets` that match the search, in display order.
    private var visible: [Int] = []
    private var selected = 0
    private var panel: PickerPanel!
    private var search: NSTextField!
    private var list: NSStackView!
    private var scroll: NSScrollView!
    private var emptyLabel: NSTextField!
    private var actionLabel: NSTextField!
    private var resignObserver: NSObjectProtocol?

    private static let width: CGFloat = 640
    private static let maxRows = 8

    init(url: URL, catalog: BrowserCatalog, completion: @escaping Completion) {
        self.url = url
        self.catalog = catalog
        self.completion = completion
        self.targets = catalog.visibleTargets
        super.init()
        build()
    }

    // MARK: Building

    private func build() {
        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        // A layer corner radius doesn't clip the behind-window blur, which left square
        // corners around the rounded panel; a mask image shapes the blur and the shadow.
        root.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        root.layer?.cornerRadius = Self.cornerRadius
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        root.layer?.borderColor = Theme.line.cgColor

        // The website's panel: night indigo over a hint of blur.
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = Theme.surface.withAlphaComponent(0.94).cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tint)
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tint.topAnchor.constraint(equalTo: root.topAnchor),
            tint.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: Self.width),
        ])

        stack.addArrangedSubview(searchBar())
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(results())
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(footer())

        panel = PickerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.appearance = Theme.appearance
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = root
        panel.delegate = self
        panel.keyEquivalentHandler = { [weak self] e in self?.handleKeyEquivalent(e) ?? false }
        root.layoutSubtreeIfNeeded()
        panel.setContentSize(root.fittingSize)
        applyFilter()
    }

    private func searchBar() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 17, weight: .medium)
        icon.contentTintColor = Theme.faint
        icon.setContentHuggingPriority(.required, for: .horizontal)

        search = NSTextField()
        search.isBordered = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.font = .systemFont(ofSize: 20, weight: .regular)
        search.textColor = Theme.text
        search.placeholderAttributedString = NSAttributedString(string: "Open in…", attributes: [
            .foregroundColor: Theme.faint, .font: NSFont.systemFont(ofSize: 20, weight: .regular),
        ])
        search.delegate = self
        search.cell?.isScrollable = true
        search.cell?.wraps = false
        search.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let host = url.host ?? url.absoluteString
        let chip = Chip(text: host.hasPrefix("www.") ? String(host.dropFirst(4)) : host, symbol: "link")
        chip.toolTip = url.absoluteString
        chip.setContentHuggingPriority(.required, for: .horizontal)
        chip.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let h = NSStackView(views: [icon, search, chip])
        h.orientation = .horizontal
        h.alignment = .centerY
        h.spacing = 12
        h.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 16)
        h.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            h.widthAnchor.constraint(equalToConstant: Self.width),
            h.heightAnchor.constraint(equalToConstant: 60),
            chip.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
        ])
        return h
    }

    private func results() -> NSView {
        list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 2
        list.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
        list.translatesAutoresizingMaskIntoConstraints = false

        let header = label("Browsers & Profiles", size: 11.5, weight: .semibold, color: Theme.faint)
        let headerBox = NSStackView(views: [header])
        headerBox.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 2, right: 10)
        list.addArrangedSubview(headerBox)

        for (i, t) in targets.enumerated() {
            let row = PickerRow(pick: t, icon: catalog.icon(for: t.browser.bundleID, size: 28),
                                avatar: t.profile.map { avatarImage($0) })
            row.onHover = { [weak self] in
                guard let self, let pos = self.visible.firstIndex(of: i) else { return }
                self.select(pos)
            }
            row.onClick = { [weak self] flags in self?.choose(target: i, flags: flags) }
            rows.append(row)
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: Self.width - 16).isActive = true
        }

        emptyLabel = label(targets.isEmpty ? "No browsers found" : "No matching browser or profile",
                           size: 13, color: Theme.muted)
        let emptyBox = NSStackView(views: [emptyLabel])
        emptyBox.edgeInsets = NSEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        list.addArrangedSubview(emptyBox)

        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            list.topAnchor.constraint(equalTo: flipped.topAnchor),
            list.bottomAnchor.constraint(equalTo: flipped.bottomAnchor),
        ])

        scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = flipped
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // Fixed height, like Raycast: the window doesn't jump while you type.
        let rowsShown = CGFloat(min(max(targets.count, 3), Self.maxRows))
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: Self.width),
            scroll.heightAnchor.constraint(equalToConstant: rowsShown * (PickerRow.height + 2) + 40),
            flipped.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return scroll
    }

    private func footer() -> NSView {
        let linkIcon = NSImageView(image: NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!)
        linkIcon.contentTintColor = Theme.faint
        linkIcon.setContentHuggingPriority(.required, for: .horizontal)
        let link = label(url.absoluteString, size: 11.5, color: Theme.faint)
        link.lineBreakMode = .byTruncatingMiddle

        actionLabel = label("Open", size: 12, weight: .medium, color: Theme.text)
        actionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let hints = NSStackView(views: [
            actionLabel, KeyCap("↩"),
            divider(),
            label("Private", size: 12, color: Theme.muted), KeyCap("⇧"), KeyCap("↩"),
            divider(),
            label("Always here", size: 12, color: Theme.muted), KeyCap("⌘"), KeyCap("↩"),
        ])
        hints.spacing = 4
        hints.setHuggingPriority(.required, for: .horizontal)
        hints.setClippingResistancePriority(.required, for: .horizontal)

        let h = NSStackView(views: [linkIcon, link, hints])
        h.orientation = .horizontal
        h.alignment = .centerY
        h.spacing = 8
        h.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 12)
        h.wantsLayer = true
        h.layer?.backgroundColor = Theme.ink.withAlphaComponent(0.45).cgColor
        h.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            h.widthAnchor.constraint(equalToConstant: Self.width),
            h.heightAnchor.constraint(equalToConstant: 40),
        ])
        return h
    }

    private func divider() -> NSView {
        let v = Self.line()
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let wrap = NSStackView(views: [v])
        wrap.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        return wrap
    }

    private func separator() -> NSView {
        let v = Self.line()
        v.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private static let cornerRadius: CGFloat = 16

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let mask = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        return mask
    }

    private static func line() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = Theme.line.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Theme.text) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func avatarImage(_ p: BrowserProfile) -> NSImage {
        if let img = catalog.avatar(for: p) { return img }
        return Self.initialAvatar(p.name, color: p.color)
    }

    static func initialAvatar(_ name: String, color: UInt32?) -> NSImage {
        let size = NSSize(width: 32, height: 32)
        return NSImage(size: size, flipped: false) { rect in
            let fill: NSColor = color.map {
                NSColor(srgbRed: CGFloat(($0 >> 16) & 0xFF) / 255, green: CGFloat(($0 >> 8) & 0xFF) / 255,
                        blue: CGFloat($0 & 0xFF) / 255, alpha: 1)
            } ?? .systemGray
            fill.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let rgb = fill.usingColorSpace(.sRGB) ?? fill
            let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
            let ink: NSColor = luminance > 0.65 ? NSColor(white: 0.15, alpha: 1) : .white
            let initial = String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 17, weight: .bold),
                .foregroundColor: ink,
            ]
            let s = initial as NSString
            let sz = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2), withAttributes: attrs)
            return true
        }
    }

    // MARK: Showing

    func show() {
        // Top third of the screen under the cursor, like Spotlight / Raycast.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let vis = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        let top = vis.maxY - vis.height * 0.2
        panel.setFrameOrigin(NSPoint(x: vis.midX - size.width / 2, y: max(vis.minY + 20, top - size.height)))

        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
        (search.currentEditor() as? NSTextView)?.insertionPointColor = Theme.pink
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 1
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.finish(nil) } }
    }

    func close() { finish(nil) }

    var contentView: NSView? { panel.contentView }

    #if DEBUG
    func debugSearch(_ text: String) {
        search.stringValue = text
        applyFilter()
    }
    #endif

    func windowDidResignKey(_ notification: Notification) { finish(nil) }

    private func finish(_ choice: PickTarget?, remember: Bool = false) {
        guard let done = completion else { return }
        completion = nil
        if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
        panel.delegate = nil
        panel.orderOut(nil)
        done(choice, remember)
    }

    // MARK: Search

    func controlTextDidChange(_ obj: Notification) { applyFilter() }

    private func applyFilter() {
        let tokens = search.stringValue.lowercased().split(separator: " ").map(String.init)
        var matches: [(index: Int, score: Int)] = []
        for (i, t) in targets.enumerated() {
            let fields = [t.title, t.profile?.name ?? "", t.profile?.detail ?? ""].map { $0.lowercased() }
            let hay = fields.joined(separator: " ")
            guard tokens.allSatisfy({ hay.contains($0) }) else { continue }
            // Prefix hits on a name rank first.
            let score = tokens.reduce(0) { s, tok in
                s + (fields.contains { $0.hasPrefix(tok) } ? 0 : 1)
            }
            matches.append((i, score))
        }
        visible = matches.sorted { $0.score < $1.score || ($0.score == $1.score && $0.index < $1.index) }.map(\.index)

        // Re-order the rows to match ranking; header stays first, empty label last.
        for (i, row) in rows.enumerated() { row.isHidden = !visible.contains(i) }
        for (pos, i) in visible.enumerated() {
            list.removeArrangedSubview(rows[i])
            list.insertArrangedSubview(rows[i], at: pos + 1)
            rows[i].shortcut = pos < 9 ? "⌘\(pos + 1)" : nil
        }
        emptyLabel.superview?.isHidden = !visible.isEmpty
        select(0)
    }

    // MARK: Interaction

    private func select(_ pos: Int) {
        guard !visible.isEmpty else { actionLabel.stringValue = "Open"; return }
        selected = (pos + visible.count) % visible.count
        let current = visible[selected]
        for (i, r) in rows.enumerated() { r.isSelected = i == current }
        rows[current].scrollToVisible(rows[current].bounds.insetBy(dx: 0, dy: -8))
        let t = targets[current]
        actionLabel.stringValue = "Open in \(t.profile.map { "\(t.title) · \($0.name)" } ?? t.title)"
    }

    private func choose(target i: Int, flags: NSEvent.ModifierFlags) {
        guard targets.indices.contains(i) else { return }
        var pick = targets[i]
        if flags.contains(.shift) && pick.browser.engine.supportsPrivate { pick.target.privateWindow = true }
        finish(pick, remember: flags.contains(.command))
    }

    private func chooseSelected(flags: NSEvent.ModifierFlags) {
        guard visible.indices.contains(selected) else { NSSound.beep(); return }
        choose(target: visible[selected], flags: flags)
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        finish(nil)
    }

    /// Arrow keys, return and escape arrive as text-field commands while typing.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        switch selector {
        case #selector(NSResponder.moveDown(_:)): select(selected + 1)
        case #selector(NSResponder.moveUp(_:)): select(selected - 1)
        case #selector(NSResponder.insertNewline(_:)): chooseSelected(flags: flags)
        case #selector(NSResponder.cancelOperation(_:)):
            if search.stringValue.isEmpty { finish(nil) } else { search.stringValue = ""; applyFilter() }
        default: return false
        }
        return true
    }

    /// ⌘1–9 picks directly, ⌘↩ remembers, ⌘C copies the link (when no text is selected).
    private func handleKeyEquivalent(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return false }
        if e.keyCode == 36 || e.keyCode == 76 { chooseSelected(flags: flags); return true }
        let chars = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if let d = Int(chars), chars.count == 1, d >= 1 {
            guard visible.indices.contains(d - 1) else { NSSound.beep(); return true }
            choose(target: visible[d - 1], flags: flags.subtracting(.command))
            return true
        }
        if chars == "c", (search.currentEditor()?.selectedRange.length ?? 0) == 0 { copyLink(); return true }
        return false
    }
}

final class PickerPanel: NSPanel {
    var keyEquivalentHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyEquivalentHandler?(event) == true || super.performKeyEquivalent(with: event)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Small rounded key, like the shortcut hints in Raycast's action bar.
private final class KeyCap: NSView {
    init(_ text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = Theme.raised.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.line.cgColor
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = Theme.muted
        l.alignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        addSubview(l)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            l.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            l.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            l.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Pill showing the link's site next to the search field.
private final class Chip: NSView {
    init(text: String, symbol: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Theme.violet.withAlphaComponent(0.14).cgColor
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = Theme.violet
        icon.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12.5, weight: .medium)
        l.textColor = Theme.violet
        l.lineBreakMode = .byTruncatingMiddle
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let s = NSStackView(views: [icon, l])
        s.spacing = 5
        s.edgeInsets = NSEdgeInsets(top: 4, left: 9, bottom: 4, right: 10)
        s.translatesAutoresizingMaskIntoConstraints = false
        addSubview(s)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            s.leadingAnchor.constraint(equalTo: leadingAnchor),
            s.trailingAnchor.constraint(equalTo: trailingAnchor),
            s.topAnchor.constraint(equalTo: topAnchor),
            s.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class PickerRow: NSView {
    static let height: CGFloat = 44

    var onHover: (() -> Void)?
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var isSelected = false { didSet { if oldValue != isSelected { updateColors() } } }
    var shortcut: String? {
        didSet { keyCap.stringValue = shortcut ?? ""; keyCap.isHidden = shortcut == nil }
    }

    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let keyCap = NSTextField(labelWithString: "")
    private var lastMouse: NSPoint?

    init(pick: PickTarget, icon: NSImage, avatar: NSImage?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true

        let iconView = NSImageView(image: icon)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // Raycast puts the secondary text inline, right after the title.
        title.stringValue = pick.title
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = Theme.text
        title.setContentHuggingPriority(.required, for: .horizontal)
        subtitle.stringValue = pick.subtitle ?? ""
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = Theme.muted
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.isHidden = pick.subtitle == nil

        var views: [NSView] = [title, subtitle]
        if pick.target.privateWindow {
            let eye = NSImageView(image: NSImage(systemSymbolName: "eyeglasses", accessibilityDescription: "Private")!)
            eye.contentTintColor = Theme.muted
            views.append(eye)
        }
        let texts = NSStackView(views: views)
        texts.spacing = 8
        texts.translatesAutoresizingMaskIntoConstraints = false
        addSubview(texts)

        keyCap.font = .systemFont(ofSize: 12, weight: .medium)
        keyCap.textColor = Theme.faint
        keyCap.alignment = .right
        keyCap.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyCap)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            texts.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: keyCap.leadingAnchor, constant: -12),
            keyCap.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            keyCap.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        if let avatar {
            let badge = NSImageView(image: avatar)
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 8
            badge.layer?.masksToBounds = true
            badge.layer?.borderWidth = 1.5
            badge.layer?.borderColor = Theme.surface.cgColor
            badge.imageScaling = .scaleProportionallyUpOrDown
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.widthAnchor.constraint(equalToConstant: 16),
                badge.heightAnchor.constraint(equalToConstant: 16),
                badge.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 3),
                badge.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 2),
            ])
        }
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    // Only follow the mouse when it actually moves, so scrolling via keyboard
    // doesn't get hijacked by a row that slides under a resting cursor.
    override func mouseMoved(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        if p != lastMouse { lastMouse = p; onHover?() }
    }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        // Selected like the website's picker: a raised row with a pink edge.
        layer?.backgroundColor = isSelected ? Theme.raised.cgColor : NSColor.clear.cgColor
        layer?.borderWidth = isSelected ? 1 : 0
        layer?.borderColor = Theme.pink.withAlphaComponent(0.4).cgColor
        keyCap.textColor = isSelected ? Theme.muted : Theme.faint
    }
}
