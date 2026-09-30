import Foundation
import CoreGraphics
import FocusCore

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let message): message } }
}

var assertionCount = 0

@inline(__always)
func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    assertionCount += 1
    guard condition() else { throw CheckFailure.failed(message) }
}

let origin = Date(timeIntervalSinceReferenceDate: 1_000_000)
func makeSettings(_ checkpoint: Int = 50, _ hardStop: Int = 90, _ breakMinutes: Int = 10) -> TimerSettings {
    TimerSettings(checkpointMinutes: checkpoint, hardStopMinutes: hardStop, breakMinutes: breakMinutes)
}
func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
}
func sameRect(_ left: CGRect, _ right: CGRect) -> Bool {
    left.origin.x == right.origin.x && left.origin.y == right.origin.y &&
        left.size.width == right.size.width && left.size.height == right.size.height
}
func temporaryDefaults() -> UserDefaults {
    let suite = "FocusCoreChecks.\(UUID().uuidString)"
    let result = UserDefaults(suiteName: suite)!
    result.removePersistentDomain(forName: suite)
    return result
}

func testFocusLifecycle() throws {
    var engine = SessionEngine(now: origin)
    try check(engine.startFocus(settings: makeSettings(), now: origin), "new session starts")
    try check(engine.snapshot.state == .focusBeforeCheckpoint, "new session is before checkpoint")
    try check(engine.snapshot.checkpointAt == origin.addingTimeInterval(3_000), "checkpoint is absolute")
    try check(engine.snapshot.hardStopAt == origin.addingTimeInterval(5_400), "hard stop is absolute")
    engine.refresh(now: origin.addingTimeInterval(3_000))
    try check(engine.snapshot.state == .checkpointReached, "checkpoint exact boundary")
    try check(engine.continueFocus(now: origin.addingTimeInterval(3_001)), "continue from checkpoint")
    try check(engine.snapshot.state == .focusAfterCheckpoint, "continue state")
    engine.refresh(now: origin.addingTimeInterval(5_400))
    try check(engine.snapshot.state == .hardStopReached, "hard stop exact boundary")
    try check(!engine.continueFocus(now: origin.addingTimeInterval(5_401)), "cannot continue after hard stop")
    try check(engine.startBreak(settings: makeSettings(), now: origin.addingTimeInterval(5_401)), "break starts at hard stop")
    try check(engine.snapshot.state == .onBreak, "break state")
    try check(!engine.refresh(now: origin.addingTimeInterval(6_000)), "break remains before end")
    try check(engine.refresh(now: origin.addingTimeInterval(6_001)), "break completion event")
    try check(engine.snapshot.state == .idle, "break returns idle")
    try check(!engine.refresh(now: origin.addingTimeInterval(6_002)), "completion happens once")
}

func testInactiveRehydrationAndClockMonotonicity() throws {
    var engine = SessionEngine(now: origin)
    _ = engine.startFocus(settings: makeSettings(), now: origin)
    let saved = engine.snapshot
    try check(SessionEngine(snapshot: saved, now: origin.addingTimeInterval(3_000)).snapshot.state == .checkpointReached, "rehydration reaches checkpoint")
    try check(SessionEngine(snapshot: saved, now: origin.addingTimeInterval(5_400)).snapshot.state == .hardStopReached, "hard stop overrides missed checkpoint")
    let checkpointed = SessionEngine(snapshot: saved, now: origin.addingTimeInterval(3_000)).snapshot
    try check(SessionEngine(snapshot: checkpointed, now: origin.addingTimeInterval(5_400)).snapshot.state == .hardStopReached, "persisted checkpoint reaches hard stop")
    engine.refresh(now: origin.addingTimeInterval(3_000))
    engine.refresh(now: origin.addingTimeInterval(1))
    try check(engine.snapshot.state == .checkpointReached, "backward clock does not rewind checkpoint")
    _ = engine.continueFocus(now: origin.addingTimeInterval(1))
    try check(engine.snapshot.state == .focusAfterCheckpoint, "continue after backward clock")
}

