import Foundation

/// The durable states used by the focus-session state machine.
public enum SessionState: String, Codable, Equatable, Sendable {
    case idle
    case focusBeforeCheckpoint
    case checkpointReached
    case focusAfterCheckpoint
    case hardStopReached
    case onBreak
}

public enum ThemePreference: String, CaseIterable, Codable, Equatable, Sendable {
    case system
    case solarizedLight
    case solarizedDark

    public var displayName: String {
        switch self {
        case .system: "System"
        case .solarizedLight: "Solarized Light"
        case .solarizedDark: "Solarized Dark"
        }
    }
}

public struct TimerSettings: Codable, Equatable, Sendable {
    public var checkpointMinutes: Int
    public var hardStopMinutes: Int
    public var breakMinutes: Int
    public var theme: ThemePreference

    public init(
        checkpointMinutes: Int = 50,
        hardStopMinutes: Int = 90,
        breakMinutes: Int = 10,
        theme: ThemePreference = .system
    ) {
        self.checkpointMinutes = checkpointMinutes
        self.hardStopMinutes = hardStopMinutes
        self.breakMinutes = breakMinutes
        self.theme = theme
    }

    /// A user-facing validation message, or nil when these values can be used.
    public var validationError: String? {
        guard (1...239).contains(checkpointMinutes) else {
            return "Checkpoint must be between 1 and 239 minutes."
        }
        guard (2...240).contains(hardStopMinutes) else {
            return "Hard stop must be between 2 and 240 minutes."
        }
        guard hardStopMinutes > checkpointMinutes else {
            return "Hard stop must be longer than the checkpoint."
        }
        guard (1...120).contains(breakMinutes) else {
            return "Break must be between 1 and 120 minutes."
        }
        return nil
    }
}

/// A codable record. Deadlines are stored directly so later settings edits never
/// change an active session.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    public var state: SessionState
    public var id: UUID?
    public var sessionStart: Date?
    public var checkpointAt: Date?
    public var hardStopAt: Date?
    public var breakStart: Date?
    public var breakEndAt: Date?
    public var schemaVersion: Int

    public init(
        state: SessionState = .idle,
        id: UUID? = nil,
        sessionStart: Date? = nil,
        checkpointAt: Date? = nil,
        hardStopAt: Date? = nil,
        breakStart: Date? = nil,
        breakEndAt: Date? = nil,
        schemaVersion: Int = 1
    ) {
        self.state = state
        self.id = id
        self.sessionStart = sessionStart
        self.checkpointAt = checkpointAt
        self.hardStopAt = hardStopAt
        self.breakStart = breakStart
        self.breakEndAt = breakEndAt
        self.schemaVersion = schemaVersion
    }
}

public struct SessionEngine: Sendable {
    public private(set) var snapshot: SessionSnapshot

    public init(snapshot: SessionSnapshot = .init(), now: Date = Date()) {
        self.snapshot = Self.normalized(snapshot)
        _ = refresh(now: now)
    }

    @discardableResult
    public mutating func startFocus(
        settings: TimerSettings,
        now: Date = Date(),
        timeScale: Double = 1
    ) -> Bool {
        guard snapshot.state == .idle,
              settings.validationError == nil,
              Self.validTimeScale(timeScale) else { return false }

        let checkpoint = now.addingTimeInterval(Double(settings.checkpointMinutes) * 60 * timeScale)
        let hardStop = now.addingTimeInterval(Double(settings.hardStopMinutes) * 60 * timeScale)
        snapshot = SessionSnapshot(
            state: .focusBeforeCheckpoint,
            id: UUID(),
            sessionStart: now,
            checkpointAt: checkpoint,
            hardStopAt: hardStop
        )
        return true
    }

    @discardableResult
    public mutating func continueFocus(now: Date = Date()) -> Bool {
        _ = refresh(now: now)
        guard snapshot.state == .checkpointReached else { return false }
        snapshot.state = .focusAfterCheckpoint
        return true
    }

    @discardableResult
    public mutating func startBreak(
        settings: TimerSettings,
        now: Date = Date(),
        timeScale: Double = 1
    ) -> Bool {
        _ = refresh(now: now)
        guard settings.validationError == nil,
              Self.validTimeScale(timeScale),
              snapshot.state != .onBreak else { return false }

        let breakEnd = now.addingTimeInterval(Double(settings.breakMinutes) * 60 * timeScale)
        snapshot = SessionSnapshot(
            state: .onBreak,
            id: snapshot.id ?? UUID(),
            breakStart: now,
            breakEndAt: breakEnd
        )
        return true
    }

    public mutating func cancel() {
        snapshot = SessionSnapshot()
    }

