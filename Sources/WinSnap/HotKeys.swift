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
        /// Snap to this position on the neighbouring display, if there is one.
        case moveToNeighbor(SnapPosition, toLeft: Bool)
        case restore, minimize, none
    }

    static func handle(_ dir: Direction) {
        guard let w = AX.focusedWindow(), !w.isOwn, let f = w.frame,
              let screen = NSScreen.best(for: Coords.flip(f)) else { return }
        let rec = WindowStore.shared.record(for: w, currentFrame: f)

        switch action(for: dir, snapped: rec != nil, position: rec?.position) {
        case .snap(let p): Snapper.snap(w, to: p, screen: screen)
        case .moveToNeighbor(let p, let toLeft):
            if let next = neighbor(of: screen, toLeft: toLeft) { Snapper.snap(w, to: p, screen: next) }
        case .restore: Snapper.restore(w)
        case .minimize: w.minimize()
        case .none: break
        }
    }

    /// What a shortcut does to a window. `snapped` is whether WinSnap placed it; `position` is nil for
    /// unsnapped windows and for layout zones that aren't a half, quarter or maximized (e.g. thirds).
    static func action(for dir: Direction, snapped: Bool, position: SnapPosition?) -> Action {
        switch (dir, position) {
        case (.left, .rightHalf?), (.right, .leftHalf?), (.down, .maximized?): return .restore
        case (.left, .topRight?): return .snap(.topLeft)
        case (.left, .bottomRight?): return .snap(.bottomLeft)
        case (.right, .topLeft?): return .snap(.topRight)
        case (.right, .bottomLeft?): return .snap(.bottomRight)
        // Already on the left: hop to the right half of the display on the left, if any.
        case (.left, .leftHalf?): return .moveToNeighbor(.rightHalf, toLeft: true)
        case (.right, .rightHalf?): return .moveToNeighbor(.leftHalf, toLeft: false)
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
        // A window in some other layout zone goes back to its own size, like Windows; only a free one minimizes.
        case (.down, nil): return snapped ? .restore : .minimize
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
