import AppKit
import SwiftUI
import Combine
import FocusCore

@MainActor final class IslandPresentation: ObservableObject {
    @Published var expanded = false
    @Published var expansion: CGFloat = 0
    @Published var attachedToNotch = false
    @Published var notchWidth: CGFloat = 0
    @Published var notchHeight: CGFloat = 0
    @Published var baseLeadingWing: CGFloat = 28
    @Published var baseTrailingWing: CGFloat = 28
    /// 1 while the macOS 27 menu-bar overflow is open: the wings fold into the notch.
    @Published var wingFold: CGFloat = 0
    var leadingWing: CGFloat { baseLeadingWing * (1 - wingFold) }
    var trailingWing: CGFloat { baseTrailingWing * (1 - wingFold) }
    @Published var canvasWidth: CGFloat = 340
    @Published var canvasHeight: CGFloat = 180
    @Published var expandedWidth: CGFloat = 400
    @Published var expandedHeight: CGFloat = 150
    @Published var menuBarHeight: CGFloat = 24
    var headerHeight: CGFloat { attachedToNotch ? notchHeight : IslandGeometry.menuBarHeaderHeight(menuBarHeight) }
}

/// Public window metadata is per-display and follows the real auto-hidden bar.
/// NSMenu.menuBarVisible/currentSystemPresentationOptions describe this app
/// and can remain unchanged when a different app enters full screen.
@MainActor enum SystemMenuBar {
    static func frame(on screen: NSScreen) -> CGRect? {
        guard let primary = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
              }),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let bounds = windows.compactMap { window -> CGRect? in
            guard window[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.mainMenuWindow)),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let value = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: value as CFDictionary)
        }
        return IslandGeometry.menuBarFrame(display: screen.frame, primaryDisplayTop: primary.frame.maxY, menuWindowBounds: bounds)
    }
}

private final class PassivePanel: NSPanel {
    // Key eligibility allows keyboard/assistive access after an explicit interaction.
    // Passive updates only order the panel; they never call makeKey or activate the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Placement deliberately occupies the menu-bar band around the camera.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class HoverHostingView<Content: View>: NSHostingView<Content> {
    var hoverChanged: ((Bool) -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        area = next; addTrackingArea(next)
    }
    override func mouseEntered(with event: NSEvent) { hoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged?(false) }
}

