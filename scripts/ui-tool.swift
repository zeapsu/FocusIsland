import AppKit
import ApplicationServices
import CoreGraphics

enum ToolError: Error, CustomStringConvertible {
    case usage(String)
    case targetNotRunning(String)
    case accessibilityDenied
    case elementNotFound(String)
    case axFailure(String, AXError)

    var description: String {
        switch self {
        case .usage(let message): return message
        case .targetNotRunning(let bundleID): return "No running application with bundle identifier " + bundleID
        case .accessibilityDenied: return "Accessibility access is not granted to this terminal or executable. Enable it in System Settings > Privacy & Security > Accessibility."
        case .elementNotFound(let query): return "No accessibility element matched " + query
        case .axFailure(let operation, let error): return operation + " failed: " + String(describing: error)
        }
    }
}

func value(_ element: AXUIElement, _ attribute: String) -> Any? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
    return result
}

func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
    if let string = value(element, attribute) as? String { return string }
    if let number = value(element, attribute) as? NSNumber { return number.stringValue }
    return nil
}

func frameValue(_ element: AXUIElement) -> CGRect? {
    guard let rawValue = value(element, "AXFrame"),
          CFGetTypeID(rawValue as CFTypeRef) == AXValueGetTypeID() else { return nil }
    let axValue = rawValue as! AXValue
    var frame = CGRect.zero
    guard AXValueGetValue(axValue, .cgRect, &frame) else { return nil }
    return frame
}

func appElement(_ bundleID: String) throws -> AXUIElement {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        throw ToolError.targetNotRunning(bundleID)
    }
    return AXUIElementCreateApplication(app.processIdentifier)
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    var parentPID: pid_t = 0
    AXUIElementGetPid(element, &parentPID)
    return (value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { child in
        if CFEqual(child, element) { return false }
        var childPID: pid_t = 0
        AXUIElementGetPid(child, &childPID)
        return !(stringValue(child, kAXRoleAttribute) == kAXApplicationRole && childPID == parentPID)
    }
}

func attributes(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success,
          let names else { return [] }
    return names as NSArray as? [String] ?? []
}

func actions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let names else { return [] }
    return names as NSArray as? [String] ?? []
}

func matches(_ element: AXUIElement, query: String) -> Bool {
    let fields = [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
    return fields.compactMap { stringValue(element, $0) }.contains {
        $0.localizedCaseInsensitiveContains(query)
    }
}

func findElement(_ root: AXUIElement, query: String, depth: Int = 12) -> AXUIElement? {
    if matches(root, query: query) { return root }
    guard depth > 0 else { return nil }
    for child in children(root) {
        if let found = findElement(child, query: query, depth: depth - 1) { return found }
    }
    return nil
}

func describe(_ element: AXUIElement, indent: String = "", depth: Int) {
    let role = stringValue(element, kAXRoleAttribute) ?? "unknown"
    let identifier = stringValue(element, kAXIdentifierAttribute) ?? ""
    let title = stringValue(element, kAXTitleAttribute) ?? ""
    let description = stringValue(element, kAXDescriptionAttribute) ?? ""
    let value = stringValue(element, kAXValueAttribute) ?? ""
    let frame = frameValue(element).map { NSStringFromRect($0) } ?? ""
    let actionNames = actions(element).joined(separator: ",")
    print(indent + "role=" + role + " id=" + identifier + " title=" + title + " desc=" + description + " value=" + value + " frame=" + frame + " actions=" + actionNames)
    guard depth > 0 else { return }
    for child in children(element) { describe(child, indent: indent + "  ", depth: depth - 1) }
}

func requireAccessibility() throws {
    if !AXIsProcessTrusted() { throw ToolError.accessibilityDenied }
}

func click(at point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.04)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        if let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.08)
    }
}

func submitQAInput(_ input: [String: Any]) throws {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("qa/live/input.json")
    guard !FileManager.default.fileExists(atPath: url.path) else {
        throw ToolError.usage("A QA input is still pending. Wait for qa/live/input.json to disappear before sending another.")
    }
    let data = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
    try data.write(to: url, options: .atomic)
}

