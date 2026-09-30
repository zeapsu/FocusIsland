import AppKit
import Combine
import SwiftUI
import FocusCore

// Keep these fixtures limited to the controller's two collaborators. The real
// controller, NSPanel, tracking, delayed work, animation, and geometry run below.
@MainActor final class SessionController: ObservableObject {
    @Published var snapshot = SessionSnapshot(state: .hardStopReached)
}

struct IslandView: View {
    @ObservedObject var model: SessionController
    @ObservedObject var island: IslandPresentation
    let openMenu: () -> Void
    var body: some View { Color.clear.frame(width: island.canvasWidth, height: island.canvasHeight) }
}

@main @MainActor struct IslandHoverChecks {
    static func settle(_ seconds: TimeInterval = 0.65) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
        print("PASS: \(message)")
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            fputs("Native hover checks require a logged-in macOS display session.\n", stderr)
            exit(1)
        }
        let outside = NSPoint(x: screen.frame.minX + 40, y: screen.frame.midY)
        var pointer = outside
        var menuVisible = true
        let model = SessionController()
        let controller = IslandWindowController(model: model, openMenu: {}, pointerLocation: { pointer },
            menuBarFrame: { screen in menuVisible ? CGRect(x: screen.frame.minX, y: screen.frame.maxY - 30, width: screen.frame.width, height: 30) : nil })
        guard let host = controller.panel.contentView as? NSHostingView<IslandView> else {
            fputs("Missing controller hosting view.\n", stderr)
            exit(1)
        }
        let presentation = host.rootView.island
        let originalKeyWindow = app.keyWindow
        func headerPoint() -> NSPoint {
            NSPoint(x: controller.panel.frame.midX, y: controller.panel.frame.maxY - presentation.headerHeight / 2)
        }
        func collapsed() -> Bool { !presentation.expanded && presentation.expansion == 0 }

        settle()
        expect(controller.panel.isOnActiveSpace, "native panel is on the active Space")
        expect(collapsed(), "restored hard stop starts collapsed without hover")

        for state in [SessionState.idle, .focusBeforeCheckpoint, .checkpointReached,
                      .focusAfterCheckpoint, .hardStopReached, .onBreak] {
            model.snapshot = SessionSnapshot(state: state)
            settle()
            expect(collapsed(), "\(state.rawValue): unattended transition stays collapsed")
            pointer = headerPoint()
            settle()
            expect(presentation.expanded && presentation.expansion == 1, "\(state.rawValue): hover expands")
            pointer = outside
            settle()
            expect(collapsed(), "\(state.rawValue): pointer exit collapses")
        }

        model.snapshot = SessionSnapshot(state: .hardStopReached)
        pointer = headerPoint()
        settle()
        controller.setMenuOpen(true)
        pointer = outside
        settle()
        expect(collapsed(), "opening menu folds the movement prompt away")
        controller.setMenuOpen(false)
        settle()
        expect(collapsed(), "closing menu without hover keeps movement prompt collapsed")
        pointer = headerPoint()
        settle()
        expect(presentation.expanded, "movement prompt can expand again after menu dismissal")

        pointer = outside
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        settle()
        expect(collapsed(), "Space change without hover resets the movement prompt")
        pointer = headerPoint()
        settle()
        expect(presentation.expanded, "hover still works after a Space reset")

        model.snapshot = SessionSnapshot(state: .checkpointReached)
        settle()
        model.snapshot = SessionSnapshot(state: .hardStopReached)
        settle()
        expect(presentation.expanded, "hard stop reached while hovered keeps controls available")
        pointer = outside
        settle()
        expect(collapsed(), "leaving a hard stop reached while hovered collapses")

        pointer = headerPoint()
        settle(0.11)
        pointer = outside
        settle()
        expect(collapsed(), "brief pointer transit leaves no persistent expansion")
        pointer = headerPoint()
        settle()
        pointer = outside
        settle(0.42)
        pointer = headerPoint()
        settle()
        expect(presentation.expanded && presentation.expansion == 1, "re-entry during collapse restores expansion")
        pointer = outside
        settle()
        expect(collapsed(), "final pointer exit collapses after re-entry")
        expect(app.keyWindow === originalKeyWindow, "passive controller updates preserve keyboard focus")
        if !presentation.attachedToNotch {
            expect(controller.panel.frame.maxY - presentation.headerHeight >= screen.frame.maxY - 30, "compact header stays within the actual menu-bar band")
            for state in [SessionState.idle, .focusBeforeCheckpoint, .checkpointReached,
                          .focusAfterCheckpoint, .hardStopReached, .onBreak] {
                model.snapshot = SessionSnapshot(state: state)
                menuVisible = false
                settle()
                expect(!controller.panel.isVisible && collapsed() && controller.panel.ignoresMouseEvents, "\(state.rawValue): hidden menu bar removes the pill and its input")
                pointer = headerPoint()
                settle()
                expect(!controller.panel.isVisible && collapsed(), "\(state.rawValue): hidden bar cannot trigger expansion")
                pointer = outside
                menuVisible = true
                settle()
                expect(controller.panel.isVisible && collapsed(), "\(state.rawValue): menu-bar return restores compact pill")
            }
            pointer = headerPoint()
            settle()
            menuVisible = false
            settle()
            expect(!controller.panel.isVisible && collapsed(), "header hover cannot keep the pill above a newly hidden fullscreen menu bar")
            pointer = outside
            menuVisible = true
            settle()
            pointer = headerPoint()
            settle()
            pointer = NSPoint(x: controller.panel.frame.midX, y: controller.panel.frame.maxY - presentation.headerHeight - 40)
            menuVisible = false
            settle()
            expect(controller.panel.isVisible && presentation.expanded, "revealed fullscreen controls remain usable below an auto-hidden bar")
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            settle()
            expect(!controller.panel.isVisible && collapsed(), "Space transition clears the hovered-body exception")
            pointer = outside
            menuVisible = true
            settle()
            pointer = headerPoint()
            settle()
            pointer = NSPoint(x: controller.panel.frame.midX, y: controller.panel.frame.maxY - presentation.headerHeight - 40)
            menuVisible = false
            settle()
            pointer = outside
            settle()
            expect(!controller.panel.isVisible && collapsed(), "leaving fullscreen controls removes the overlay")
            menuVisible = true
            settle()
            pointer = headerPoint()
            settle()
            menuVisible = false
            controller.setMenuOpen(true)
            settle()
            expect(!controller.panel.isVisible && collapsed(), "menu dismissal cannot leave a hidden-bar overlay")
            pointer = outside
            controller.setMenuOpen(false)
            menuVisible = true
            settle()
            expect(controller.panel.isVisible && collapsed(), "compact pill recovers after menu suppression")
            expect(app.keyWindow === originalKeyWindow, "visibility changes never take keyboard focus")
        }
        controller.panel.orderOut(nil)
        print("PASS: all native hover-controller checks")
    }
}