@MainActor
final class IslandWindowController {
    let panel: NSPanel
    private let presentation = IslandPresentation()
    private let model: SessionController
    private var subscriptions = Set<AnyCancellable>()
    private var collapse: DispatchWorkItem?
    private var expand: DispatchWorkItem?
    private var hoverGeneration: UInt = 0
    private var animationTimer: AnyCancellable?
    private var selectedScreen: NSScreen?
    private var observers: [NSObjectProtocol] = []
    private var hovering = false
    private let yieldsToOverflow = IslandGeometry.yieldsToMenuBarOverflow(macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    private var notchMinX: CGFloat = 0
    private var overflowFolded = false
    private var foldTimer: AnyCancellable?
    private var menuOpen = false
    private var displayedState: SessionState = .idle
    private var pointerTimer: AnyCancellable?
    private var menuBarAvailable = true
    private var suppressed: Bool { !panel.isOnActiveSpace || !menuBarAvailable }
    private var pointerMonitors: [Any] = []
    private let pointerLocation: () -> NSPoint
    private let menuBarFrame: @MainActor (NSScreen) -> CGRect?
    private let saveFold: (Bool) -> Void

    init(model: SessionController, openMenu: @escaping () -> Void,
         pointerLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
         menuBarFrame: @escaping @MainActor (NSScreen) -> CGRect? = SystemMenuBar.frame,
         restoredFold: Bool = false, saveFold: @escaping (Bool) -> Void = { _ in }) {
        self.model = model
        self.saveFold = saveFold
        self.pointerLocation = pointerLocation
        self.menuBarFrame = menuBarFrame
        panel = PassivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Focus Island"
        // Keep the notch utility available on desktop and full-screen Spaces.
        // AppKit owns membership; window size never determines visibility.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.setAccessibilityElement(true)
        panel.setAccessibilityRole(.window)
        panel.setAccessibilitySubrole(.floatingWindow)
        panel.setAccessibilityParent(NSApp)
        let host = HoverHostingView(rootView: IslandView(model: model, island: presentation, openMenu: openMenu))
        host.sizingOptions = []
        host.hoverChanged = { [weak self] _ in self?.updatePointer() }
        panel.contentView = host
        chooseScreen()
        if yieldsToOverflow, presentation.attachedToNotch, restoredFold {
            overflowFolded = true
            presentation.wingFold = 1
        }
        reposition()
        updateVisibility()
        // Tracking events can be missed by nonactivating panels, especially after a resize.
        // Checking the pointer against the current frame also avoids a gap between hover areas.
        pointerTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.updateVisibility()
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in self?.updatePointer() }) { pointerMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in self?.updatePointer(); return event }) { pointerMonitors.append(monitor) }
        // Global mouse monitors need no Accessibility permission. They only see
        // clicks delivered to other apps, such as the system menu bar.
        if yieldsToOverflow, let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            guard let self else { return }
            self.menuBandClicked(at: self.pointerLocation())
        }) { pointerMonitors.append(monitor) }
        model.$snapshot.map(\.state).removeDuplicates().sink { [weak self] state in
            guard let self else { return }
            self.displayedState = state
            self.cancelHoverWork()
            self.reposition()
            self.setExpanded(self.hovering && !self.menuOpen && !self.suppressed)
            self.updateVisibility()
        }.store(in: &subscriptions)
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.chooseScreen(); self?.reposition(); self?.updateVisibility() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.hovering = false
                self.cancelHoverWork()
                self.animationTimer?.cancel()
                self.animationTimer = nil
                self.presentation.expanded = false
                self.presentation.expansion = 0
                self.chooseScreen()
                self.reposition()
                self.updateVisibility()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateVisibility() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateVisibility() }
        })
    }

    func moveToCursorDisplay() { chooseScreen(); reposition(); updateVisibility(); updatePointer() }
    func setMenuOpen(_ open: Bool) {
        menuOpen = open
        cancelHoverWork()
        hovering = false
        setExpanded(false)
        updatePointer()
    }
    private func updateVisibility() {
        guard let screen = selectedScreen else { return }
        if presentation.attachedToNotch {
            menuBarAvailable = true
        } else {
            let band = menuBarFrame(screen)
            if let band, presentation.menuBarHeight != band.height {
                presentation.menuBarHeight = band.height
                reposition()
            }
            // Once deliberately expanded, controls stay usable as the pointer
            // enters the body below an auto-hidden bar. Leaving hides it at once.
            let inBody = pointerLocation().y < panel.frame.maxY - presentation.headerHeight
            let hoveredBody = presentation.expanded && inBody && panel.isVisible && panel.isOnActiveSpace && !menuOpen && pointerWithinSurface()
            menuBarAvailable = band != nil || hoveredBody
            if !menuBarAvailable, panel.isVisible { panel.orderOut(nil) }
        }
        if menuBarAvailable, !panel.isVisible { panel.orderFrontRegardless() }
        // An ordered window can be absent from the active Space. Keep it
        // noninteractive until AppKit reports membership in the active Space.
        if suppressed {
            cancelHoverWork()
            animationTimer?.cancel()
            animationTimer = nil
            hovering = false
            if presentation.expanded { presentation.expanded = false }
            if presentation.expansion != 0 { presentation.expansion = 0 }
            panel.ignoresMouseEvents = true
        } else {
            updatePointer()
        }
    }
    private func chooseScreen() {
        selectedScreen = NSScreen.screens.first { NSMouseInRect(pointerLocation(), $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        presentation.attachedToNotch = (selectedScreen?.safeAreaInsets.top ?? 0) > 0
        // The compact external pill must not cast a shadow into app toolbars.
        panel.hasShadow = false
        if let screen = selectedScreen {
            let reserved = screen.frame.maxY - screen.visibleFrame.maxY
            if (20...64).contains(reserved) { presentation.menuBarHeight = reserved }
        }
    }
    private func pointerIsInside() -> Bool {
        let point = pointerLocation()
        guard panel.isVisible, !suppressed, !menuOpen, panel.isOnActiveSpace, NSMouseInRect(point, panel.frame, false),
              pointerWithinSurface() else { return false }
        let yielding = yieldsToOverflow && presentation.attachedToNotch && !hovering && presentation.expansion == 0
        return IslandGeometry.startsHover(at: point.x, notchMinX: notchMinX, yielding: yielding)
    }
    private func pointerWithinSurface() -> Bool {
        return IslandGeometry.containsPointer(pointerLocation(), canvas: panel.frame,
            headerWidth: presentation.attachedToNotch ? presentation.notchWidth + presentation.leadingWing + presentation.trailingWing : 224,
            headerHeight: presentation.headerHeight,
            headerOffset: presentation.attachedToNotch ? (presentation.trailingWing - presentation.leadingWing) / 2 : 0,
            expandedHeight: presentation.expandedHeight, expanded: presentation.expanded,
            attached: presentation.attachedToNotch, expansion: presentation.expansion)
    }
    private func updatePointer() {
        let inside = pointerIsInside()
        panel.ignoresMouseEvents = !inside
        // A collapsed notch shell sits just under the system menu-bar window so
        // overflowed status items draw over it and receive clicks. Hover raises
        // it before the expand delay, so header clicks still reach the island.
        let lowered = yieldsToOverflow && presentation.attachedToNotch && !inside && !presentation.expanded && presentation.expansion == 0
        let level = lowered ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1) : .statusBar
        if panel.level != level { panel.level = level }
        if inside != hovering { hover(inside) }
    }
    private func hover(_ inside: Bool) {
        guard !suppressed, !menuOpen else { return }
        hovering = inside
        cancelHoverWork()
        let generation = hoverGeneration
        if inside && !presentation.expanded {
            if presentation.expansion > 0 {
                setExpanded(true)
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hoverGeneration == generation, self.hovering, !self.suppressed else { return }
                self.setExpanded(true)
            }
            expand = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
        }
        else if !inside {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hoverGeneration == generation, !self.hovering else { return }
                if self.pointerIsInside() { return }
                self.setExpanded(false)
            }
            collapse = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: work)
        }
    }
    private func cancelHoverWork() {
        hoverGeneration &+= 1
        collapse?.cancel()
        expand?.cancel()
        collapse = nil
        expand = nil
    }
    func menuBandClicked(at point: NSPoint) {
        guard yieldsToOverflow, presentation.attachedToNotch, let screen = selectedScreen else { return }
        let band = CGRect(x: screen.frame.minX, y: screen.frame.maxY - presentation.notchHeight,
                          width: screen.frame.width, height: presentation.notchHeight)
        let folded = IslandGeometry.overflowFolded(after: point, folded: overflowFolded, menuBand: band,
            notchMaxX: notchMinX + presentation.notchWidth, trailingWing: presentation.baseTrailingWing)
        guard folded != overflowFolded else { return }
        overflowFolded = folded
        saveFold(folded)
        foldTimer?.cancel()
        foldTimer = nil
        let target: CGFloat = folded ? 1 : 0
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || suppressed {
            presentation.wingFold = target
            return
        }
        let start = presentation.wingFold
        let began = ProcessInfo.processInfo.systemUptime
        let duration = 0.22 * max(0.25, Double(abs(target - start)))
        foldTimer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self else { return }
            let elapsed = min(1, max(0, (ProcessInfo.processInfo.systemUptime - began) / duration))
            let eased = elapsed < 0.5 ? 4 * pow(elapsed, 3) : 1 - pow(-2 * elapsed + 2, 3) / 2
            self.presentation.wingFold = start + (target - start) * eased
            if elapsed >= 1 {
                self.foldTimer?.cancel()
                self.foldTimer = nil
            }
        }
    }
    private func setExpanded(_ expanded: Bool) {
        guard presentation.expanded != expanded else { return }
        presentation.expanded = expanded
        animationTimer?.cancel()
        animationTimer = nil
        let target: CGFloat = expanded ? 1 : 0
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || suppressed {
            presentation.expansion = target
            updatePointer()
            return
        }
        let start = presentation.expansion
        let began = ProcessInfo.processInfo.systemUptime
        let duration = 0.18 * max(0.25, Double(abs(target - start)))
        // One short-lived animation clock drives both rendering and hit testing.
        // Its value comes from elapsed monotonic time, never a frame count.
        animationTimer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self else { return }
            let elapsed = min(1, max(0, (ProcessInfo.processInfo.systemUptime - began) / duration))
            let eased = 1 - pow(1 - elapsed, 3)
            self.presentation.expansion = start + (target - start) * eased
            if elapsed >= 1 {
                self.animationTimer?.cancel()
                self.animationTimer = nil
            }
            self.updatePointer()
        }
    }
    private func reposition() {
        guard let screen = selectedScreen ?? NSScreen.screens.first else { return }
        let notchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(0, right.minX - left.maxX)
        } else { notchWidth = 0 }
        presentation.notchWidth = notchWidth
        notchMinX = screen.frame.midX - notchWidth / 2
        presentation.notchHeight = IslandGeometry.notchHeaderHeight(safeAreaTop: screen.safeAreaInsets.top)
        let expandedWidth = max(400, notchWidth + 200)
        presentation.baseLeadingWing = displayedState == .idle ? 28 : 72
        presentation.baseTrailingWing = 28
        presentation.expandedWidth = expandedWidth
        presentation.canvasWidth = expandedWidth + (presentation.attachedToNotch ? 2 * IslandGeometry.maximumTopFlare : 0)
        presentation.canvasHeight = presentation.headerHeight + 126
        presentation.expandedHeight = presentation.headerHeight + (displayedState == .idle ? 100 : 118)
        // A fixed transparent canvas keeps window motion out of the shape animation.
        // A shared progress value morphs the surface and input path together.
        let size = NSSize(width: presentation.canvasWidth, height: presentation.canvasHeight)
        let frame = IslandGeometry.frame(display: screen.frame, visible: screen.visibleFrame, safeAreaTop: screen.safeAreaInsets.top, size: size, attachedToNotch: presentation.attachedToNotch, menuBarHeight: presentation.menuBarHeight)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
}