func usage() -> String {
    """
    Usage:
      ui-tool apps
      ui-tool onscreen-windows <bundle-id>
      ui-tool attributes <bundle-id> [identifier-or-title]
      ui-tool windows <bundle-id>
      ui-tool enable-enhanced <bundle-id>
      ui-tool at <global-x> <global-y>
      ui-tool qa-click <window-index> <x-from-left> <y-from-top>
      ui-tool qa-text <window-index> <text>
      ui-tool qa-key <window-index> <tab|return|escape>
      ui-tool tree <bundle-id> [depth]
      ui-tool inspect <bundle-id> <identifier-or-title>
      ui-tool press <bundle-id> <identifier-or-title>
      ui-tool set-value <bundle-id> <identifier-or-title> <value>
      ui-tool pointer
      ui-tool move <global-x> <global-y>
      ui-tool click <global-x> <global-y>
    """
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw ToolError.usage(usage()) }
    switch command {
    case "onscreen-windows":
        guard arguments.count == 2 else { throw ToolError.usage(usage()) }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: arguments[1]).first else {
            throw ToolError.targetNotRunning(arguments[1])
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let rows: [[String: Any]] = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(app.processIdentifier) }.map {
            ["number": $0[kCGWindowNumber as String] ?? 0,
             "title": $0[kCGWindowName as String] ?? "",
             "bounds": $0[kCGWindowBounds as String] ?? [:],
             "layer": $0[kCGWindowLayer as String] ?? 0]
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    case "apps":
        for app in NSWorkspace.shared.runningApplications.sorted(by: { $0.localizedName ?? "" < $1.localizedName ?? "" }) {
            let name = app.localizedName ?? ""
            let bundle = app.bundleIdentifier ?? ""
            print(name + "\t" + bundle + "\tpid=" + String(app.processIdentifier))
        }
    case "tree":
        guard arguments.count >= 2 else { throw ToolError.usage(usage()) }
        try requireAccessibility()
        let depth = arguments.count >= 3 ? (Int(arguments[2]) ?? 8) : 8
        describe(try appElement(arguments[1]), depth: depth)
    case "attributes":
        guard arguments.count >= 2 else { throw ToolError.usage(usage()) }
        try requireAccessibility()
        let root = try appElement(arguments[1])
        let element: AXUIElement
        if arguments.count >= 3 {
            guard let found = findElement(root, query: arguments[2]) else { throw ToolError.elementNotFound(arguments[2]) }
            element = found
        } else {
            element = root
        }
        for name in attributes(element) { print(name) }
    case "windows":
        guard arguments.count == 2 else { throw ToolError.usage(usage()) }
        try requireAccessibility()
        let root = try appElement(arguments[1])
        for window in value(root, kAXWindowsAttribute) as? [AXUIElement] ?? [] { describe(window, depth: 6) }
    case "close-window":
        guard arguments.count == 3 else { throw ToolError.usage(usage()) }
        try requireAccessibility()
        let app = try appElement(arguments[1])
        let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard let window = windows.first(where: { stringValue($0, kAXTitleAttribute) == arguments[2] }),
              let raw = value(window, kAXCloseButtonAttribute) else { throw ToolError.elementNotFound(arguments[2]) }
        let result = AXUIElementPerformAction(raw as! AXUIElement, kAXPressAction as CFString)
        guard result == .success else { throw ToolError.axFailure("Close window", result) }
    case "enable-enhanced":
        guard arguments.count == 2 else { throw ToolError.usage(usage()) }
        try requireAccessibility()
        let result = AXUIElementSetAttributeValue(try appElement(arguments[1]), "AXEnhancedUserInterface" as CFString, true as CFBoolean)
        guard result == .success else { throw ToolError.axFailure("Enable enhanced accessibility", result) }
    case "at":
        guard arguments.count == 3, let x = Float(arguments[1]), let y = Float(arguments[2]) else { throw ToolError.usage(usage()) }
        try requireAccessibility()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), x, y, &element)
        guard result == .success, let element else { throw ToolError.axFailure("Find accessibility element at position", result) }
        describe(element, depth: 4)
    case "inspect", "press", "confirm", "set-value":
        guard arguments.count >= 3 else { throw ToolError.usage(usage()) }
        try requireAccessibility()
        let root = try appElement(arguments[1])
        guard let element = findElement(root, query: arguments[2]) else { throw ToolError.elementNotFound(arguments[2]) }
        if command == "inspect" {
            describe(element, depth: 2)
        } else if command == "press" || command == "confirm" {
            let result = AXUIElementPerformAction(element, (command == "press" ? kAXPressAction : kAXConfirmAction) as CFString)
            guard result == .success else { throw ToolError.axFailure("Press", result) }
        } else {
            guard arguments.count >= 4 else { throw ToolError.usage(usage()) }
            let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, arguments[3] as CFString)
            guard result == .success else { throw ToolError.axFailure("Set value", result) }
        }
    case "move", "click":
        guard arguments.count == 3, let x = Double(arguments[1]), let y = Double(arguments[2]) else { throw ToolError.usage(usage()) }
        let point = CGPoint(x: x, y: y)
        if command == "move" {
            let source = CGEventSource(stateID: .combinedSessionState)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        } else {
            click(at: point)
        }
    case "pointer":
        let point = NSEvent.mouseLocation
        print(String(format: "%.0f %.0f", point.x, point.y))
    case "qa-click":
        guard arguments.count == 4,
              let window = Int(arguments[1]), let x = Double(arguments[2]), let y = Double(arguments[3]) else { throw ToolError.usage(usage()) }
        try submitQAInput(["type": "click", "window": window, "x": x, "y": y])
    case "qa-text":
        guard arguments.count == 3, let window = Int(arguments[1]) else { throw ToolError.usage(usage()) }
        try submitQAInput(["type": "text", "window": window, "text": arguments[2]])
    case "qa-key":
        guard arguments.count == 3, let window = Int(arguments[1]), ["tab", "return", "escape"].contains(arguments[2]) else { throw ToolError.usage(usage()) }
        try submitQAInput(["type": "key", "window": window, "key": arguments[2]])
    default:
        throw ToolError.usage(usage())
    }
} catch {
    FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8))
    exit(2)
}
