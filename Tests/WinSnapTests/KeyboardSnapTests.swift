import Testing
#if !WINSNAP_SINGLE_MODULE_TESTS
@testable import WinSnap
#endif

@Suite struct KeyboardSnapTests {
    typealias A = KeyboardSnap.Action

    func act(_ dir: KeyboardSnap.Direction, _ position: SnapPosition?, snapped: Bool = true) -> A {
        KeyboardSnap.action(for: dir, snapped: snapped, position: position)
    }

    @Test func freeWindow() {
        #expect(act(.left, nil, snapped: false) == .snap(.leftHalf))
        #expect(act(.right, nil, snapped: false) == .snap(.rightHalf))
        #expect(act(.up, nil, snapped: false) == .snap(.maximized))
        #expect(act(.down, nil, snapped: false) == .minimize)
    }

    @Test func halves() {
        #expect(act(.left, .rightHalf) == .restore)
        #expect(act(.right, .leftHalf) == .restore)
        #expect(act(.left, .leftHalf) == .moveToNeighbor(.rightHalf, toLeft: true))
        #expect(act(.right, .rightHalf) == .moveToNeighbor(.leftHalf, toLeft: false))
        #expect(act(.up, .leftHalf) == .snap(.topLeft))
        #expect(act(.down, .rightHalf) == .snap(.bottomRight))
    }

    @Test func quarters() {
        #expect(act(.left, .topRight) == .snap(.topLeft))
        #expect(act(.right, .bottomLeft) == .snap(.bottomRight))
        #expect(act(.up, .bottomLeft) == .snap(.leftHalf))
        #expect(act(.down, .topRight) == .snap(.rightHalf))
        #expect(act(.up, .topLeft) == .none)
        #expect(act(.down, .bottomRight) == .none)
    }

    @Test func maximized() {
        #expect(act(.down, .maximized) == .restore)
        #expect(act(.up, .maximized) == .none)
    }

    /// Regression: windows snapped from a layout flyout or Snap Assist used to have no position,
    /// so ⌃⌥↓ minimized them and ⌃⌥↑ maximized a left half instead of making it a quarter.
    @Test func afterLayoutSnap() {
        let leftFromFlyout = SnapPosition(unit: Layouts.all[0].zones[0])
        #expect(act(.up, leftFromFlyout) == .snap(.topLeft))
        #expect(act(.down, leftFromFlyout) == .snap(.bottomLeft))
        #expect(act(.left, leftFromFlyout) == .moveToNeighbor(.rightHalf, toLeft: true))

        let quarterFromFlyout = SnapPosition(unit: Layouts.all[4].zones[3])
        #expect(act(.up, quarterFromFlyout) == .snap(.rightHalf))

        let third = SnapPosition(unit: Layouts.all[2].zones[1])
        #expect(act(.down, third) == .restore)
        #expect(act(.up, third) == .snap(.maximized))
        #expect(act(.left, third) == .snap(.leftHalf))
    }
}
