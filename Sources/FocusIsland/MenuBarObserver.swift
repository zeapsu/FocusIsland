import AppKit
import ApplicationServices
import FocusCore

/// Reads the macOS 27 menu bar through Accessibility, which the user grants
/// from Settings. Without the grant there is no reading and the island keeps
/// its guess-based fold.
@MainActor
final class MenuBarObserver: ObservableObject {
    typealias Frames = (controls: [CGRect], items: [CGRect])
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var frames: Frames?
    /// Readings only matter while the island sits in a notch; skip the queries otherwise.
    var isActive = true { didSet { if isActive != oldValue { refresh() } } }
    private var timer: Timer?
    private var hasPrompted = false
    private var agent: (pid: pid_t, element: AXUIElement)?

    init() {
        // Trust is re-read on every tick, so a grant is picked up without a relaunch.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// The first request shows the system prompt. Once Focus Island is listed,
    /// macOS no longer prompts, so later requests open the Accessibility pane.
    func requestAccess() {
        if hasPrompted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        } else {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            isTrusted = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            hasPrompted = true
        }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
        let next = trusted && isActive ? readFrames() : nil
        if next?.controls != frames?.controls || next?.items != frames?.items || (next == nil) != (frames == nil) { frames = next }
    }

    /// MenuBarAgent draws each display's menu bar as one window. Its direct
    /// buttons are the overflow control; each status icon sits one level
    /// down. Matching by role and position avoids localized titles.
    private func readFrames() -> Frames? {
        guard let app = agentElement(),
              let windows = Self.attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        var controls: [CGRect] = [], items: [CGRect] = []
        for window in windows {
            for child in Self.children(window) {
                if Self.role(child) == kAXButtonRole, let f = Self.frame(child) { controls.append(f); continue }
                // Third-party icons are buttons; system icons are groups.
                for item in Self.children(child) { if let f = Self.frame(item) { items.append(f) } }
            }
        }
        return (controls, items)
    }

    /// The system agent, found by bundle ID and cached until it relaunches.
    /// A short messaging timeout keeps a busy agent from stalling the island.
    private func agentElement() -> AXUIElement? {
        if let agent, NSRunningApplication(processIdentifier: agent.pid)?.isTerminated == false { return agent.element }
        guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.MenuBarAgent" }) else {
            agent = nil
            return nil
        }
        let element = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        agent = (running.processIdentifier, element)
        return element
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    private static func role(_ element: AXUIElement) -> String? { attribute(element, kAXRoleAttribute) as? String }
    /// Returns nil unless both values decode and the element has a visible size.
    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetType(position as! AXValue) == .cgPoint, AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetType(size as! AXValue) == .cgSize, AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
