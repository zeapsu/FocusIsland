#if DEBUG
import AppKit
import UserNotifications

// Opt-in snapshots of this app's own views, for UI QA when system screen capture is unavailable.
@MainActor enum QADiagnostics {
    private static var nativeNotifications: [String: Any] = [:]
    private static var queryingNotifications = false
    static func capture(model: SessionController) {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--qa-artifacts"), args.indices.contains(flag + 1) else { return }
        let directory = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if model.isQA { processInput(directory: directory) }
        if !queryingNotifications {
            queryingNotifications = true
            Task {
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                let pending = await center.pendingNotificationRequests()
                let delivered = await center.deliveredNotifications()
                nativeNotifications = ["authorization": settings.authorizationStatus.rawValue,
                    "pending": pending.map { ["id": $0.identifier, "title": $0.content.title, "deadline": ($0.content.userInfo["deadline"] as? Double) ?? 0] },
                    "delivered": delivered.map { ["id": $0.request.identifier, "title": $0.request.content.title] }]
                queryingNotifications = false
            }
        }
        var windows: [[String: Any]] = []
        let listed = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let onScreenIDs = Set(listed.compactMap { $0[kCGWindowNumber as String] as? Int })
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView else { continue }
            windows.append(["index": index, "number": window.windowNumber, "title": window.title, "frame": NSStringFromRect(window.frame), "level": window.level.rawValue, "role": window.accessibilityRole()?.rawValue ?? "nil", "appearance": window.effectiveAppearance.name.rawValue, "onActiveSpace": window.isOnActiveSpace, "onScreen": onScreenIDs.contains(window.windowNumber)])
            guard view.bounds.width > 0, view.bounds.height > 0, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: directory.appendingPathComponent("window-\(index).png"), options: .atomic) }
        }
        let result: [String: Any] = ["state": model.snapshot.state.rawValue, "clock": model.clockText, "theme": model.settings.theme.rawValue, "windows": windows, "time": Date().timeIntervalSince1970, "activationPolicy": NSApp.activationPolicy().rawValue, "systemPresentation": NSApp.currentSystemPresentationOptions.rawValue, "notifications": nativeNotifications,
            "sessionStart": model.snapshot.sessionStart?.timeIntervalSince1970 ?? 0,
            "checkpointAt": model.snapshot.checkpointAt?.timeIntervalSince1970 ?? 0,
            "hardStopAt": model.snapshot.hardStopAt?.timeIntervalSince1970 ?? 0,
            "breakEndAt": model.snapshot.breakEndAt?.timeIntervalSince1970 ?? 0]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: directory.appendingPathComponent("live.json"), options: .atomic) }
    }

    private static func processInput(directory: URL) {
        let input = directory.appendingPathComponent("input.json")
        guard let data = try? Data(contentsOf: input),
              let command = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        try? FileManager.default.removeItem(at: input)
        guard let number = command["window"] as? Int,
              let window = NSApp.windows.first(where: { $0.windowNumber == number && $0.isVisible }) else { return }
        // These events enter AppKit's actual hit testing and text-input paths.
        // No QA command calls the session model or changes preferences directly.
        if command["type"] as? String == "click", let x = command["x"] as? Double, let y = command["y"] as? Double {
            let point = NSPoint(x: x, y: window.frame.height - y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: number, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { NSApp.postEvent(event, atStart: false) }
            }
        } else if command["type"] as? String == "text", let text = command["text"] as? String {
            window.makeKey()
            if let editor = window.firstResponder as? NSTextView { editor.selectAll(nil); editor.insertText(text, replacementRange: editor.selectedRange()) }
        } else if command["type"] as? String == "key", let key = command["key"] as? String {
            let chars = key == "tab" ? "\t" : key == "return" ? "\r" : "\u{1b}"
            let code: UInt16 = key == "tab" ? 48 : key == "return" ? 36 : 53
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: number, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) { NSApp.postEvent(event, atStart: false) }
        }
    }
}
#endif
