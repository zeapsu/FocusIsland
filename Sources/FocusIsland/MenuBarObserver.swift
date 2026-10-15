import AppKit
import ApplicationServices
import FocusCore

/// Reads the macOS 27 menu bar through Accessibility, which the user grants
/// from Settings. Without the grant there is no reading and the island keeps
/// its guess-based fold.
@MainActor
final class MenuBarObserver: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    typealias Frames = (controls: [CGRect], items: [CGRect])
    @Published private(set) var frames: Frames?
    private var timer: Timer?

    init() {
        // Trust is re-read on every tick, so a grant is picked up without a relaunch.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func requestAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        isTrusted = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        if !isTrusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
        let next = trusted ? Self.readFrames() : nil
        if next?.controls != frames?.controls || next?.items != frames?.items { frames = next }
    }

    /// MenuBarAgent draws each display's menu bar as one window. Its direct
    /// buttons are the overflow control; each status icon sits one level
    /// down. Matching by role and position avoids localized titles.
    private static func readFrames() -> Frames? {
        guard let agent = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "MenuBarAgent" }) else { return nil }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        var controls: [CGRect] = [], items: [CGRect] = []
        for window in windows {
            for child in children(window) {
                if role(child) == kAXButtonRole, let f = frame(child) { controls.append(f); continue }
                // Third-party icons are buttons; system icons are groups.
                for item in children(child) { if let f = frame(item) { items.append(f) } }
            }
        }
        return (controls, items)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    private static func role(_ element: AXUIElement) -> String? { attribute(element, kAXRoleAttribute) as? String }
    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
}
