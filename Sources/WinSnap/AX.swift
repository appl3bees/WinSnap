import AppKit
import ApplicationServices

// Private but long-stable API used by most window managers to map an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Accessibility uses a top-left origin on the primary screen; AppKit uses bottom-left.
enum Coords {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.minY - r.height, width: r.width, height: r.height)
    }

    static func flip(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}

extension NSScreen {
    static func containing(_ p: CGPoint) -> NSScreen? {
        screens.first { NSMouseInRect(p, $0.frame, false) } ?? main
    }

    /// Screen with the largest overlap with a Cocoa-coordinate rect.
    static func best(for rect: CGRect) -> NSScreen? {
        screens.max { a, b in
            let ia = a.frame.intersection(rect), ib = b.frame.intersection(rect)
            return ia.width * ia.height < ib.width * ib.height
        } ?? main
    }
}

enum AX {
    static let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, 0.25)
        return el
    }()

    static func copy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v
    }

    static func string(_ el: AXUIElement, _ attr: String) -> String? {
        copy(el, attr) as? String
    }

    static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        guard let v = copy(el, attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func point(_ el: AXUIElement, _ attr: String) -> CGPoint? {
        guard let v = copy(el, attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    static func size(_ el: AXUIElement, _ attr: String) -> CGSize? {
        guard let v = copy(el, attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    /// Frame of any element in Cocoa coordinates.
    static func cocoaFrame(of el: AXUIElement) -> CGRect? {
        guard let p = point(el, kAXPositionAttribute), let s = size(el, kAXSizeAttribute) else { return nil }
        return Coords.flip(CGRect(origin: p, size: s))
    }

    static func element(at cocoaPoint: CGPoint) -> AXUIElement? {
        let p = Coords.flip(cocoaPoint)
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &el) == .success else { return nil }
        return el
    }

    static func window(containing el: AXUIElement) -> WindowRef? {
        if string(el, kAXRoleAttribute) == kAXWindowRole { return WindowRef(el) }
        return element(el, kAXWindowAttribute).map(WindowRef.init)
    }

    static func window(at cocoaPoint: CGPoint) -> WindowRef? {
        element(at: cocoaPoint).flatMap(window(containing:))
    }

    static func focusedWindow() -> WindowRef? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        return element(appEl, kAXFocusedWindowAttribute).map(WindowRef.init)
    }

    /// Visible standard windows of regular apps, front-most first.
    static func standardWindows() -> [WindowRef] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let order = info.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }

        var result: [(WindowRef, Int)] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != getpid() {
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appEl, 0.2)
            guard let windows = copy(appEl, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for el in windows {
                let w = WindowRef(el)
                guard w.subrole == kAXStandardWindowSubrole, !w.isMinimized else { continue }
                var index = Int.max
                if let id = w.windowID {
                    // Not on screen means another Space; leave those out.
                    guard let i = order.firstIndex(of: id) else { continue }
                    index = i
                }
                result.append((w, index))
            }
        }
        return result.sorted { $0.1 < $1.1 }.map(\.0)
    }
}

/// A handle to another app's window. Equality follows the underlying AX element.
final class WindowRef: Hashable {
    let element: AXUIElement
    let pid: pid_t

    init(_ element: AXUIElement) {
        self.element = element
        var p: pid_t = 0
        AXUIElementGetPid(element, &p)
        pid = p
    }

    static func == (a: WindowRef, b: WindowRef) -> Bool { CFEqual(a.element, b.element) }
    func hash(into h: inout Hasher) { h.combine(CFHash(element)) }

    var isOwn: Bool { pid == getpid() }
    var title: String? { AX.string(element, kAXTitleAttribute) }
    var subrole: String? { AX.string(element, kAXSubroleAttribute) }
    var isMinimized: Bool { (AX.copy(element, kAXMinimizedAttribute) as? Bool) ?? false }
    var isFullScreen: Bool { (AX.copy(element, "AXFullScreen") as? Bool) ?? false }
    var app: NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }
    var zoomButton: AXUIElement? { AX.element(element, kAXZoomButtonAttribute) }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    /// Frame in Accessibility (top-left) coordinates.
    var frame: CGRect? {
        guard let p = AX.point(element, kAXPositionAttribute), let s = AX.size(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }

    func setFrame(_ r: CGRect) {
        // Apps with AXEnhancedUserInterface on animate every change and fight us; switch it off meanwhile.
        let appEl = AXUIElementCreateApplication(pid)
        let enhanced = (AX.copy(appEl, "AXEnhancedUserInterface") as? Bool) ?? false
        if enhanced { AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        // Size, move, size again: the first resize can be clamped by the screen the window started on.
        setSize(r.size)
        setPosition(r.origin)
        setSize(r.size)
        if enhanced { AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    func setPosition(_ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, v)
        }
    }

    func setSize(_ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, v)
        }
    }

    func exitFullScreen() {
        AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, kCFBooleanFalse)
    }

    func minimize() {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        app?.activate()
    }
}
