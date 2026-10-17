import AppKit

/// Remembers each window's pre-snap frame so it can be restored, like Windows does.
final class WindowStore {
    static let shared = WindowStore()

    struct Record {
        var original: CGRect   // AX coordinates
        var snapped: CGRect    // AX coordinates, as the app actually applied it
        var position: SnapPosition?
    }

    private var records: [WindowRef: Record] = [:]

    /// The record, but only if the window still has the size we gave it.
    func record(for w: WindowRef, currentFrame: CGRect? = nil) -> Record? {
        guard let rec = records[w] else { return nil }
        guard let f = currentFrame ?? w.frame,
              abs(f.width - rec.snapped.width) < 20, abs(f.height - rec.snapped.height) < 20 else {
            records[w] = nil
            return nil
        }
        return rec
    }

    func set(_ rec: Record, for w: WindowRef) { records[w] = rec }
    func remove(_ w: WindowRef) { records[w] = nil }
}

enum Snapper {
    static func snap(_ w: WindowRef, unit: CGRect, screen: NSScreen, position: SnapPosition? = nil) {
        if w.isFullScreen {
            w.exitFullScreen()
            // The exit animation has to finish before the window accepts a new frame.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                snap(w, unit: unit, screen: screen, position: position)
            }
            return
        }
        guard let current = w.frame else { return }
        let original = WindowStore.shared.record(for: w, currentFrame: current)?.original ?? current
        let target = Coords.flip(Layouts.frame(for: unit, on: screen))
        w.setFrame(target)
        let applied = w.frame ?? target
        // Layout and Snap Assist snaps pass only a zone; record the matching position so shortcuts keep working.
        let recorded = position ?? SnapPosition(unit: unit)
        WindowStore.shared.set(.init(original: original, snapped: applied, position: recorded), for: w)
    }

    static func snap(_ w: WindowRef, to position: SnapPosition, screen: NSScreen) {
        snap(w, unit: position.unit, screen: screen, position: position)
    }

    static func restore(_ w: WindowRef) {
        guard let rec = WindowStore.shared.record(for: w) else { return }
        WindowStore.shared.remove(w)
        w.setFrame(rec.original)
    }

    static func screen(of w: WindowRef) -> NSScreen? {
        guard let f = w.frame else { return NSScreen.main }
        return NSScreen.best(for: Coords.flip(f))
    }
}
