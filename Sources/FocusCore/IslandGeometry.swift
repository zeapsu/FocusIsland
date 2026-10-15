import Foundation
import CoreGraphics

/// Pure placement math for the one top-centre island. Keeping this independent
/// from AppKit makes the display and safe-area behaviour deterministic to test.
public enum IslandGeometry {
    public static let maximumTopFlare: CGFloat = 14

    /// WindowServer uses top-left coordinates relative to the primary display.
    /// Only pass windows at the system's main-menu window level. Names and
    /// contents are deliberately unnecessary, including without capture access.
    public static func menuBarFrame(display: CGRect, primaryDisplayTop: CGFloat,
                                    menuWindowBounds: [CGRect]) -> CGRect? {
        let quartzTop = primaryDisplayTop - display.maxY
        guard let window = menuWindowBounds.first(where: {
            abs($0.minY - quartzTop) <= 1 &&
            abs($0.minX - display.minX) <= 1 &&
            abs($0.width - display.width) <= 2 &&
            (20...64).contains($0.height)
        }) else { return nil }
        return CGRect(x: display.minX, y: display.maxY - window.height,
                      width: display.width, height: window.height)
    }

    public static func menuBarHeaderHeight(_ menuBarHeight: CGFloat) -> CGFloat {
        min(28, max(18, menuBarHeight - 6))
    }

    /// macOS 27 reports a fractional notch inset (33.5 pt) under a 34 pt menu bar.
    /// AppKit snaps window frames to whole points, so a fractional canvas height
    /// shifts the drawn shell below the screen edge. Round up to fill the band.
    public static func notchHeaderHeight(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop.rounded(.up)
    }

    /// macOS 27 draws overflowed status items (the `<<` control) beside the notch,
    /// inside the system menu-bar window. Earlier releases never put items there,
    /// and their opaque menu-bar material would tint a window below it.
    public static func yieldsToMenuBarOverflow(macOSMajor: Int) -> Bool { macOSMajor >= 27 }

    /// While yielding, a collapsed island starts hover only from the camera housing
    /// or trailing wing, so reaching for an overflow item over the leading wing
    /// does not expand the island on top of it.
    public static func startsHover(at x: CGFloat, notchMinX: CGFloat, yielding: Bool) -> Bool {
        !yielding || x >= notchMinX
    }

    /// What Accessibility shows of the macOS 27 menu bar on the island's display.
    public struct MenuBarReading: Equatable {
        /// Horizontal span of the `<<` overflow control.
        public var control: ClosedRange<CGFloat>?
        /// Hidden status items are drawn left of the notch while the overflow is open.
        public var overflowOpen: Bool
        public init(control: ClosedRange<CGFloat>?, overflowOpen: Bool) {
            self.control = control
            self.overflowOpen = overflowOpen
        }
    }

    /// Interprets frames read from MenuBarAgent's windows, in Accessibility's
    /// top-left coordinates. `controls` are buttons directly in a menu-bar window
    /// (the overflow control); `items` are the per-icon buttons one level down.
    /// While closed, hidden items stack behind the control right of the notch.
    public static func menuBarReading(controls: [CGRect], items: [CGRect], band: CGRect,
                                      notchMinX: CGFloat, notchMaxX: CGFloat) -> MenuBarReading {
        func inBand(_ r: CGRect) -> Bool { r.midY >= band.minY && r.midY <= band.maxY && r.minX >= band.minX && r.maxX <= band.maxX }
        let control = controls.first { inBand($0) && $0.minX >= notchMaxX - 4 }
        let open = items.contains { $0.width > 0 && $0.height > 0 && inBand($0) && $0.maxX <= notchMinX }
        return MenuBarReading(control: control.map { $0.minX...$0.maxX }, overflowOpen: open)
    }

    /// The trailing wing stays only while it ends clear of the overflow control.
    public static func trailingWingFits(control: ClosedRange<CGFloat>?, notchMaxX: CGFloat, trailingWing: CGFloat) -> Bool {
        guard let control else { return true }
        return notchMaxX + trailingWing <= control.lowerBound
    }

    /// How far right of the island's trailing wing the `<<` overflow control is
    /// expected. It is the leftmost status item, so only its position is guessed.
    public static let overflowControlReach: CGFloat = 44

    /// Whether the wings are folded into the notch after a click in another app.
    /// Only a click just right of the trailing wing, where macOS 27 puts the
    /// `<<` overflow control, toggles the fold. The overflow stays open while
    /// people click in other apps or on its items, so no other click changes it.
    public static func overflowFolded(after click: CGPoint, folded: Bool, menuBand: CGRect,
                                      notchMaxX: CGFloat, trailingWing: CGFloat) -> Bool {
        let controlStart = notchMaxX + trailingWing
        let onControl = click.y >= menuBand.minY && click.y <= menuBand.maxY &&
            click.x >= controlStart && click.x <= controlStart + overflowControlReach
        return onControl ? !folded : folded
    }
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
        attachedToNotch: Bool = false,
        centerOffset: CGFloat = 0,
        menuBarHeight: CGFloat? = nil
    ) -> CGRect {
        let displayTop = display.origin.y + display.size.height
        let reserved = displayTop - visible.maxY
        let bandHeight = menuBarHeight ?? ((20...64).contains(reserved) ? reserved : 24)
        let headerHeight = menuBarHeaderHeight(bandHeight)
        let top = attachedToNotch && safeAreaTop > 0
            ? displayTop
            : displayTop - max(0, (bandHeight - headerHeight) / 2)
        return CGRect(
            origin: CGPoint(x: display.origin.x + display.size.width / 2 - size.width / 2 + centerOffset, y: top - size.height),
            size: size
        )
    }
}
