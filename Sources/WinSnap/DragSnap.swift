import AppKit

/// Watches window drags: edge/corner snapping, the top-of-screen layout flyout, and restore-on-drag-away.
final class DragSnapController {
    private enum State { case idle, pending, moving, ignoring }

    private struct Target {
        var unit: CGRect
        var screen: NSScreen
        var position: SnapPosition?
        var slot: (layout: Int, zone: Int)?
    }

    private var monitors: [Any] = []
    private var state = State.idle
    private var window: WindowRef?
    private var startFrame: CGRect?
    private var target: Target?
    private let overlay = PreviewOverlay()
    private let topFlyout = TopFlyoutController()

    private let edgeThreshold: CGFloat = 4
    private let cornerSize: CGFloat = 80

    func start() {
        guard monitors.isEmpty else { return }
        let handlers: [(NSEvent.EventTypeMask, () -> Void)] = [
            (.leftMouseDown, { [weak self] in self?.mouseDown() }),
            (.leftMouseDragged, { [weak self] in self?.mouseDragged() }),
            (.leftMouseUp, { [weak self] in self?.mouseUp() }),
        ]
        for (mask, handler) in handlers {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in handler() }) {
                monitors.append(m)
            }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
    }

    private func reset() {
        state = .idle
        window = nil
        startFrame = nil
        target = nil
        overlay.hide()
        topFlyout.hide()
    }

    private func mouseDown() {
        reset()
        guard Settings.dragSnap,
              let w = AX.window(at: NSEvent.mouseLocation), !w.isOwn,
              let f = w.frame else {
            state = .ignoring
            return
        }
        window = w
        startFrame = f
        state = .pending
    }

    private func mouseDragged() {
        switch state {
        case .pending:
            guard let w = window, let f = w.frame, let s = startFrame else { state = .ignoring; return }
            if abs(f.width - s.width) > 1 || abs(f.height - s.height) > 1 {
                state = .ignoring   // a resize, not a move
            } else if hypot(f.minX - s.minX, f.minY - s.minY) > 3 {
                state = .moving
                beginMove(w, frame: f)
            }
        case .moving:
            update(NSEvent.mouseLocation)
        default:
            break
        }
    }

    private func beginMove(_ w: WindowRef, frame f: CGRect) {
        // Dragging a snapped window away restores its old size, keeping the grab point under the cursor.
        if let s = startFrame, let rec = WindowStore.shared.record(for: w, currentFrame: s) {
            WindowStore.shared.remove(w)
            let mouse = Coords.flip(NSEvent.mouseLocation)
            let ratio = f.width > 0 ? (mouse.x - f.minX) / f.width : 0.5
            w.setSize(rec.original.size)
            w.setPosition(CGPoint(x: mouse.x - ratio * rec.original.width, y: f.minY))
        }
        if Settings.topFlyout, let screen = NSScreen.containing(NSEvent.mouseLocation) {
            topFlyout.showHint(on: screen)
        }
    }

    private func update(_ loc: CGPoint) {
        guard let screen = NSScreen.containing(loc) else { return }
        var t: Target?
        if Settings.topFlyout, let slot = topFlyout.update(mouse: loc, screen: screen) {
            t = Target(unit: Layouts.all[slot.layout].zones[slot.zone], screen: screen, position: nil, slot: slot)
        } else if !topFlyout.isExpanded, let p = edgePosition(loc, screen: screen) {
            t = Target(unit: p.unit, screen: screen, position: p, slot: p.assistSlot)
        }
        target = t
        if let t {
            overlay.show(Layouts.frame(for: t.unit, on: t.screen), from: loc)
        } else {
            overlay.hide()
        }
    }

    private func edgePosition(_ loc: CGPoint, screen: NSScreen) -> SnapPosition? {
        let f = screen.frame
        // A shared edge with another display isn't a snap edge; the cursor just crosses over.
        func open(_ dx: CGFloat, _ dy: CGFloat) -> Bool {
            let p = CGPoint(x: loc.x + dx, y: loc.y + dy)
            return !NSScreen.screens.contains { $0 != screen && NSMouseInRect(p, $0.frame, false) }
        }
        let atLeft = loc.x <= f.minX + edgeThreshold && open(-10, 0)
        let atRight = loc.x >= f.maxX - 1 - edgeThreshold && open(10, 0)
        let atTop = loc.y >= f.maxY - 1 - edgeThreshold && open(0, 10)
        let atBottom = loc.y <= f.minY + edgeThreshold && open(0, -10)
        let nearTop = loc.y >= f.maxY - cornerSize, nearBottom = loc.y <= f.minY + cornerSize
        let nearLeft = loc.x <= f.minX + cornerSize, nearRight = loc.x >= f.maxX - cornerSize

        if atLeft { return nearTop ? .topLeft : nearBottom ? .bottomLeft : .leftHalf }
        if atRight { return nearTop ? .topRight : nearBottom ? .bottomRight : .rightHalf }
        if atTop { return nearLeft ? .topLeft : nearRight ? .topRight : .maximized }
        if atBottom { return nearLeft ? .bottomLeft : nearRight ? .bottomRight : nil }
        return nil
    }

    private func mouseUp() {
        let snap = state == .moving ? target : nil
        let w = window
        reset()
        guard let t = snap, let w else { return }
        // Let the window server finish the drag before we move the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Snapper.snap(w, unit: t.unit, screen: t.screen, position: t.position)
            if Settings.snapAssist, let slot = t.slot {
                SnapAssist.shared.begin(after: w, layout: slot.layout, zone: slot.zone, screen: t.screen)
            }
        }
    }
}