func testEarlyBreakTransitions() throws {
    let times: [SessionState] = [.idle, .focusBeforeCheckpoint, .checkpointReached, .focusAfterCheckpoint, .hardStopReached]
    for expectedState in times {
        var engine = SessionEngine(now: origin)
        switch expectedState {
        case .idle: break
        case .focusBeforeCheckpoint:
            _ = engine.startFocus(settings: makeSettings(), now: origin)
        case .checkpointReached:
            _ = engine.startFocus(settings: makeSettings(), now: origin)
            engine.refresh(now: origin.addingTimeInterval(3_000))
        case .focusAfterCheckpoint:
            _ = engine.startFocus(settings: makeSettings(), now: origin)
            engine.refresh(now: origin.addingTimeInterval(3_000))
            _ = engine.continueFocus(now: origin.addingTimeInterval(3_000))
        case .hardStopReached:
            _ = engine.startFocus(settings: makeSettings(), now: origin)
            engine.refresh(now: origin.addingTimeInterval(5_400))
        default: break
        }
        try check(engine.snapshot.state == expectedState, "setup \(expectedState)")
        try check(engine.startBreak(settings: makeSettings(), now: origin.addingTimeInterval(10)), "early break from \(expectedState)")
        try check(engine.snapshot.state == .onBreak && engine.snapshot.breakEndAt != nil, "early break record \(expectedState)")
        try check(engine.snapshot.sessionStart == nil && engine.snapshot.hardStopAt == nil, "break clears focus deadlines")
        try check(!engine.startBreak(settings: makeSettings(), now: origin.addingTimeInterval(11)), "no duplicate break \(expectedState)")
    }
}

func testValidationAndInvalidTransitions() throws {
    try check(makeSettings(10, 10).validationError != nil, "strict hard-stop validation")
    try check(makeSettings(0, 20).validationError != nil, "checkpoint range")
    try check(makeSettings(10, 241).validationError != nil, "hard-stop range")
    try check(makeSettings(10, 20, 0).validationError != nil, "break range")
    var engine = SessionEngine(now: origin)
    try check(!engine.startFocus(settings: makeSettings(10, 10), now: origin), "invalid settings rejected")
    try check(!engine.continueFocus(now: origin), "continue only at checkpoint")
    _ = engine.startFocus(settings: makeSettings(), now: origin)
    try check(!engine.startFocus(settings: makeSettings(), now: origin), "cannot start duplicate focus")
    engine.cancel()
    try check(engine.snapshot == SessionSnapshot(), "cancel resets snapshot")
    let reversed = SessionSnapshot(state: .focusBeforeCheckpoint, id: UUID(), sessionStart: origin, checkpointAt: origin.addingTimeInterval(30), hardStopAt: origin.addingTimeInterval(20))
    try check(SessionEngine(snapshot: reversed, now: origin).snapshot.state == .idle, "reversed persisted deadlines rejected")
    let missing = SessionSnapshot(state: .focusAfterCheckpoint, id: UUID(), sessionStart: origin)
    try check(SessionEngine(snapshot: missing, now: origin).snapshot.state == .idle, "missing persisted deadlines rejected")
    let futureSchema = SessionSnapshot(state: .onBreak, id: UUID(), breakStart: origin, breakEndAt: origin.addingTimeInterval(10), schemaVersion: 99)
    try check(SessionEngine(snapshot: futureSchema, now: origin).snapshot.state == .idle, "unknown persistence schema rejected")
    let invalidBreak = SessionSnapshot(state: .onBreak, id: UUID(), breakStart: origin, breakEndAt: origin)
    try check(SessionEngine(snapshot: invalidBreak, now: origin).snapshot.state == .idle, "zero-length persisted break rejected")
}