    /// Reconciles the durable state against an absolute clock. It never rewinds
    /// an already-reached state if the system clock temporarily moves backward.
    /// Returns true only when a break has just completed.
    @discardableResult
    public mutating func refresh(now: Date = Date()) -> Bool {
        switch snapshot.state {
        case .focusBeforeCheckpoint:
            if let hardStopAt = snapshot.hardStopAt, now >= hardStopAt {
                snapshot.state = .hardStopReached
            } else if let checkpointAt = snapshot.checkpointAt, now >= checkpointAt {
                snapshot.state = .checkpointReached
            }
        case .checkpointReached, .focusAfterCheckpoint:
            if let hardStopAt = snapshot.hardStopAt, now >= hardStopAt {
                snapshot.state = .hardStopReached
            }
        case .onBreak:
            if let breakEndAt = snapshot.breakEndAt, now >= breakEndAt {
                snapshot = SessionSnapshot()
                return true
            }
        case .idle, .hardStopReached:
            break
        }
        return false
    }

    private static func normalized(_ input: SessionSnapshot) -> SessionSnapshot {
        guard input.schemaVersion == 1 else { return SessionSnapshot() }
        switch input.state {
        case .idle:
            return SessionSnapshot()
        case .focusBeforeCheckpoint, .checkpointReached, .focusAfterCheckpoint, .hardStopReached:
            guard let id = input.id,
                  let start = input.sessionStart,
                  let checkpoint = input.checkpointAt,
                  let hardStop = input.hardStopAt,
                  start < checkpoint,
                  checkpoint < hardStop,
                  Self.isFinite(start),
                  Self.isFinite(checkpoint),
                  Self.isFinite(hardStop) else { return SessionSnapshot() }
            var output = input
            output.id = id
            output.sessionStart = start
            output.checkpointAt = checkpoint
            output.hardStopAt = hardStop
            return output
        case .onBreak:
            guard let id = input.id,
                  let breakStart = input.breakStart,
                  let breakEnd = input.breakEndAt,
                  breakStart < breakEnd,
                  Self.isFinite(breakStart),
                  Self.isFinite(breakEnd) else { return SessionSnapshot() }
            var output = input
            output.id = id
            output.breakStart = breakStart
            output.breakEndAt = breakEnd
            return output
        }
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    private static func validTimeScale(_ value: Double) -> Bool {
        guard value.isFinite, value > 0 else { return false }
        #if DEBUG
        return true
        #else
        return value == 1
        #endif
    }
}

public struct ScheduledNotice: Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let date: Date

    public init(id: String, title: String, body: String, date: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.date = date
    }
}

/// Produces notices that are still useful at `now`; scheduling is left to the UI
/// layer so the domain model remains testable without UserNotifications.
public func notificationPlan(snapshot: SessionSnapshot, now: Date = Date()) -> [ScheduledNotice] {
    guard let id = snapshot.id else { return [] }
    func notice(_ suffix: String, _ title: String, _ body: String, _ date: Date?) -> ScheduledNotice? {
        guard let date, date > now else { return nil }
        return ScheduledNotice(id: "\(id.uuidString).\(suffix)", title: title, body: body, date: date)
    }

    switch snapshot.state {
    case .focusBeforeCheckpoint:
        return [
            notice("checkpoint", "Still focused?", "Choose whether to continue or take a break.", snapshot.checkpointAt),
            notice("hard-stop", "Time to get up and move.", "Your focus block has reached its hard stop.", snapshot.hardStopAt)
        ].compactMap { $0 }
    case .checkpointReached, .focusAfterCheckpoint:
        return [notice("hard-stop", "Time to get up and move.", "Your focus block has reached its hard stop.", snapshot.hardStopAt)].compactMap { $0 }
    case .onBreak:
        return [notice("break-complete", "Break complete.", "You are ready for another focus block.", snapshot.breakEndAt)].compactMap { $0 }
    case .idle, .hardStopReached:
        return []
    }
}

public struct LocalStore {
    private let defaults: UserDefaults
    private let settingsKey = "focusIsland.settings.v1"
    private let sessionKey = "focusIsland.session.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSettings() -> TimerSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(TimerSettings.self, from: data),
              settings.validationError == nil else { return TimerSettings() }
        return settings
    }

    public func saveSettings(_ settings: TimerSettings) {
        guard settings.validationError == nil,
              let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }

    public func loadSession(now: Date = Date()) -> SessionSnapshot {
        guard let data = defaults.data(forKey: sessionKey),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data) else { return SessionSnapshot() }
        return SessionEngine(snapshot: snapshot, now: now).snapshot
    }

    public func saveSession(_ snapshot: SessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: sessionKey)
    }
}
