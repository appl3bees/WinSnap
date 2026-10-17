import XCTest
@testable import WinSnap

final class KeyboardSnapTests: XCTestCase {
    private func act(_ dir: KeyboardSnap.Direction, _ from: SnapPosition?) -> KeyboardSnap.Action {
        KeyboardSnap.action(for: dir, from: from)
    }

    func testFromUnsnappedWindow() {
        XCTAssertEqual(act(.left, nil), .snap(.leftHalf))
        XCTAssertEqual(act(.right, nil), .snap(.rightHalf))
        XCTAssertEqual(act(.up, nil), .snap(.maximized))
        XCTAssertEqual(act(.down, nil), .minimize)
    }

    func testOppositeArrowRestores() {
        XCTAssertEqual(act(.left, .rightHalf), .restore)
        XCTAssertEqual(act(.right, .leftHalf), .restore)
        XCTAssertEqual(act(.down, .maximized), .restore)
    }

    func testSameArrowMovesToNeighbouringDisplay() {
        XCTAssertEqual(act(.left, .leftHalf), .snapOnNeighbor(toLeft: true, position: .rightHalf))
        XCTAssertEqual(act(.right, .rightHalf), .snapOnNeighbor(toLeft: false, position: .leftHalf))
    }

    func testHalvesSplitIntoQuarters() {
        XCTAssertEqual(act(.up, .leftHalf), .snap(.topLeft))
        XCTAssertEqual(act(.up, .rightHalf), .snap(.topRight))
        XCTAssertEqual(act(.down, .leftHalf), .snap(.bottomLeft))
        XCTAssertEqual(act(.down, .rightHalf), .snap(.bottomRight))
    }

    func testQuartersMergeBackIntoHalves() {
        XCTAssertEqual(act(.up, .bottomLeft), .snap(.leftHalf))
        XCTAssertEqual(act(.up, .bottomRight), .snap(.rightHalf))
        XCTAssertEqual(act(.down, .topLeft), .snap(.leftHalf))
        XCTAssertEqual(act(.down, .topRight), .snap(.rightHalf))
    }

    func testQuartersSlideSideways() {
        XCTAssertEqual(act(.left, .topRight), .snap(.topLeft))
        XCTAssertEqual(act(.left, .bottomRight), .snap(.bottomLeft))
        XCTAssertEqual(act(.right, .topLeft), .snap(.topRight))
        XCTAssertEqual(act(.right, .bottomLeft), .snap(.bottomRight))
    }

    func testLeftQuarterGoingLeftAndRightQuarterGoingRightBecomeHalves() {
        XCTAssertEqual(act(.left, .topLeft), .snap(.leftHalf))
        XCTAssertEqual(act(.left, .bottomLeft), .snap(.leftHalf))
        XCTAssertEqual(act(.right, .topRight), .snap(.rightHalf))
        XCTAssertEqual(act(.right, .bottomRight), .snap(.rightHalf))
    }

    func testMaximizedWindow() {
        XCTAssertEqual(act(.up, .maximized), .none)
        XCTAssertEqual(act(.left, .maximized), .snap(.leftHalf))
        XCTAssertEqual(act(.right, .maximized), .snap(.rightHalf))
    }

    func testNoOpsAtTheEdges() {
        XCTAssertEqual(act(.up, .topLeft), .none)
        XCTAssertEqual(act(.up, .topRight), .none)
        XCTAssertEqual(act(.down, .bottomLeft), .none)
        XCTAssertEqual(act(.down, .bottomRight), .none)
    }
}
