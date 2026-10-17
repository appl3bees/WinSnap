import AppKit

/// After a snap, offers the other open windows to fill each remaining zone of the layout.
final class SnapAssist {
    static let shared = SnapAssist()

    private var queue: [CGRect] = []
    private var screen: NSScreen?
    private var placed: [WindowRef] = []
    private var panel: KeyablePanel?
    private var clickMonitor: Any?

    func begin(after w: WindowRef, layout: Int, zone: Int, screen: NSScreen) {
        end(raise: false)
        let zones = Layouts.all[layout].zones
        queue = zones.indices.filter { $0 != zone }.map { zones[$0] }
        self.screen = screen
        placed = [w]
        // Give the snapped window a moment to settle before covering the rest of the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.showNext() }
    }

    private func showNext() {
        closePanel()
        guard let screen, !queue.isEmpty else { return end(raise: true) }
        let candidates = AX.standardWindows().filter { !placed.contains($0) }
        guard !candidates.isEmpty else { return end(raise: true) }

        let unit = queue.removeFirst()
        let frame = Layouts.frame(for: unit, on: screen).insetBy(dx: 6, dy: 6)
        let grid = AssistGridView(windows: candidates) { [weak self] picked in
            self?.pick(picked, unit: unit)
        }
        let p = UI.panel(size: frame.size, content: grid, radius: 12, keyable: true) as! KeyablePanel
        p.level = .floating
        p.onCancel = { [weak self] in self?.end(raise: true) }
        p.setFrame(frame, display: true)
        panel = p

        NSApp.activate(ignoringOtherApps: true)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }

        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.end(raise: false)
            }
        }
    }

    private func pick(_ w: WindowRef, unit: CGRect) {
        guard let screen else { return }
        placed.append(w)
        Snapper.snap(w, unit: unit, screen: screen)
        showNext()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Ends the session; when `raise` is set, brings every placed window forward, the first-snapped one last so it gets focus.
    private func end(raise: Bool) {
        closePanel()
        if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
        if raise {
            for w in placed.reversed() { w.raise() }
        }
        queue = []
        placed = []
        screen = nil
    }
}

/// Grid of window tiles (app icon + title) shown inside an empty zone.
final class AssistGridView: NSView {
    private let scroll = NSScrollView()
    private let doc = FlippedView()
    private var tiles: [WindowTile] = []

    static let tileSize = NSSize(width: 180, height: 120)
    static let gap: CGFloat = 14

    init(windows: [WindowRef], onPick: @escaping (WindowRef) -> Void) {
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = doc
        scroll.autoresizingMask = [.width, .height]
        addSubview(scroll)
        tiles = windows.map { w in WindowTile(window: w) { onPick(w) } }
        tiles.forEach(doc.addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        let t = Self.tileSize, g = Self.gap
        let width = scroll.contentSize.width
        let cols = max(1, Int((width - g) / (t.width + g)))
        let rows = (tiles.count + cols - 1) / cols
        let usedW = CGFloat(min(cols, tiles.count)) * (t.width + g) - g
        let docH = CGFloat(rows) * (t.height + g) + g
        let height = max(docH, scroll.contentSize.height)
        let x0 = max(g, (width - usedW) / 2)
        let y0 = max(g, (height - docH) / 2 + g)
        doc.frame = NSRect(x: 0, y: 0, width: width, height: height)
        for (i, tile) in tiles.enumerated() {
            tile.frame = NSRect(x: x0 + CGFloat(i % cols) * (t.width + g),
                                y: y0 + CGFloat(i / cols) * (t.height + g),
                                width: t.width, height: t.height)
        }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class WindowTile: NSView {
    private let action: () -> Void
    private var hovering = false { didSet { updateLayer() } }

    init(window w: WindowRef, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1

        let app = w.app
        let icon = NSImageView(image: app?.icon ?? NSImage(named: NSImage.applicationIconName)!)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.frame = NSRect(x: 0, y: 0, width: 52, height: 52)

        let title = NSTextField(labelWithString: (w.title?.isEmpty == false ? w.title : app?.localizedName) ?? "Window")
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.alignment = .center
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 2
        title.cell?.wraps = true

        let appName = NSTextField(labelWithString: app?.localizedName ?? "")
        appName.font = .systemFont(ofSize: 10)
        appName.textColor = .secondaryLabelColor
        appName.alignment = .center
        appName.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [icon, title, appName])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 52),
            icon.heightAnchor.constraint(equalToConstant: 52),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            title.widthAnchor.constraint(lessThanOrEqualToConstant: 164),
            appName.widthAnchor.constraint(lessThanOrEqualToConstant: 164),
        ])
        updateLayer()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = (hovering ? NSColor.controlAccentColor.withAlphaComponent(0.35)
                                           : NSColor.labelColor.withAlphaComponent(0.07)).cgColor
        layer?.borderColor = (hovering ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.15)).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}
