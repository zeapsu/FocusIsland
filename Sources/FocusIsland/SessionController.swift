import AppKit
import Combine
import FocusCore

@MainActor
final class SessionController: ObservableObject {
    @Published private(set) var snapshot: SessionSnapshot
    @Published private(set) var settings: TimerSettings
    @Published private(set) var now = Date()
    @Published private(set) var completionMessage: String?
    let notifications: NotificationManager
    let isQA: Bool
    private let store: LocalStore
    private var engine: SessionEngine
    private var ticker: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var scale: Double { isQA ? 0.05 : 1 }

    init() {
        #if DEBUG
        isQA = CommandLine.arguments.contains("--qa-speed")
        #else
        isQA = false
        #endif
        let defaults = isQA ? UserDefaults(suiteName: "local.focusisland.qa") ?? .standard : .standard
        store = LocalStore(defaults: defaults)
        settings = store.loadSettings()
        engine = SessionEngine(snapshot: store.loadSession(), now: Date())
        snapshot = engine.snapshot
        notifications = NotificationManager()
        // Codable ignores the retired theme field in older preferences.
        // Save the current schema while preserving the user's durations.
        store.saveSettings(settings)
        store.saveSession(snapshot)
        syncNotifications()
        ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refresh() }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                await self?.notifications.updatePermission()
            }
        })
    }

    func refresh() {
        now = Date()
        let previous = engine.snapshot
        if engine.refresh(now: now) { completionMessage = "Break complete. Ready when you are." }
        publish(previous: previous, preservingDueNotices: true)
    }

    func startFocus() {
        refresh()
        let previous = engine.snapshot
        if engine.startFocus(settings: settings, now: now, timeScale: scale) { completionMessage = nil }
        publish(previous: previous)
    }
    func continueFocus() {
        refresh()
        let previous = engine.snapshot
        engine.continueFocus(now: now)
        publish(previous: previous)
    }
    func startBreak() {
        refresh()
        let previous = engine.snapshot
        engine.startBreak(settings: settings, now: now, timeScale: scale)
        completionMessage = nil
        publish(previous: previous)
    }
    func cancel() {
        let previous = engine.snapshot
        engine.cancel()
        completionMessage = nil
        publish(previous: previous)
    }
    func saveSettings(_ new: TimerSettings) {
        guard new.validationError == nil else { return }
        settings = new
        store.saveSettings(new)
    }

    /// Keep the persisted absolute deadlines current before Sparkle or the user
    /// terminates the process. This is intentionally synchronous so a delayed
    /// termination reply cannot race session persistence.
    func prepareForTermination() {
        refresh()
        store.saveSession(snapshot)
    }

    private func publish(previous: SessionSnapshot, preservingDueNotices: Bool = false) {
        guard previous != engine.snapshot else { return }
        snapshot = engine.snapshot
        store.saveSession(snapshot)
        syncNotifications(preservingDueNotices: preservingDueNotices)
    }
    private func syncNotifications(preservingDueNotices: Bool = false) {
        notifications.synchronize(notificationPlan(snapshot: snapshot, now: now), preservingDueNotices: preservingDueNotices)
    }

    var title: String {
        switch snapshot.state {
        case .idle: return "Ready to focus"
        case .focusBeforeCheckpoint, .focusAfterCheckpoint: return "Focus"
        case .checkpointReached: return "Still focused?"
        case .hardStopReached: return "Time to get up and move."
        case .onBreak: return "Take a break"
        }
    }
    var icon: String {
        switch snapshot.state {
        case .idle: return "circle.dotted"
        case .focusBeforeCheckpoint, .focusAfterCheckpoint: return "scope"
        case .checkpointReached: return "questionmark.circle"
        case .hardStopReached: return "figure.walk"
        case .onBreak: return "cup.and.saucer"
        }
    }
    var clockText: String {
        let seconds: TimeInterval
        switch snapshot.state {
        case .idle: return ""
        case .onBreak: seconds = max(0, (snapshot.breakEndAt ?? now).timeIntervalSince(now))
        case .hardStopReached: seconds = max(0, (snapshot.hardStopAt ?? now).timeIntervalSince(snapshot.sessionStart ?? now))
        default: seconds = max(0, now.timeIntervalSince(snapshot.sessionStart ?? now))
        }
        return Self.format(seconds, roundUp: snapshot.state == .onBreak)
    }
    static func format(_ seconds: TimeInterval, roundUp: Bool = false) -> String {
        let safe = max(0, min(seconds, 7 * 86400))
        let total = Int(roundUp ? ceil(safe) : floor(safe))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    var detail: String {
        switch snapshot.state {
        case .idle: return completionMessage ?? "A little awareness. Room to concentrate."
        case .focusBeforeCheckpoint: return "Check in in \(Self.format(max(0, (snapshot.checkpointAt ?? now).timeIntervalSince(now)), roundUp: true))"
        case .checkpointReached: return "Keep going, or give yourself a break."
        case .focusAfterCheckpoint: return "Movement break in \(Self.format(max(0, (snapshot.hardStopAt ?? now).timeIntervalSince(now)), roundUp: true))"
        case .hardStopReached: return "Stand up, stretch, and look away from the screen."
        case .onBreak: return "Time to recharge. Focus can wait."
        }
    }
    var progress: Double {
        let start = snapshot.state == .onBreak ? snapshot.breakStart : snapshot.sessionStart
        let end = snapshot.state == .onBreak ? snapshot.breakEndAt : snapshot.hardStopAt
        guard let start, let end, end > start else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }
}
