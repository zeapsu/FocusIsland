import Foundation
import CoreGraphics

/// Pure placement math for the one top-centre island. Keeping this independent
/// from AppKit makes the display and safe-area behaviour deterministic to test.
public enum IslandGeometry {
    public static let maximumTopFlare: CGFloat = 14
    /// The drawing and input system share this exact path in local top-left coordinates.
    public static func surfacePath(size: CGSize, headerWidth: CGFloat, headerHeight: CGFloat,
                                   headerOffset: CGFloat, expandedHeight: CGFloat,
                                   attached: Bool, expansion: CGFloat) -> CGPath {
        let progress = min(1, max(0, expansion))
        let expandedWidth = size.width - (attached ? 2 * maximumTopFlare : 0)
        let width = headerWidth + (expandedWidth - headerWidth) * progress
        let bodyHeight = (expandedHeight - headerHeight) * progress
        if !attached {
            return CGPath(roundedRect: CGRect(x: (size.width - width) / 2, y: 0, width: width, height: headerHeight + bodyHeight), cornerWidth: 17, cornerHeight: 17, transform: nil)
        }
        // The whole shell widens through the menu band, like one physical notch.
        let left = (size.width - width) / 2 + headerOffset * (1 - progress)
        let right = left + width
        let height = headerHeight + bodyHeight
        let radius = min(12 + 10 * progress, height / 2)
        let topFlare = min(6 + (maximumTopFlare - 6) * progress, height / 4)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left - topFlare, y: 0))
        path.addLine(to: CGPoint(x: right + topFlare, y: 0))
        path.addQuadCurve(to: CGPoint(x: right, y: topFlare), control: CGPoint(x: right, y: 0))
        path.addLine(to: CGPoint(x: right, y: height - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: height), control: CGPoint(x: right, y: height))
        path.addLine(to: CGPoint(x: left + radius, y: height))
        path.addQuadCurve(to: CGPoint(x: left, y: height - radius), control: CGPoint(x: left, y: height))
        path.addLine(to: CGPoint(x: left, y: topFlare))
        path.addQuadCurve(to: CGPoint(x: left - topFlare, y: 0), control: CGPoint(x: left, y: 0))
        path.closeSubpath()
        return path
    }

    /// Input follows the same path and animation progress as the visible surface.
    /// Empty canvas remains click-through; the expanded surface intentionally covers the menu band.
    public static func containsPointer(_ point: CGPoint, canvas: CGRect, headerWidth: CGFloat,
                                       headerHeight: CGFloat, headerOffset: CGFloat,
                                       expandedHeight: CGFloat, expanded: Bool,
                                       attached: Bool = true, expansion: CGFloat? = nil) -> Bool {
        let local = CGPoint(x: point.x - canvas.minX, y: canvas.maxY - point.y)
        return surfacePath(size: canvas.size, headerWidth: headerWidth, headerHeight: headerHeight,
            headerOffset: headerOffset, expandedHeight: expandedHeight, attached: attached,
            expansion: expansion ?? (expanded ? 1 : 0)).contains(local)
    }

    public static func frame(
        display: CGRect,
        visible: CGRect,
        safeAreaTop: CGFloat,
        size: CGSize,
        gap: CGFloat = 4,
        attachedToNotch: Bool = false,
        centerOffset: CGFloat = 0
    ) -> CGRect {
        let visibleTop = visible.origin.y + visible.size.height
        let displayTop = display.origin.y + display.size.height
        let top = attachedToNotch && safeAreaTop > 0
            ? displayTop
            : min(visibleTop, displayTop - safeAreaTop) - gap
        return CGRect(
            origin: CGPoint(x: display.origin.x + display.size.width / 2 - size.width / 2 + centerOffset, y: top - size.height),
            size: size
        )
    }
}
