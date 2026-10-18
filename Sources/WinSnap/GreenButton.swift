import AppKit

/// Shows the snap layout flyout when hovering a window's green (zoom / full screen) button.
final class GreenButtonController {
    private var monitors: [Any] = []
    private var lastCheck = Date.distantPast
    private var hoverTimer: Timer?
    private var hoverWindow: WindowRef?
    private var hoverButton: CGRect = .zero

    private let flyoutView = LayoutFlyoutView()
    private let preview = PreviewOverlay()
    private var flyoutScreen: NSScreen?
    private lazy var flyout = UI.panel(size: LayoutFlyoutView.preferredSize, content: flyoutView)
    private var flyoutWindow: WindowRef?
    private var anchor: CGRect = .zero
    private var trackTimer: Timer?
    /// Where macOS's own green-button menu is (or is expected to appear). The flyout sits beside it, never on top.
    private var systemMenu: CGRect?

    private var hoverStart = Date.distantPast
    private let fallbackDelay: TimeInterval = 1.2
    private let gap: CGFloat = 8
    /// Rough size of the macOS menu, used until the real one shows up.
    private let systemMenuEstimate = CGSize(width: 260, height: 190)

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

        // Off the button, a pending hover is left to hoverTick, which keeps it if the macOS menu just opened.
        guard let (w, button) = zoomButton(at: NSEvent.mouseLocation) else { return }
        if hoverTimer == nil || hoverWindow != w {
            cancelHover()
            hoverWindow = w
            hoverButton = button
            hoverStart = now
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
                self?.hoverTick()
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

    /// Waits for the macOS menu so both open together; apps without one get the flyout after `fallbackDelay`.
    private func hoverTick() {
        guard let w = hoverWindow else { return cancelHover() }
        if Self.systemMenuFrame(below: hoverButton) != nil
            || (Date().timeIntervalSince(hoverStart) >= fallbackDelay
                && hoverButton.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation)) {
            let button = hoverButton
            cancelHover()
            showFlyout(for: w, anchor: button, besideSystemMenu: true)
        } else if !hoverButton.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation) {
            cancelHover()
        }
    }

    /// Opens the flyout at `anchor` (Cocoa coordinates). Like the macOS menu, it stays until a zone is picked or the user
    /// clicks elsewhere. Hover flyouts sit beside the macOS menu so both stay usable; ⌃⌥Z ones sit right under the button.
    func showFlyout(for w: WindowRef, anchor: CGRect, besideSystemMenu: Bool) {
        flyoutWindow = w
        flyoutScreen = Snapper.screen(of: w)
        self.anchor = anchor
        flyoutView.highlighted = nil
        flyoutView.onSelect = { [weak self] l, z in self?.select(layout: l, zone: z) }
        flyoutView.onHover = { [weak self] hit in self?.previewZone(hit) }

        let size = LayoutFlyoutView.preferredSize
        trackTimer?.invalidate()
        trackTimer = nil
        if besideSystemMenu {
            let menu = Self.systemMenuFrame(below: anchor) ?? CGRect(
                x: anchor.minX - 12, y: anchor.minY - 6 - systemMenuEstimate.height,
                width: systemMenuEstimate.width, height: systemMenuEstimate.height)
            systemMenu = menu
            flyout.setFrame(frame(beside: menu, size: size), display: true)
            // The macOS menu pops in without a fade; match it so the two appear together.
            flyout.alphaValue = 1
            flyout.orderFrontRegardless()
            trackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.track() }
        } else {
            systemMenu = nil
            var origin = CGPoint(x: anchor.midX - 40, y: anchor.minY - 6 - size.height)
            if let vf = NSScreen.containing(CGPoint(x: anchor.midX, y: anchor.midY))?.visibleFrame {
                origin.x = min(max(origin.x, vf.minX + 6), vf.maxX - size.width - 6)
                if origin.y < vf.minY + 6 { origin.y = anchor.maxY + 6 }
            }
            flyout.setFrame(CGRect(origin: origin, size: size), display: true)
            UI.fadeIn(flyout)
        }
    }

    /// To the right of the macOS menu, top edges aligned; to its left or below it when the screen runs out.
    private func frame(beside menu: CGRect, size: CGSize) -> CGRect {
        var origin = CGPoint(x: menu.maxX + gap, y: menu.maxY - size.height)
        if let vf = NSScreen.containing(CGPoint(x: menu.midX, y: menu.maxY))?.visibleFrame {
            if origin.x + size.width > vf.maxX - 6 { origin.x = menu.minX - gap - size.width }
            if origin.x < vf.minX + 6 {
                origin = CGPoint(x: min(max(menu.minX, vf.minX + 6), vf.maxX - size.width - 6),
                                 y: menu.minY - gap - size.height)
            }
            origin.y = max(origin.y, vf.minY + 6)
        }
        return CGRect(origin: origin, size: size)
    }

    /// The macOS green-button menu, if it's open: a small floating window hanging just under the button.
    private static func systemMenuFrame(below button: CGRect) -> CGRect? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for win in info {
            guard (win[kCGWindowLayer as String] as? Int ?? 0) > 0,
                  (win[kCGWindowOwnerPID as String] as? pid_t) != getpid(),
                  let dict = win[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            let f = Coords.flip(bounds)
            guard f.width > 120, f.width < 600, f.height > 60, f.height < 500 else { continue }
            if f.maxY <= button.maxY, f.maxY >= button.minY - 40,
               f.minX <= button.maxX + 20, f.maxX >= button.minX {
                return f
            }
        }
        return nil
    }

    /// Follows the real macOS menu once it appears, so the two never overlap.
    private func track() {
        guard flyoutWindow != nil, let real = Self.systemMenuFrame(below: anchor), real != systemMenu else { return }
        systemMenu = real
        flyout.setFrame(frame(beside: real, size: flyout.frame.size), display: true)
    }

    func hideFlyout() {
        trackTimer?.invalidate()
        trackTimer = nil
        flyoutWindow = nil
        systemMenu = nil
        preview.hide()
        guard flyout.isVisible else { return }
        flyout.orderOut(nil)
    }

    /// Shows where the window would land for the zone under the mouse, gliding between zones.
    /// The window itself stays put until a zone is clicked.
    private func previewZone(_ hit: (layout: Int, zone: Int)?) {
        // Crossing the gaps between zones keeps the last preview; it only goes once the mouse leaves the flyout.
        if hit == nil, flyout.frame.contains(NSEvent.mouseLocation) { return }
        guard let hit, let screen = flyoutScreen else { return preview.hide() }
        preview.show(Layouts.frame(for: Layouts.all[hit.layout].zones[hit.zone], on: screen), from: NSEvent.mouseLocation)
    }

    private func select(layout: Int, zone: Int) {
        guard let w = flyoutWindow, let screen = flyoutScreen else { return hideFlyout() }
        hideFlyout()
        Snapper.snap(w, unit: Layouts.all[layout].zones[zone], screen: screen)
        w.raise()
        if Settings.snapAssist {
            SnapAssist.shared.begin(after: w, layout: layout, zone: zone, screen: screen)
        }
    }
}
