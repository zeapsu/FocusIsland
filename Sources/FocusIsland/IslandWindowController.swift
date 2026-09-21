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
    @Published var leadingWing: CGFloat = 28
    @Published var trailingWing: CGFloat = 28
    @Published var canvasWidth: CGFloat = 340
    @Published var canvasHeight: CGFloat = 180
    @Published var expandedWidth: CGFloat = 400
    @Published var expandedHeight: CGFloat = 150
    var headerHeight: CGFloat { attachedToNotch ? notchHeight : 38 }
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
    private var pinnedPrompt = false
    private var menuOpen = false
    private var displayedState: SessionState = .idle
    private var pointerTimer: AnyCancellable?
    private var suppressed: Bool { !panel.isOnActiveSpace }
    private var pointerMonitors: [Any] = []

    init(model: SessionController, openMenu: @escaping () -> Void) {
        self.model = model
        panel = PassivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Focus Island"
        // Keep the notch utility available on desktop and full-screen Spaces.
        // AppKit owns membership; window size never determines visibility.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
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
        reposition()
        panel.orderFrontRegardless()
        updateVisibility()
        // Tracking events can be missed by nonactivating panels, especially after a resize.
        // Checking the pointer against the current frame also avoids a gap between hover areas.
        pointerTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.updatePointer()
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in self?.updatePointer() }) { pointerMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in self?.updatePointer(); return event }) { pointerMonitors.append(monitor) }
        model.$settings.sink { [weak self] settings in self?.panel.appearance = settings.theme.appearance }.store(in: &subscriptions)
        model.$snapshot.map(\.state).removeDuplicates().sink { [weak self] state in
            guard let self else { return }
            self.displayedState = state
            self.pinnedPrompt = state == .hardStopReached
            self.cancelHoverWork()
            self.reposition()
            self.setExpanded((self.hovering || self.pinnedPrompt) && !self.menuOpen)
        }.store(in: &subscriptions)
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.chooseScreen(); self?.reposition(); self?.updatePointer() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.hovering = false
                self.cancelHoverWork()
                self.animationTimer?.cancel()
                self.animationTimer = nil
                self.presentation.expanded = self.pinnedPrompt && !self.menuOpen
                self.presentation.expansion = self.presentation.expanded ? 1 : 0
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
        setExpanded(!open && pinnedPrompt)
        updatePointer()
    }
    private func updateVisibility() {
        // A window can remain ordered (isVisible) while absent from the active
        // Space. Do not order it out or reassign it while Spaces are changing.
        if suppressed {
            cancelHoverWork()
            animationTimer?.cancel()
            animationTimer = nil
            hovering = false
            let pinned = pinnedPrompt && !menuOpen
            if presentation.expanded != pinned { presentation.expanded = pinned }
            let progress: CGFloat = pinned ? 1 : 0
            if presentation.expansion != progress { presentation.expansion = progress }
            panel.ignoresMouseEvents = true
        } else {
            updatePointer()
        }
    }
    private func chooseScreen() {
        selectedScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        presentation.attachedToNotch = (selectedScreen?.safeAreaInsets.top ?? 0) > 0
        panel.hasShadow = !presentation.attachedToNotch
    }
    private func pointerIsInside() -> Bool {
        let point = NSEvent.mouseLocation
        guard panel.isVisible, !suppressed, !menuOpen, panel.isOnActiveSpace, NSMouseInRect(point, panel.frame, false) else { return false }
        return IslandGeometry.containsPointer(point, canvas: panel.frame,
            headerWidth: presentation.attachedToNotch ? presentation.notchWidth + presentation.leadingWing + presentation.trailingWing : 224,
            headerHeight: presentation.headerHeight,
            headerOffset: presentation.attachedToNotch ? (presentation.trailingWing - presentation.leadingWing) / 2 : 0,
            expandedHeight: presentation.expandedHeight, expanded: presentation.expanded,
            attached: presentation.attachedToNotch, expansion: presentation.expansion)
    }
    private func updatePointer() {
        let inside = pointerIsInside()
        panel.ignoresMouseEvents = !inside
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
        else if !inside && !pinnedPrompt {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hoverGeneration == generation, !self.hovering, !self.pinnedPrompt else { return }
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
        presentation.notchHeight = screen.safeAreaInsets.top
        let expandedWidth = max(400, notchWidth + 200)
        presentation.leadingWing = displayedState == .idle ? 28 : 72
        presentation.trailingWing = 28
        presentation.expandedWidth = expandedWidth
        presentation.canvasWidth = expandedWidth + (presentation.attachedToNotch ? 2 * IslandGeometry.maximumTopFlare : 0)
        presentation.canvasHeight = presentation.headerHeight + 126
        presentation.expandedHeight = presentation.headerHeight + (displayedState == .idle ? 100 : 118)
        // A fixed transparent canvas keeps window motion out of the shape animation.
        // A shared progress value morphs the surface and input path together.
        let size = NSSize(width: presentation.canvasWidth, height: presentation.canvasHeight)
        let frame = IslandGeometry.frame(display: screen.frame, visible: screen.visibleFrame, safeAreaTop: screen.safeAreaInsets.top, size: size, attachedToNotch: presentation.attachedToNotch)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
}
