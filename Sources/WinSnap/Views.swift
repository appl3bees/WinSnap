import AppKit

enum UI {
    /// Stretchable rounded mask so NSVisualEffectView gets real rounded corners.
    static func roundedMask(_ radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.set()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }

    static func blurView(radius: CGFloat, material: NSVisualEffectView.Material = .hudWindow) -> NSVisualEffectView {
        let fx = NSVisualEffectView()
        fx.material = material
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.maskImage = roundedMask(radius)
        return fx
    }

    static func panel(size: NSSize, content: NSView, radius: CGFloat = 12, keyable: Bool = false) -> NSPanel {
        let rect = NSRect(origin: .zero, size: size)
        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        let panel = keyable
            ? KeyablePanel(contentRect: rect, styleMask: style, backing: .buffered, defer: true)
            : NSPanel(contentRect: rect, styleMask: style, backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let fx = blurView(radius: radius)
        fx.frame = NSRect(origin: .zero, size: size)
        fx.autoresizingMask = [.width, .height]
        content.frame = fx.bounds
        content.autoresizingMask = [.width, .height]
        fx.addSubview(content)
        panel.contentView = fx
        return panel
    }

    static func fadeIn(_ w: NSWindow) {
        w.alphaValue = 0
        w.orderFrontRegardless()
        w.invalidateShadow()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            w.animator().alphaValue = 1
        }
    }
}

final class KeyablePanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// The 3x2 grid of snap layouts from the Windows 11 flyout.
final class LayoutFlyoutView: NSView {
    static let cell = NSSize(width: 100, height: 64)
    static let spacing: CGFloat = 14
    static let padding: CGFloat = 14
    static let columns = 3

    static var preferredSize: NSSize {
        let rows = CGFloat((Layouts.all.count + columns - 1) / columns)
        let cols = CGFloat(columns)
        return NSSize(width: cols * cell.width + (cols - 1) * spacing + padding * 2,
                      height: rows * cell.height + (rows - 1) * spacing + padding * 2)
    }

    var highlighted: (layout: Int, zone: Int)? {
        didSet { if highlighted?.layout != oldValue?.layout || highlighted?.zone != oldValue?.zone { needsDisplay = true } }
    }

    /// Set to handle clicks; leave nil when hover is driven externally (during a drag).
    var onSelect: ((Int, Int) -> Void)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func cellRect(_ i: Int) -> NSRect {
        let c = Self.cell
        let col = CGFloat(i % Self.columns), row = CGFloat(i / Self.columns)
        return NSRect(x: Self.padding + col * (c.width + Self.spacing),
                      y: Self.padding + row * (c.height + Self.spacing),
                      width: c.width, height: c.height)
    }

    func zoneRect(layout: Int, zone: Int) -> NSRect {
        let c = cellRect(layout)
        let u = Layouts.all[layout].zones[zone]
        return NSRect(x: c.minX + u.minX * c.width, y: c.minY + u.minY * c.height,
                      width: u.width * c.width, height: u.height * c.height).insetBy(dx: 2, dy: 2)
    }

    func zone(at p: NSPoint) -> (layout: Int, zone: Int)? {
        for l in Layouts.all.indices {
            guard cellRect(l).insetBy(dx: -4, dy: -4).contains(p) else { continue }
            for z in Layouts.all[l].zones.indices where zoneRect(layout: l, zone: z).insetBy(dx: -2, dy: -2).contains(p) {
                return (l, z)
            }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        for l in Layouts.all.indices {
            for z in Layouts.all[l].zones.indices {
                let path = NSBezierPath(roundedRect: zoneRect(layout: l, zone: z), xRadius: 5, yRadius: 5)
                let on = highlighted?.layout == l && highlighted?.zone == z
                (on ? accent : NSColor.labelColor.withAlphaComponent(0.12)).setFill()
                path.fill()
                (on ? accent.highlight(withLevel: 0.3) ?? accent : NSColor.labelColor.withAlphaComponent(0.28)).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        guard onSelect != nil else { return }
        highlighted = zone(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        if onSelect != nil { highlighted = nil }
    }

    override func mouseDown(with event: NSEvent) {
        guard let hit = zone(at: convert(event.locationInWindow, from: nil)) else { return }
        onSelect?(hit.layout, hit.zone)
    }
}

/// Small pill shown at the top of the screen while dragging, before it expands into the flyout.
final class HintView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let icon = NSRect(x: bounds.midX - 14, y: bounds.midY - 7, width: 28, height: 14)
        NSColor.labelColor.withAlphaComponent(0.55).setStroke()
        for half in [NSRect(x: icon.minX, y: icon.minY, width: 13, height: 14),
                     NSRect(x: icon.minX + 15, y: icon.minY, width: 13, height: 14)] {
            let p = NSBezierPath(roundedRect: half.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            p.lineWidth = 1
            p.stroke()
        }
    }
}

/// Translucent rectangle showing where the window will land.
final class PreviewOverlay {
    private let window: NSWindow

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let fx = UI.blurView(radius: 12, material: .underWindowBackground)
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        tint.layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        tint.layer?.borderWidth = 1
        tint.layer?.cornerRadius = 12
        tint.autoresizingMask = [.width, .height]
        fx.addSubview(tint)
        window.contentView = fx
    }

    func show(_ frame: CGRect, from point: CGPoint) {
        let target = frame.insetBy(dx: 6, dy: 6)
        if !window.isVisible {
            window.setFrame(CGRect(x: point.x - 20, y: point.y - 20, width: 40, height: 40), display: false)
            window.alphaValue = 0
            window.orderFrontRegardless()
        } else if window.frame == target {
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        guard window.isVisible else { return }
        window.orderOut(nil)
    }
}
