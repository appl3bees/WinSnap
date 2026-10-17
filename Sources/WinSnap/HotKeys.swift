import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys through Carbon, which needs no extra permission.
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var refs: [EventHotKeyRef] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var handlerRef: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { mgr.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func register(keyCode: Int, modifiers: Int, _ action: @escaping () -> Void) {
        let id = UInt32(handlers.count + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         EventHotKeyID(signature: OSType(0x574E_534E), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return }
        refs.append(ref)
        handlers[id] = action
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }
}

/// Windows-style Win+Arrow behaviour, mapped to Control+Option+Arrow.
enum KeyboardSnap {
    enum Direction { case left, right, up, down }

    static func handle(_ dir: Direction) {
        guard let w = AX.focusedWindow(), !w.isOwn, let f = w.frame,
              let screen = NSScreen.best(for: Coords.flip(f)) else { return }
        let current = WindowStore.shared.record(for: w, currentFrame: f)?.position

        switch (dir, current) {
        case (.left, .rightHalf?), (.right, .leftHalf?), (.down, .maximized?):
            Snapper.restore(w)
        case (.left, .topRight?): Snapper.snap(w, to: .topLeft, screen: screen)
        case (.left, .bottomRight?): Snapper.snap(w, to: .bottomLeft, screen: screen)
        case (.right, .topLeft?): Snapper.snap(w, to: .topRight, screen: screen)
        case (.right, .bottomLeft?): Snapper.snap(w, to: .bottomRight, screen: screen)
        case (.left, .leftHalf?):
            // Already on the left: hop to the right half of the display on the left, if any.
            if let next = neighbor(of: screen, toLeft: true) { Snapper.snap(w, to: .rightHalf, screen: next) }
        case (.right, .rightHalf?):
            if let next = neighbor(of: screen, toLeft: false) { Snapper.snap(w, to: .leftHalf, screen: next) }
        case (.left, _): Snapper.snap(w, to: .leftHalf, screen: screen)
        case (.right, _): Snapper.snap(w, to: .rightHalf, screen: screen)

        case (.up, .leftHalf?): Snapper.snap(w, to: .topLeft, screen: screen)
        case (.up, .rightHalf?): Snapper.snap(w, to: .topRight, screen: screen)
        case (.up, .bottomLeft?): Snapper.snap(w, to: .leftHalf, screen: screen)
        case (.up, .bottomRight?): Snapper.snap(w, to: .rightHalf, screen: screen)
        case (.up, nil): Snapper.snap(w, to: .maximized, screen: screen)
        case (.up, _): break

        case (.down, .leftHalf?): Snapper.snap(w, to: .bottomLeft, screen: screen)
        case (.down, .rightHalf?): Snapper.snap(w, to: .bottomRight, screen: screen)
        case (.down, .topLeft?): Snapper.snap(w, to: .leftHalf, screen: screen)
        case (.down, .topRight?): Snapper.snap(w, to: .rightHalf, screen: screen)
        case (.down, nil): w.minimize()
        case (.down, _): break
        }
    }

    private static func neighbor(of screen: NSScreen, toLeft: Bool) -> NSScreen? {
        let others = NSScreen.screens.filter { $0 != screen }
        return toLeft
            ? others.filter { $0.frame.maxX <= screen.frame.minX + 1 }.max { $0.frame.maxX < $1.frame.maxX }
            : others.filter { $0.frame.minX >= screen.frame.maxX - 1 }.min { $0.frame.minX < $1.frame.minX }
    }
}
