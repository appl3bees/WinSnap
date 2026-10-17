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

    enum Action: Equatable {
        case snap(SnapPosition)
        /// Snap to `position` on the adjacent display, if there is one.
        case snapOnNeighbor(toLeft: Bool, position: SnapPosition)
        case restore
        case minimize
        case none
    }

    static func handle(_ dir: Direction) {
        guard let w = AX.focusedWindow(), !w.isOwn, let f = w.frame,
              let screen = NSScreen.best(for: Coords.flip(f)) else { return }
        let current = WindowStore.shared.record(for: w, currentFrame: f)?.position

        switch action(for: dir, from: current) {
        case .snap(let position): Snapper.snap(w, to: position, screen: screen)
        case .snapOnNeighbor(let toLeft, let position):
            if let next = neighbor(of: screen, toLeft: toLeft) { Snapper.snap(w, to: position, screen: next) }
        case .restore: Snapper.restore(w)
        case .minimize: w.minimize()
        case .none: break
        }
    }

    /// What a key press does, given where the window is currently snapped (nil if it isn't).
    static func action(for dir: Direction, from current: SnapPosition?) -> Action {
        switch (dir, current) {
        case (.left, .rightHalf?), (.right, .leftHalf?), (.down, .maximized?):
            return .restore
        case (.left, .topRight?): return .snap(.topLeft)
        case (.left, .bottomRight?): return .snap(.bottomLeft)
        case (.right, .topLeft?): return .snap(.topRight)
        case (.right, .bottomLeft?): return .snap(.bottomRight)
        case (.left, .leftHalf?):
            // Already on the left: hop to the right half of the display on the left, if any.
            return .snapOnNeighbor(toLeft: true, position: .rightHalf)
        case (.right, .rightHalf?):
            return .snapOnNeighbor(toLeft: false, position: .leftHalf)
        case (.left, _): return .snap(.leftHalf)
        case (.right, _): return .snap(.rightHalf)

        case (.up, .leftHalf?): return .snap(.topLeft)
        case (.up, .rightHalf?): return .snap(.topRight)
        case (.up, .bottomLeft?): return .snap(.leftHalf)
        case (.up, .bottomRight?): return .snap(.rightHalf)
        case (.up, nil): return .snap(.maximized)
        case (.up, _): return .none

        case (.down, .leftHalf?): return .snap(.bottomLeft)
        case (.down, .rightHalf?): return .snap(.bottomRight)
        case (.down, .topLeft?): return .snap(.leftHalf)
        case (.down, .topRight?): return .snap(.rightHalf)
        case (.down, nil): return .minimize
        case (.down, _): return .none
        }
    }

    private static func neighbor(of screen: NSScreen, toLeft: Bool) -> NSScreen? {
        let others = NSScreen.screens.filter { $0 != screen }
        return toLeft
            ? others.filter { $0.frame.maxX <= screen.frame.minX + 1 }.max { $0.frame.maxX < $1.frame.maxX }
            : others.filter { $0.frame.minX >= screen.frame.maxX - 1 }.min { $0.frame.minX < $1.frame.minX }
    }
}
