// A separate, disposable native window for QA of foreign full-screen Spaces.
// Compile into .build/FullscreenFixture.app; never included in Focus Island.
import AppKit

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 220, y: 180, width: 800, height: 500), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        self.window = window
        window.title = "Focus Island Fullscreen QA"
        window.collectionBehavior = [.fullScreenPrimary]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 24
        stack.addArrangedSubview(NSTextField(labelWithString: "Full-screen test window. No documents or user data."))
        stack.addArrangedSubview(NSButton(title: "Toggle Full Screen", target: self, action: #selector(toggle)))
        stack.addArrangedSubview(NSButton(title: "Maximize on Desktop", target: self, action: #selector(maximizeDesktop)))
        stack.addArrangedSubview(NSButton(title: "Normal Window", target: self, action: #selector(normalWindow)))
        stack.addArrangedSubview(NSButton(title: "Quit Fixture", target: NSApp, action: #selector(NSApplication.terminate(_:))))
        window.contentView?.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let content = window.contentView {
            NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: content.centerXAnchor), stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)])
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func toggle() { window?.toggleFullScreen(nil) }
    @objc private func maximizeDesktop() {
        guard let window, !window.styleMask.contains(.fullScreen), let screen = window.screen else { return }
        var frame = screen.frame
        frame.size.height -= max(34, screen.safeAreaInsets.top)
        window.setFrame(frame, display: true)
    }
    @objc private func normalWindow() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.setContentSize(NSSize(width: 800, height: 500))
        window.center()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = FixtureDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