/// The pill at the top of the screen that expands into the layout flyout while dragging.
final class TopFlyoutController {
    private let flyoutView = LayoutFlyoutView()
    private lazy var flyout = UI.panel(size: LayoutFlyoutView.preferredSize, content: flyoutView)
    private lazy var hint: NSPanel = {
        let p = UI.panel(size: NSSize(width: 120, height: 30), content: HintView(), radius: 15)
        p.ignoresMouseEvents = true
        return p
    }()
    private var screen: NSScreen?
    private(set) var isExpanded = false

    init() {
        flyout.ignoresMouseEvents = true   // hover is computed from drag events instead
    }

    private var hintFrame: CGRect {
        guard let vf = screen?.visibleFrame else { return .zero }
        return CGRect(x: vf.midX - 60, y: vf.maxY - 8 - 30, width: 120, height: 30)
    }

    private var flyoutFrame: CGRect {
        guard let vf = screen?.visibleFrame else { return .zero }
        let s = LayoutFlyoutView.preferredSize
        return CGRect(x: (vf.midX - s.width / 2).rounded(), y: vf.maxY - 8 - s.height, width: s.width, height: s.height)
    }

    func showHint(on screen: NSScreen) {
        self.screen = screen
        isExpanded = false
        flyout.orderOut(nil)
        hint.setFrame(hintFrame, display: false)
        UI.fadeIn(hint)
    }

    /// Returns the zone under the cursor, expanding or collapsing the flyout as the cursor approaches or leaves.
    func update(mouse loc: CGPoint, screen: NSScreen) -> (layout: Int, zone: Int)? {
        if screen != self.screen { showHint(on: screen) }
        let top = screen.frame.maxY

        if !isExpanded {
            let h = hintFrame
            let trigger = CGRect(x: h.minX - 90, y: h.minY - 50, width: h.width + 180, height: top - (h.minY - 50))
            guard trigger.contains(loc) else { return nil }
            expand()
        }

        let f = flyout.frame
        let keep = CGRect(x: f.minX - 50, y: f.minY - 50, width: f.width + 100, height: top - (f.minY - 50))
        guard keep.contains(loc) else {
            collapse()
            return nil
        }
        let hit = flyoutView.zone(at: flyoutView.convert(flyout.convertPoint(fromScreen: loc), from: nil))
        flyoutView.highlighted = hit
        return hit
    }

    private func expand() {
        isExpanded = true
        flyoutView.highlighted = nil
        hint.orderOut(nil)
        let target = flyoutFrame
        flyout.setFrame(CGRect(x: target.midX - 60, y: target.maxY - 30, width: 120, height: 30), display: false)
        flyout.alphaValue = 0
        flyout.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            flyout.animator().setFrame(target, display: true)
            flyout.animator().alphaValue = 1
        }
        flyout.invalidateShadow()
    }

    private func collapse() {
        isExpanded = false
        flyoutView.highlighted = nil
        flyout.orderOut(nil)
        hint.setFrame(hintFrame, display: false)
        hint.alphaValue = 1
        hint.orderFrontRegardless()
    }

    func hide() {
        isExpanded = false
        flyoutView.highlighted = nil
        flyout.orderOut(nil)
        hint.orderOut(nil)
    }
}
