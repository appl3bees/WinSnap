import CoreGraphics
import Testing
#if !WINSNAP_SINGLE_MODULE_TESTS
@testable import WinSnap
#endif

@Suite struct LayoutsTests {
    /// A 1440×900 display with a 25pt menu bar, in Cocoa coordinates.
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func halvesSplitTheVisibleFrame() {
        #expect(Layouts.frame(for: SnapPosition.leftHalf.unit, in: visible) == CGRect(x: 0, y: 0, width: 720, height: 875))
        #expect(Layouts.frame(for: SnapPosition.rightHalf.unit, in: visible) == CGRect(x: 720, y: 0, width: 720, height: 875))
    }

    @Test func topZonesSitUnderTheMenuBar() {
        // Unit rects have a top-left origin; Cocoa frames grow upwards.
        let top = Layouts.frame(for: SnapPosition.topLeft.unit, in: visible)
        #expect(top.maxY == visible.maxY)
        #expect(Layouts.frame(for: SnapPosition.bottomLeft.unit, in: visible).minY == visible.minY)
    }

    @Test func framesFollowTheDisplayOrigin() {
        let secondary = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        #expect(Layouts.frame(for: SnapPosition.maximized.unit, in: secondary) == secondary)
        #expect(Layouts.frame(for: SnapPosition.rightHalf.unit, in: secondary) == CGRect(x: 2400, y: -200, width: 960, height: 1055))
    }

    @Test(arguments: Layouts.all.indices)
    func zonesTileTheScreenExactly(layout: Int) {
        let zones = Layouts.all[layout].zones
        let area = zones.reduce(0) { $0 + $1.width * $1.height }
        #expect(abs(area - 1) < 0.0001)
        for (i, a) in zones.enumerated() {
            for b in zones[(i + 1)...] {
                let overlap = a.intersection(b)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.0001)
            }
        }
    }

    @Test(arguments: Layouts.all.indices)
    func roundedFramesLeaveNoGaps(layout: Int) {
        // Thirds of an odd width must still meet edge to edge after rounding.
        let vf = CGRect(x: 0, y: 0, width: 1001, height: 701)
        let frames = Layouts.all[layout].zones.map { Layouts.frame(for: $0, in: vf) }
        let area = frames.reduce(0) { $0 + $1.width * $1.height }
        #expect(area == vf.width * vf.height)
    }
}

@Suite struct SnapPositionTests {
    @Test(arguments: SnapPosition.allCases)
    func roundTripsThroughItsUnit(position: SnapPosition) {
        #expect(SnapPosition(unit: position.unit) == position)
    }

    @Test func layoutHalvesAndQuartersMapToPositions() {
        #expect(SnapPosition(unit: Layouts.all[0].zones[0]) == .leftHalf)
        #expect(SnapPosition(unit: Layouts.all[0].zones[1]) == .rightHalf)
        #expect(SnapPosition(unit: Layouts.all[3].zones[0]) == .leftHalf)
        #expect(SnapPosition(unit: Layouts.all[3].zones[1]) == .topRight)
        #expect(Layouts.all[4].zones.map(SnapPosition.init(unit:)) == [.topLeft, .topRight, .bottomLeft, .bottomRight])
    }

    @Test func otherZonesHaveNoPosition() {
        #expect(SnapPosition(unit: Layouts.all[1].zones[0]) == nil)   // two thirds
        #expect(Layouts.all[2].zones.allSatisfy { SnapPosition(unit: $0) == nil })   // thirds
        #expect(SnapPosition(unit: Layouts.all[5].zones[1]) == nil)   // wide centre
    }

    @Test(arguments: SnapPosition.allCases)
    func assistSlotIsTheSameZone(position: SnapPosition) {
        guard let slot = position.assistSlot else {
            #expect(position == .maximized)
            return
        }
        #expect(Layouts.all[slot.layout].zones[slot.zone] == position.unit)
    }
}
