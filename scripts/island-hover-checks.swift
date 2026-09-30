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
        let model = SessionController()
        let controller = IslandWindowController(model: model, openMenu: {}, pointerLocation: { pointer })
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
        controller.panel.orderOut(nil)
        print("PASS: all native hover-controller checks")
    }
}
