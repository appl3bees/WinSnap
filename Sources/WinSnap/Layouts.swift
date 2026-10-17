import AppKit

/// A Windows 11 snap layout. Zones are unit rects with a top-left origin.
struct SnapLayout {
    let zones: [CGRect]
}

enum Layouts {
    private static func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    /// Same order as the Windows 11 flyout: three per row, two rows.
    static let all: [SnapLayout] = [
        SnapLayout(zones: [r(0, 0, 0.5, 1), r(0.5, 0, 0.5, 1)]),
        SnapLayout(zones: [r(0, 0, 2.0 / 3, 1), r(2.0 / 3, 0, 1.0 / 3, 1)]),
        SnapLayout(zones: [r(0, 0, 1.0 / 3, 1), r(1.0 / 3, 0, 1.0 / 3, 1), r(2.0 / 3, 0, 1.0 / 3, 1)]),
        SnapLayout(zones: [r(0, 0, 0.5, 1), r(0.5, 0, 0.5, 0.5), r(0.5, 0.5, 0.5, 0.5)]),
        SnapLayout(zones: [r(0, 0, 0.5, 0.5), r(0.5, 0, 0.5, 0.5), r(0, 0.5, 0.5, 0.5), r(0.5, 0.5, 0.5, 0.5)]),
        SnapLayout(zones: [r(0, 0, 0.25, 1), r(0.25, 0, 0.5, 1), r(0.75, 0, 0.25, 1)]),
    ]

    /// Target frame for a unit zone, in Cocoa coordinates.
    static func frame(for unit: CGRect, on screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        let x = (vf.minX + unit.minX * vf.width).rounded()
        let maxX = (vf.minX + unit.maxX * vf.width).rounded()
        let top = (vf.maxY - unit.minY * vf.height).rounded()
        let bottom = (vf.maxY - unit.maxY * vf.height).rounded()
        return CGRect(x: x, y: bottom, width: maxX - x, height: top - bottom)
    }
}

/// Snap positions reachable from screen edges and keyboard shortcuts.
enum SnapPosition {
    case leftHalf, rightHalf, topLeft, topRight, bottomLeft, bottomRight, maximized

    var unit: CGRect {
        switch self {
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .maximized: return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    /// The layout and zone Snap Assist should continue from.
    var assistSlot: (layout: Int, zone: Int)? {
        switch self {
        case .leftHalf: return (0, 0)
        case .rightHalf: return (0, 1)
        case .topLeft: return (4, 0)
        case .topRight: return (4, 1)
        case .bottomLeft: return (4, 2)
        case .bottomRight: return (4, 3)
        case .maximized: return nil
        }
    }
}
