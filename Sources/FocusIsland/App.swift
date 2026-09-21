import AppKit
import SwiftUI
import Combine

@main
struct FocusIslandMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private lazy var model = SessionController()
    private var statusItem: NSStatusItem?
    private var island: IslandWindowController?
    private var settingsWindow: NSWindow?
    private let popover = NSPopover()
    private var menuHost: NSHostingController<MenuContentView>?
    private var subscriptions = Set<AnyCancellable>()
    private var localDismissalMonitor: Any?
    private var globalDismissalMonitor: Any?
    // A status-item click arrives as a mouse down followed by the button's
    // action on mouse up.  Remembering that down event prevents the action
    // from reopening a popover that the click has just dismissed.
    private var suppressNextStatusItemToggle = false
    private var popoverGeneration = 0
    #if DEBUG
    private var qaTimer: Timer?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        island = IslandWindowController(model: model, openMenu: { [weak self] in self?.toggleMenu() })
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(toggleMenu)
        item.button?.setAccessibilityLabel("Focus Island menu")
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = false
        let host = NSHostingController(rootView: MenuContentView(model: model, openSettings: { [weak self] in self?.showSettings() }, quit: { NSApp.terminate(nil) }))
        host.sizingOptions = []
        menuHost = host
        popover.contentViewController = host
        installPopoverDismissalMonitors()
        model.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatus() } }.store(in: &subscriptions)
        model.$settings.sink { [weak self] settings in
            self?.popover.appearance = settings.theme.appearance
            self?.settingsWindow?.appearance = settings.theme.appearance
        }.store(in: &subscriptions)
        model.$snapshot.map(\.state).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.sizeMenu() }
        }.store(in: &subscriptions)
        updateStatus()
        #if DEBUG
        if CommandLine.arguments.contains("--qa-artifacts") {
            qaTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in if let self { QADiagnostics.capture(model: self.model) } }
            }
        }
        #endif
    }

    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: model.icon, accessibilityDescription: model.title)
        button.imagePosition = .imageOnly
        button.title = ""
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.toolTip = "Focus Island · " + model.title
        button.setAccessibilityLabel("Focus Island menu, \(model.title) \(model.clockText)")
    }

    @objc private func toggleMenu() {
        guard let button = statusItem?.button else { return }
        if suppressNextStatusItemToggle {
            suppressNextStatusItemToggle = false
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else {
            model.refresh()
            island?.moveToCursorDisplay()
            sizeMenu()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    private func sizeMenu() {
        guard let host = menuHost else { return }
        host.view.layoutSubtreeIfNeeded()
        let size = host.sizeThatFits(in: NSSize(width: 340, height: 1_000))
        guard size.width > 0, size.height > 0 else { return }
        host.view.setFrameSize(size)
        popover.contentSize = size
    }
    func popoverWillShow(_ notification: Notification) {
        popoverGeneration &+= 1
        island?.setMenuOpen(true)
    }
    func popoverDidClose(_ notification: Notification) { island?.setMenuOpen(false) }

    /// NSPopover's transient behavior is not dependable for every click-away
    /// path (notably non-activating panels).  These monitors close the menu
    /// without consuming the click, so the clicked control or window still
    /// receives it.
    private func installPopoverDismissalMonitors() {
        localDismissalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }

            let isMouseDown = event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown
            let isMouseUp = event.type == .leftMouseUp || event.type == .rightMouseUp || event.type == .otherMouseUp
            if isMouseDown {
                // A previous status-bar gesture may have been cancelled or
                // dragged away.  Never let it suppress a later click.
                self.suppressNextStatusItemToggle = false
            }
            if event.type == .leftMouseUp, self.suppressNextStatusItemToggle {
                // The button action is dispatched from this mouse-up.  Clear
                // after it has had the opportunity to consume the flag.
                DispatchQueue.main.async { [weak self] in self?.suppressNextStatusItemToggle = false }
            }

            guard self.popover.isShown else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                self.popover.performClose(nil)
                return nil
            }

            guard isMouseDown || isMouseUp else { return event }

            if self.isStatusItemEvent(event) {
                if isMouseDown {
                    if event.type == .leftMouseDown {
                        self.suppressNextStatusItemToggle = true
                    }
                    self.popover.performClose(nil)
                }
                return event
            }

            if self.isPopoverEvent(event) {
                if isMouseUp {
                    // Let a SwiftUI/AppKit control finish its mouse-up action
                    // first, then dismiss the menu on the next run-loop turn.
                    let generation = self.popoverGeneration
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.popover.isShown, self.popoverGeneration == generation else { return }
                        self.popover.performClose(nil)
                    }
                }
            } else if isMouseDown {
                self.popover.performClose(nil)
            }
            return event
        }

        globalDismissalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    private func isPopoverEvent(_ event: NSEvent) -> Bool {
        guard let popoverWindow = popover.contentViewController?.view.window else { return false }
        return event.window === popoverWindow
    }

    private func isStatusItemEvent(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button, let window = button.window else { return false }
        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = window.convertToScreen(buttonFrame)
        return screenFrame.contains(NSEvent.mouseLocation)
    }

    deinit {
        if let localDismissalMonitor { NSEvent.removeMonitor(localDismissalMonitor) }
        if let globalDismissalMonitor { NSEvent.removeMonitor(globalDismissalMonitor) }
    }
    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.title = "Focus Island Settings"
            window.isReleasedWhenClosed = false
            window.appearance = model.settings.theme.appearance
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.notifications.finishPending()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
