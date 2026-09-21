import AppKit
import UserNotifications
import FocusCore

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var permissionText = "Notifications are optional. The island always shows your timer."
    @Published private(set) var authorizationStatus: UNAuthorizationStatus?
    @Published private(set) var isRequestingPermission = false
    private let center = UNUserNotificationCenter.current()
    private var generation = 0
    private var pending: Task<Void, Never>?
    private var notices: [ScheduledNotice] = []

    override init() {
        super.init()
        center.delegate = self
        Task { await updatePermission() }
    }

    var permissionButtonTitle: String {
        if isRequestingPermission { return "Checking Notifications…" }
        guard let authorizationStatus else { return "Checking Notifications…" }
        return authorizationStatus == .notDetermined ? "Enable Notifications" : "Open Notification Settings…"
    }

    func handlePermissionAction() {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        Task {
            defer { isRequestingPermission = false }
            // Re-read the system state in case it changed while Settings was open.
            await updatePermission()
            guard authorizationStatus == .notDetermined else {
                openNotificationSettings()
                return
            }
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                await updatePermission()
            } catch {
                await updatePermission()
                // Keep this error visible instead of overwriting it with the status.
                permissionText = "Couldn't request notifications. Open System Settings > Notifications > Focus Island. Your timer still works."
            }
        }
    }

    func updatePermission() async {
        let settings = await center.notificationSettings()
        let previous = authorizationStatus
        authorizationStatus = settings.authorizationStatus
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: permissionText = "Notifications enabled."
        case .denied: permissionText = "Notifications are off. Turn on Allow Notifications for Focus Island in System Settings."
        case .notDetermined: permissionText = "Enable gentle checkpoint, movement and break reminders."
        @unknown default: permissionText = "Your timer works independently of notifications."
        }
        // Apply permission changes to the current session without moving its deadlines.
        if previous != settings.authorizationStatus { synchronize(notices) }
    }

    private func openNotificationSettings() {
        var components = URLComponents()
        components.scheme = "x-apple.systempreferences"
        components.path = "com.apple.Notifications-Settings.extension"
        if let bundleID = Bundle.main.bundleIdentifier {
            components.queryItems = [URLQueryItem(name: "id", value: bundleID)]
        }
        if let url = components.url, NSWorkspace.shared.open(url) { return }
        permissionText = "Open System Settings > Notifications > Focus Island to change notification permissions."
    }

    // Chain updates so an older asynchronous add cannot survive a newer cancel.
    func synchronize(_ plan: [ScheduledNotice], preservingDueNotices: Bool = false) {
        notices = plan
        generation += 1
        let revision = generation
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            guard let self, revision == self.generation else { return }
            let old = await self.center.pendingNotificationRequests()
            self.center.removePendingNotificationRequests(withIdentifiers: old.filter { request in
                guard request.identifier.hasPrefix("focus-island.") else { return false }
                // Calendar triggers have whole-second precision. Let an event that just
                // became due finish delivering when the engine crosses its deadline.
                if preservingDueNotices, let deadline = request.content.userInfo["deadline"] as? Double {
                    let age = Date().timeIntervalSince1970 - deadline
                    if age >= 0 && age < 2 { return false }
                }
                return true
            }.map(\.identifier))
            let settings = await self.center.notificationSettings()
            guard revision == self.generation, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            for notice in plan where notice.date > Date() {
                guard revision == self.generation else { break }
                let content = UNMutableNotificationContent()
                content.title = notice.title
                content.body = notice.body
                content.userInfo = ["deadline": notice.date.timeIntervalSince1970]
                content.sound = .default
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
                let deadline = Date(timeIntervalSince1970: ceil(notice.date.timeIntervalSince1970))
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: deadline)
                components.timeZone = calendar.timeZone
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                do {
                    try await self.center.add(UNNotificationRequest(identifier: "focus-island." + notice.id, content: content, trigger: trigger))
                } catch { self.permissionText = "A reminder could not be scheduled. Your timer still works." }
            }
        }
    }

    func finishPending() async { await pending?.value }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