func testPersistenceAndSettings() throws {
    let defaults = temporaryDefaults()
    let store = LocalStore(defaults: defaults)
    let configured = TimerSettings(checkpointMinutes: 20, hardStopMinutes: 40, breakMinutes: 8)
    store.saveSettings(configured)
    try check(store.loadSettings() == configured, "custom durations persist")
    for legacyTheme in ["system", "solarizedLight", "solarizedDark"] {
        let legacy = try JSONSerialization.data(withJSONObject: ["checkpointMinutes": 20, "hardStopMinutes": 40, "breakMinutes": 8, "theme": legacyTheme])
        defaults.set(legacy, forKey: "focusIsland.settings.v1")
        try check(store.loadSettings() == configured, "retired \(legacyTheme) preference preserves custom durations")
    }
    store.saveSettings(store.loadSettings())
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store.loadSettings())) as? [String: Any]
    try check(encoded?["theme"] == nil, "new settings omit retired theme field")
    defaults.set(Data("bad".utf8), forKey: "focusIsland.session.v1")
    try check(store.loadSession(now: origin).state == .idle, "corrupt session falls back to idle")
    store.saveSettings(makeSettings(10, 10))
    try check(store.loadSettings() == configured, "invalid settings never replace stored valid settings")
    var engine = SessionEngine(now: origin)
    try check(engine.startFocus(settings: makeSettings(2, 4, 3), now: origin), "custom durations start")
    try check(engine.snapshot.checkpointAt == origin.addingTimeInterval(120), "custom checkpoint deadline")
    try check(engine.snapshot.hardStopAt == origin.addingTimeInterval(240), "custom hard-stop deadline")
    let storedDeadline = engine.snapshot.hardStopAt
    store.saveSession(engine.snapshot)
    try check(store.loadSession(now: origin).hardStopAt == storedDeadline, "active session deadline remains immutable")
    try check(store.loadSession(now: origin).state == .focusBeforeCheckpoint, "active focus rehydrates")
    try check(store.loadSession(now: origin.addingTimeInterval(120)).state == .checkpointReached, "stored focus reaches checkpoint")
    try check(store.loadSession(now: origin.addingTimeInterval(240)).state == .hardStopReached, "stored focus reaches hard stop")

    var breakEngine = SessionEngine(now: origin)
    try check(breakEngine.startBreak(settings: makeSettings(2, 4, 3), now: origin), "standalone break starts")
    store.saveSession(breakEngine.snapshot)
    try check(store.loadSession(now: origin.addingTimeInterval(180)).state == .idle, "expired persisted break returns idle")
}

func testNotificationPlans() throws {
    var engine = SessionEngine(now: origin)
    _ = engine.startFocus(settings: makeSettings(), now: origin)
    let initial = notificationPlan(snapshot: engine.snapshot, now: origin)
    try check(initial.count == 2 && initial.allSatisfy { $0.date > origin }, "initial notices are future only")
    let ids = Set(initial.map(\.id))
    let sessionID = engine.snapshot.id?.uuidString
    try check(sessionID != nil && ids.count == 2 && ids.allSatisfy { $0.contains(sessionID ?? "") }, "stable UUID notice IDs")
    engine.refresh(now: origin.addingTimeInterval(3_000))
    let checkpoint = notificationPlan(snapshot: engine.snapshot, now: origin.addingTimeInterval(3_000))
    try check(checkpoint.count == 1 && checkpoint[0].id.hasSuffix("hard-stop"), "checkpoint removes obsolete notice")
    _ = engine.startBreak(settings: makeSettings(), now: origin.addingTimeInterval(3_000))
    let breakNotices = notificationPlan(snapshot: engine.snapshot, now: origin.addingTimeInterval(3_000))
    try check(breakNotices.count == 1 && breakNotices[0].id.hasSuffix("break-complete"), "break removes focus notices")
    engine.cancel()
    try check(notificationPlan(snapshot: engine.snapshot, now: origin).isEmpty, "cancel produces no notice plan")
}

