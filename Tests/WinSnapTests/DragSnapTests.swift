import CoreGraphics
import Testing
#if !WINSNAP_SINGLE_MODULE_TESTS
@testable import WinSnap
#endif

@Suite struct EdgePositionTests {
    let main = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func edge(_ x: CGFloat, _ y: CGFloat, others: [CGRect] = []) -> SnapPosition? {
        DragSnapController.edgePosition(CGPoint(x: x, y: y), screen: main, others: others,
                                        edgeThreshold: 4, cornerSize: 80)
    }

    @Test func edges() {
        #expect(edge(0, 450) == .leftHalf)
        #expect(edge(1439, 450) == .rightHalf)
        #expect(edge(720, 899) == .maximized)
        #expect(edge(720, 0) == nil)
        #expect(edge(720, 450) == nil)
    }

    @Test func corners() {
        #expect(edge(0, 880) == .topLeft)
        #expect(edge(30, 899) == .topLeft)
        #expect(edge(1439, 10) == .bottomRight)
        #expect(edge(10, 0) == .bottomLeft)
        #expect(edge(1420, 899) == .topRight)
    }

    @Test func sharedEdgesDontSnap() {
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let above = CGRect(x: 0, y: 900, width: 1440, height: 900)
        #expect(edge(1439, 450, others: [right]) == nil)
        #expect(edge(0, 450, others: [right]) == .leftHalf)
        #expect(edge(720, 899, others: [above]) == nil)
    }
}

@Suite struct LayoutFlyoutTests {
    @Test func everyZoneIsHitAtItsCentre() {
        let view = LayoutFlyoutView(frame: CGRect(origin: .zero, size: LayoutFlyoutView.preferredSize))
        for l in Layouts.all.indices {
            for z in Layouts.all[l].zones.indices {
                let r = view.zoneRect(layout: l, zone: z)
                let hit = view.zone(at: CGPoint(x: r.midX, y: r.midY))
                #expect(hit?.layout == l && hit?.zone == z)
            }
        }
    }

    @Test func paddingIsNotAZone() {
        let view = LayoutFlyoutView(frame: CGRect(origin: .zero, size: LayoutFlyoutView.preferredSize))
        #expect(view.zone(at: .zero) == nil)
    }
}
