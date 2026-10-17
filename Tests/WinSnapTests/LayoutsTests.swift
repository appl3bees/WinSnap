import XCTest
@testable import WinSnap

final class LayoutsTests: XCTestCase {
    // Slightly padded: sums like 2/3 + 1/3 can land a hair past 1.
    private let unitSquare = CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -1e-9, dy: -1e-9)

    func testEveryLayoutTilesTheUnitSquare() {
        XCTAssertEqual(Layouts.all.count, 6)
        for (i, layout) in Layouts.all.enumerated() {
            let area = layout.zones.reduce(0) { $0 + $1.width * $1.height }
            XCTAssertEqual(area, 1, accuracy: 1e-9, "layout \(i) does not cover the screen exactly")
            for zone in layout.zones {
                XCTAssertTrue(unitSquare.contains(zone), "layout \(i) zone \(zone) leaves the screen")
            }
            for a in layout.zones.indices {
                for b in layout.zones.indices where a < b {
                    let overlap = layout.zones[a].intersection(layout.zones[b])
                    XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 1e-9,
                                  "layout \(i) zones \(a) and \(b) overlap")
                }
            }
        }
    }

    func testFrameFlipsTopLeftUnitIntoCocoaCoordinates() {
        // Visible frame below a 25pt menu bar on a 1440x900 display, with a dock at the bottom.
        let vf = CGRect(x: 0, y: 70, width: 1440, height: 805)
        XCTAssertEqual(Layouts.frame(for: SnapPosition.leftHalf.unit, in: vf),
                       CGRect(x: 0, y: 70, width: 720, height: 805))
        XCTAssertEqual(Layouts.frame(for: SnapPosition.topRight.unit, in: vf),
                       CGRect(x: 720, y: 473, width: 720, height: 402))
        XCTAssertEqual(Layouts.frame(for: SnapPosition.bottomLeft.unit, in: vf),
                       CGRect(x: 0, y: 70, width: 720, height: 403))
        XCTAssertEqual(Layouts.frame(for: SnapPosition.maximized.unit, in: vf), vf)
    }

    func testFrameHonoursScreenOffset() {
        // A second display to the left of the main one.
        let vf = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(Layouts.frame(for: SnapPosition.rightHalf.unit, in: vf),
                       CGRect(x: -960, y: 0, width: 960, height: 1080))
    }

    func testThirdsAreWholePixelsAndLeaveNoGaps() {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let frames = Layouts.all[2].zones.map { Layouts.frame(for: $0, in: vf) }
        for f in frames {
            XCTAssertEqual(f.minX, f.minX.rounded())
            XCTAssertEqual(f.width, f.width.rounded())
        }
        XCTAssertEqual(frames[0].minX, 0)
        XCTAssertEqual(frames[0].maxX, frames[1].minX)
        XCTAssertEqual(frames[1].maxX, frames[2].minX)
        XCTAssertEqual(frames[2].maxX, 1000)
    }

    func testAssistSlotsPointAtMatchingZones() {
        let positions: [SnapPosition] = [.leftHalf, .rightHalf, .topLeft, .topRight, .bottomLeft, .bottomRight]
        for p in positions {
            guard let slot = p.assistSlot else { return XCTFail("\(p) has no assist slot") }
            XCTAssertEqual(Layouts.all[slot.layout].zones[slot.zone], p.unit, "\(p)")
        }
        XCTAssertNil(SnapPosition.maximized.assistSlot)
    }
}