func testIslandGeometry() throws {
    let notchedDisplay = rect(0, 0, 1_710, 1_107)
    let menuVisible = rect(0, 0, 1_710, 1_073)
    let rectangularDisplay = rect(0, 0, 1_920, 1_080)
    let rectangularVisible = rect(0, 0, 1_920, 1_055)
    let rectangular = IslandGeometry.frame(display: rectangularDisplay, visible: rectangularVisible, safeAreaTop: 0, size: CGSize(width: 224, height: 19))
    try check(sameRect(rectangular, rect(848, 1_058, 224, 19)), "external compact pill occupies the actual menu bar")
    try check(rectangular.minY >= rectangularVisible.maxY && rectangular.maxY <= rectangularDisplay.maxY, "external compact pill never covers app content")
    let expanded = IslandGeometry.frame(display: rectangularDisplay, visible: rectangularVisible, safeAreaTop: 0, size: CGSize(width: 400, height: 137))
    try check(expanded.maxY == rectangular.maxY, "external hover expansion keeps the menu-bar anchor")
    let autoHidden = IslandGeometry.frame(display: rectangularDisplay, visible: rectangularDisplay, safeAreaTop: 0, size: CGSize(width: 224, height: 19), menuBarHeight: 25)
    try check(autoHidden == rectangular, "menu auto-hide does not move the cached anchor")
    let secondaryDisplay = rect(-1_440, 0, 1_440, 900)
    let secondary = IslandGeometry.frame(display: secondaryDisplay, visible: secondaryDisplay, safeAreaTop: 0, size: CGSize(width: 224, height: 18))
    try check(sameRect(secondary, rect(-832, 879, 224, 18)), "negative-coordinate secondary menu-bar placement")
    let resizedDisplay = rect(0, 0, 2_560, 1_440)
    let resizedVisible = rect(0, 0, 2_560, 1_416)
    let resized = IslandGeometry.frame(display: resizedDisplay, visible: resizedVisible, safeAreaTop: 0, size: CGSize(width: 400, height: 144))
    try check(sameRect(resized, rect(1_080, 1_293, 400, 144)), "resized display updates menu-bar center")

    let band = rect(0, 1055, 1920, 25)
    let menu = rect(0, 0, 1920, 25)
    try check(IslandGeometry.menuBarFrame(display: rectangularDisplay, primaryDisplayTop: 1080, menuWindowBounds: [menu]) == band, "visible native menu-bar bounds convert to AppKit")
    try check(IslandGeometry.menuBarFrame(display: rectangularDisplay, primaryDisplayTop: 1080, menuWindowBounds: []) == nil, "hidden fullscreen menu bar is unavailable")
    try check(IslandGeometry.menuBarFrame(display: rectangularDisplay, primaryDisplayTop: 1080, menuWindowBounds: [rect(0, -25, 1920, 25)]) == nil, "sliding hidden menu bar is not shown prematurely")
    try check(IslandGeometry.menuBarFrame(display: rectangularDisplay, primaryDisplayTop: 1080, menuWindowBounds: [rect(-1000, 0, 1920, 25)]) == nil, "Space-transition menu bar is not mistaken for the selected display")
    let above = rect(-1440, 1080, 1440, 900)
    try check(IslandGeometry.menuBarFrame(display: above, primaryDisplayTop: 1080, menuWindowBounds: [rect(-1440, -900, 1440, 24), menu]) == rect(-1440, 1956, 1440, 24), "menu bar on vertically offset display is matched independently")
    try check(IslandGeometry.menuBarFrame(display: secondaryDisplay, primaryDisplayTop: 1080, menuWindowBounds: [menu]) == nil, "another display's visible menu bar cannot expose a hidden pill")
    try check([22.0, 24, 25, 30, 34, 40].allSatisfy { IslandGeometry.menuBarHeaderHeight($0) <= $0 }, "compact header fits common menu-bar sizes")
    let attached = IslandGeometry.frame(display: notchedDisplay, visible: menuVisible, safeAreaTop: 33, size: CGSize(width: 241, height: 33), attachedToNotch: true)
    try check(sameRect(attached, rect(734.5, 1_074, 241, 33)), "compact shell occupies only the notch band")
    let attachedExpanded = IslandGeometry.frame(display: notchedDisplay, visible: menuVisible, safeAreaTop: 33, size: CGSize(width: 340, height: 222), attachedToNotch: true)
    try check(sameRect(attachedExpanded, rect(685, 885, 340, 222)), "attached expansion preserves screen-top anchor")
    let active = IslandGeometry.frame(display: notchedDisplay, visible: menuVisible, safeAreaTop: 33, size: CGSize(width: 285, height: 33), attachedToNotch: true, centerOffset: -22)
    try check(active.minX + 72 == notchedDisplay.midX - 185 / 2, "asymmetric wings reserve the actual camera position")
    try check(active.maxY == notchedDisplay.maxY && active.minY == notchedDisplay.maxY - 33, "timer stays within menu bar height")
    let hiddenMenu = IslandGeometry.frame(display: notchedDisplay, visible: notchedDisplay, safeAreaTop: 33, size: CGSize(width: 285, height: 33), attachedToNotch: true, centerOffset: -22)
    try check(sameRect(active, hiddenMenu), "notch placement does not jump when menu bar hides")
    let noNotchFallback = IslandGeometry.frame(display: rectangularDisplay, visible: rectangularVisible, safeAreaTop: 0, size: CGSize(width: 224, height: 19), attachedToNotch: true)
    try check(sameRect(noNotchFallback, rectangular), "no-notch fallback occupies the menu bar")
    let canvas = rect(641, 948, 428, 159)
    func hit(_ x: CGFloat, _ y: CGFloat, _ expanded: Bool, _ progress: CGFloat? = nil, _ attached: Bool = true) -> Bool {
        IslandGeometry.containsPointer(CGPoint(x: x, y: y), canvas: canvas,
            headerWidth: 241, headerHeight: 33, headerOffset: 0, expandedHeight: 133, expanded: expanded,
            attached: attached, expansion: progress)
    }
    try check(hit(855, 1090, false), "compact notch is interactive")
    try check(!hit(750, 1000, false), "invisible expanded canvas cannot trigger hover")
    try check(hit(750, 1000, true), "expanded controls remain interactive in stable coordinates")
    try check(hit(991, 1090, true), "expanded island intentionally overlays the menu band")
    try check(!hit(850, 960, true), "canvas below visible body passes through")
    try check(!hit(656, 975, true), "transparent rounded body corner is outside hover")
    try check(IslandGeometry.containsPointer(CGPoint(x: 720, y: 1090), canvas: canvas,
        headerWidth: 285, headerHeight: 33, headerOffset: -22, expandedHeight: 151, expanded: false), "active left timer wing is interactive")
    try check(!hit(735, 1075, false), "rounded compact corner passes input through")
    try check(!hit(735, 1106, false, nil, false), "rectangular-screen rounded corner passes input through")
    try check(!hit(855, 1000, true, 0.1), "opening does not capture invisible body")
    try check(hit(855, 1060, false, 0.5), "visible closing body permits re-entry")
    try check(hit(700, 1090, true), "expanded top spans the full popup width")
    try check(!hit(991, 1090, false), "collapsed shell leaves status item clickable")
    try check(hit(991, 1090, true, 0.8), "menu-band hit region grows with the visible shell")
    try check(hit(650, 1106, true), "expanded top flare extends outward at screen edge")
    try check(!hit(650, 1092, true), "expanded flare curves inward to the vertical side")
    try check(hit(1060, 1106, true), "right top flare mirrors the left")
    try check(!hit(1060, 1092, true), "right flare has no invisible rectangular hit region")
    try check(hit(733, 1106, false), "collapsed shell has a smaller outward flare")
    try check(!hit(733, 1098, false), "collapsed flare ends above the side")
}

let checks: [(String, () throws -> Void)] = [
    ("focus lifecycle", testFocusLifecycle),
    ("inactive rehydration and clock monotonicity", testInactiveRehydrationAndClockMonotonicity),
    ("early break transitions", testEarlyBreakTransitions),
    ("validation and invalid transitions", testValidationAndInvalidTransitions),
    ("persistence and settings", testPersistenceAndSettings),
    ("notification plans", testNotificationPlans),
    ("island geometry", testIslandGeometry)
]

do {
    for (name, body) in checks {
        try body()
        print("PASS: \(name)")
    }
    print("PASS: \(checks.count) FocusCore checks, \(assertionCount) assertions")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
