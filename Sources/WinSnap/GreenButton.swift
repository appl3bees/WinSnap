import AppKit

/// Shows the snap layout flyout when hovering a window's green (zoom / full screen) button.
final class GreenButtonController {
    private var monitors: [Any] = []
    private var lastCheck = Date.distantPast
    private var hoverTimer: Timer?
    private var hoverWindow: WindowRef?
    private var hoverButton: CGRect = .zero

    private let flyoutView = LayoutFlyoutView()
    private lazy var flyout = UI.panel(size: LayoutFlyoutView.preferredSize, content: flyoutView)
    private var flyoutWindow: WindowRef?
    private var anchor: CGRect = .zero
    private var trackTimer: Timer?
    private var outsideTicks = 0
    private var sticky = false

    private let hoverDelay: TimeInterval = 0.45

    func start() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in self?.mouseMoved() }) {
            monitors.append(m)
        }
        // Global monitors only see clicks in other apps, i.e. clicks outside the flyout.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.cancelHover()
            self?.hideFlyout()
        }) {
            monitors.append(m)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        cancelHover()
        hideFlyout()
    }

    private func mouseMoved() {
        guard Settings.greenButton, !flyout.isVisible else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCheck) > 0.04 else { return }
        lastCheck = now

        guard let (w, button) = zoomButton(at: NSEvent.mouseLocation) else {
            cancelHover()
            return
        }
        if hoverTimer == nil || hoverWindow != w {
            cancelHover()
            hoverWindow = w
            hoverButton = button
            hoverTimer = Timer.scheduledTimer(withTimeInterval: hoverDelay, repeats: false) { [weak self] _ in
                self?.hoverFired()
            }
        }
    }

    private func zoomButton(at loc: CGPoint) -> (WindowRef, CGRect)? {
        guard let el = AX.element(at: loc) else { return nil }
        let sub = AX.string(el, kAXSubroleAttribute)
        guard sub == kAXFullScreenButtonSubrole || sub == kAXZoomButtonSubrole,
              let w = AX.window(containing: el), !w.isOwn,
              let frame = AX.cocoaFrame(of: el) else { return nil }
        return (w, frame)
    }

    private func cancelHover() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverWindow = nil
    }

    private func hoverFired() {
        hoverTimer = nil
        guard let w = hoverWindow, hoverButton.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation) else {
            hoverWindow = nil
            return
        }
        showFlyout(for: w, anchor: hoverButton, sticky: false)
    }

    /// Opens the flyout below `anchor` (Cocoa coordinates). Sticky flyouts stay until a click instead of closing when the mouse leaves.
    func showFlyout(for w: WindowRef, anchor: CGRect, sticky: Bool) {
        flyoutWindow = w
        self.anchor = anchor
        self.sticky = sticky
        flyoutView.highlighted = nil
        flyoutView.onSelect = { [weak self] l, z in self?.select(layout: l, zone: z) }

        let size = LayoutFlyoutView.preferredSize
        var origin = CGPoint(x: anchor.midX - 40, y: anchor.minY - 6 - size.height)
        if let vf = NSScreen.containing(CGPoint(x: anchor.midX, y: anchor.midY))?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 6), vf.maxX - size.width - 6)
            if origin.y < vf.minY + 6 { origin.y = anchor.maxY + 6 }
        }
        flyout.setFrame(CGRect(origin: origin, size: size), display: true)
        UI.fadeIn(flyout)

        outsideTicks = 0
        trackTimer?.invalidate()
        trackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.track() }
    }

    private func track() {
        guard !sticky else { return }
        let loc = NSEvent.mouseLocation
        // The 6pt gap between button and flyout is covered by the flyout's margin.
        let inside = flyout.frame.insetBy(dx: -14, dy: -14).contains(loc)
            || anchor.insetBy(dx: -8, dy: -8).contains(loc)
        outsideTicks = inside ? 0 : outsideTicks + 1
        if outsideTicks >= 3 { hideFlyout() }
    }

    func hideFlyout() {
        trackTimer?.invalidate()
        trackTimer = nil
        flyoutWindow = nil
        guard flyout.isVisible else { return }
        flyout.orderOut(nil)
    }

    private func select(layout: Int, zone: Int) {
        guard let w = flyoutWindow, let screen = Snapper.screen(of: w) else { return hideFlyout() }
        hideFlyout()
        Snapper.snap(w, unit: Layouts.all[layout].zones[zone], screen: screen)
        w.raise()
        if Settings.snapAssist {
            SnapAssist.shared.begin(after: w, layout: layout, zone: zone, screen: screen)
        }
    }
}
