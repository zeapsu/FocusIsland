import Foundation
import CoreGraphics
import XCTest
@testable import FocusCore

final class FocusCoreTests: XCTestCase {
    private let origin = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func settings(
        checkpoint: Int = 50,
        hardStop: Int = 90,
        breakMinutes: Int = 10
    ) -> TimerSettings {
        TimerSettings(checkpointMinutes: checkpoint, hardStopMinutes: hardStop, breakMinutes: breakMinutes)
    }

    func testNewSessionStartsBeforeCheckpointWithAbsoluteDeadlines() {
        var engine = SessionEngine(now: origin)
        XCTAssertTrue(engine.startFocus(settings: settings(), now: origin))
        XCTAssertEqual(engine.snapshot.state, .focusBeforeCheckpoint)
        XCTAssertEqual(engine.snapshot.sessionStart, origin)
        XCTAssertEqual(engine.snapshot.checkpointAt, origin.addingTimeInterval(50 * 60))
        XCTAssertEqual(engine.snapshot.hardStopAt, origin.addingTimeInterval(90 * 60))
    }

    func testCheckpointDoesNotEndFocusAndContinueTransitions() {
        var engine = SessionEngine(now: origin)
        _ = engine.startFocus(settings: settings(), now: origin)
        engine.refresh(now: origin.addingTimeInterval(50 * 60))
        XCTAssertEqual(engine.snapshot.state, .checkpointReached)
        XCTAssertTrue(engine.continueFocus(now: origin.addingTimeInterval(50 * 60 + 1)))
        XCTAssertEqual(engine.snapshot.state, .focusAfterCheckpoint)
    }

    func testHardStopWinsWhenCheckpointAndHardStopAreBothPast() {
        var engine = SessionEngine(now: origin)
        _ = engine.startFocus(settings: settings(), now: origin)
        engine.refresh(now: origin.addingTimeInterval(90 * 60))
        XCTAssertEqual(engine.snapshot.state, .hardStopReached)
        XCTAssertFalse(engine.continueFocus(now: origin.addingTimeInterval(90 * 60)))
    }

    func testBreakStartsAndCompletionReturnsIdle() {
        var engine = SessionEngine(now: origin)
        _ = engine.startFocus(settings: settings(breakMinutes: 3), now: origin)
        XCTAssertTrue(engine.startBreak(settings: settings(breakMinutes: 3), now: origin.addingTimeInterval(30)))
        XCTAssertEqual(engine.snapshot.state, .onBreak)
        XCTAssertEqual(engine.snapshot.breakEndAt, origin.addingTimeInterval(30 + 3 * 60))
        XCTAssertFalse(engine.refresh(now: origin.addingTimeInterval(30 + 3 * 60 - 1)))
        XCTAssertTrue(engine.refresh(now: origin.addingTimeInterval(30 + 3 * 60)))
        XCTAssertEqual(engine.snapshot.state, .idle)
        XCTAssertFalse(engine.refresh(now: origin.addingTimeInterval(30 + 3 * 60 + 1)))
    }

    func testStandaloneBreakStartsFromIdleAndClearsFocusDeadlines() {
        var engine = SessionEngine(now: origin)
        XCTAssertTrue(engine.startBreak(settings: settings(), now: origin))
        XCTAssertEqual(engine.snapshot.state, .onBreak)
        XCTAssertNotNil(engine.snapshot.id)
        XCTAssertNil(engine.snapshot.sessionStart)
        XCTAssertNil(engine.snapshot.checkpointAt)
        XCTAssertNil(engine.snapshot.hardStopAt)
    }

    func testCancelAlwaysResets() {
        var engine = SessionEngine(now: origin)
        _ = engine.startFocus(settings: settings(), now: origin)
        engine.cancel()
        XCTAssertEqual(engine.snapshot, SessionSnapshot())
    }

    func testCustomDurationsAndTimeScaleAreAppliedAtStartOnly() {
        var engine = SessionEngine(now: origin)
        let custom = settings(checkpoint: 2, hardStop: 4, breakMinutes: 3)
        XCTAssertTrue(engine.startFocus(settings: custom, now: origin, timeScale: 0.5))
        XCTAssertEqual(engine.snapshot.checkpointAt, origin.addingTimeInterval(60))
        XCTAssertEqual(engine.snapshot.hardStopAt, origin.addingTimeInterval(120))
        let originalDeadline = engine.snapshot.hardStopAt
        _ = settings(checkpoint: 1, hardStop: 2, breakMinutes: 1)
        XCTAssertEqual(engine.snapshot.hardStopAt, originalDeadline)
    }

    func testInvalidDurationRelationshipsAreRejected() {
        XCTAssertNotNil(settings(checkpoint: 10, hardStop: 10).validationError)
        XCTAssertNotNil(settings(checkpoint: 0, hardStop: 20).validationError)
        XCTAssertNotNil(settings(checkpoint: 10, hardStop: 241).validationError)
        XCTAssertNotNil(settings(checkpoint: 10, hardStop: 20, breakMinutes: 0).validationError)
        var engine = SessionEngine(now: origin)
        XCTAssertFalse(engine.startFocus(settings: settings(checkpoint: 10, hardStop: 10), now: origin))
        XCTAssertEqual(engine.snapshot.state, .idle)
    }

    func testPersistedActiveSessionReconstructsAtCheckpoint() {
        let defaults = temporaryDefaults()
        let store = LocalStore(defaults: defaults)
        var engine = SessionEngine(now: origin)
        _ = engine.startFocus(settings: settings(), now: origin)
        store.saveSession(engine.snapshot)
        XCTAssertEqual(store.loadSession(now: origin.addingTimeInterval(50 * 60)).state, .checkpointReached)
    }

    func testPersistedActiveSessionReconstructsAtHardStop() {
        let defaults = temporaryDefaults()
        let store = LocalStore(defaults: defaults)
        var engine = SessionEngine(now: origin)
        _ = engine.startFocus(settings: settings(), now: origin)
        store.saveSession(engine.snapshot)
        XCTAssertEqual(store.loadSession(now: origin.addingTimeInterval(90 * 60)).state, .hardStopReached)
    }

    func testBackwardClockDoesNotRewindState() {
        var engine = SessionEngine(now: origin)
        _ = engine.startFocus(settings: settings(), now: origin)
        engine.refresh(now: origin.addingTimeInterval(50 * 60))
        engine.refresh(now: origin.addingTimeInterval(1))
        XCTAssertEqual(engine.snapshot.state, .checkpointReached)
        _ = engine.continueFocus(now: origin.addingTimeInterval(1))
        XCTAssertEqual(engine.snapshot.state, .focusAfterCheckpoint)
    }

    func testExactBoundariesAndInvalidTransitions() {
        var engine = SessionEngine(now: origin)
        XCTAssertFalse(engine.continueFocus(now: origin))
        XCTAssertTrue(engine.startBreak(settings: settings(), now: origin))
        XCTAssertEqual(engine.snapshot.state, .onBreak)
        engine.cancel()
        _ = engine.startFocus(settings: settings(), now: origin)
        XCTAssertFalse(engine.continueFocus(now: origin.addingTimeInterval(49 * 60 + 59)))
        engine.refresh(now: origin.addingTimeInterval(50 * 60))
        XCTAssertEqual(engine.snapshot.state, .checkpointReached)
        XCTAssertTrue(engine.startBreak(settings: settings(), now: origin.addingTimeInterval(50 * 60)))
        XCTAssertFalse(engine.startFocus(settings: settings(), now: origin))
    }

    func testCorruptedPersistenceAndInvalidSnapshotsFallBackToIdle() {
        let defaults = temporaryDefaults()
        defaults.set(Data("not json".utf8), forKey: "focusIsland.session.v1")
        XCTAssertEqual(LocalStore(defaults: defaults).loadSession(now: origin).state, .idle)
        let malformed = SessionSnapshot(state: .focusBeforeCheckpoint, id: UUID(), sessionStart: origin)
        XCTAssertEqual(SessionEngine(snapshot: malformed, now: origin).snapshot.state, .idle)
    }

    func testCustomTimerSettingsPersist() {
        let store = LocalStore(defaults: temporaryDefaults())
        let expected = TimerSettings(checkpointMinutes: 20, hardStopMinutes: 40, breakMinutes: 8)
        store.saveSettings(expected)
        XCTAssertEqual(store.loadSettings(), expected)
    }

    func testRetiredThemePreferencesPreserveDurationsAndAreNotWrittenBack() throws {
        let defaults = temporaryDefaults()
        let store = LocalStore(defaults: defaults)
        let expected = TimerSettings(checkpointMinutes: 20, hardStopMinutes: 40, breakMinutes: 8)
        for legacyTheme in ["system", "solarizedLight", "solarizedDark"] {
            let legacy = try JSONSerialization.data(withJSONObject: ["checkpointMinutes": 20, "hardStopMinutes": 40, "breakMinutes": 8, "theme": legacyTheme])
            defaults.set(legacy, forKey: "focusIsland.settings.v1")
            XCTAssertEqual(store.loadSettings(), expected, legacyTheme)
            store.saveSettings(store.loadSettings())
            let saved = try XCTUnwrap(defaults.data(forKey: "focusIsland.settings.v1"))
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
            XCTAssertNil(fields["theme"])
            XCTAssertEqual(store.loadSettings(), expected)
        }
    }

    func testNoticePlansContainOnlyFutureEventsForTheirCurrentState() {
        var engine = SessionEngine(now: origin)
        _ = engine.startFocus(settings: settings(), now: origin)
        let initial = notificationPlan(snapshot: engine.snapshot, now: origin)
        XCTAssertEqual(initial.map(\.id).count, 2)
        XCTAssertTrue(initial.allSatisfy { $0.date > origin })
        XCTAssertTrue(initial.allSatisfy { $0.id.contains(engine.snapshot.id!.uuidString) })

        engine.refresh(now: origin.addingTimeInterval(50 * 60))
        let atCheckpoint = notificationPlan(snapshot: engine.snapshot, now: origin.addingTimeInterval(50 * 60))
        XCTAssertEqual(atCheckpoint.count, 1)
        XCTAssertEqual(atCheckpoint.first?.title, "Time to get up and move.")

        _ = engine.startBreak(settings: settings(), now: origin.addingTimeInterval(50 * 60))
        XCTAssertEqual(notificationPlan(snapshot: engine.snapshot, now: origin.addingTimeInterval(50 * 60)).first?.title, "Break complete.")
    }

    func testExternalIslandFitsInsideMenuBarAndKeepsAnchor() {
        let display = rect(0, 0, 3440, 1440)
        let visible = rect(0, 0, 3440, 1410)
        let compact = IslandGeometry.frame(display: display, visible: visible, safeAreaTop: 0, size: CGSize(width: 224, height: 24))
        XCTAssertEqual(compact, rect(1608, 1413, 224, 24))
        XCTAssertGreaterThanOrEqual(compact.minY, visible.maxY)
        XCTAssertLessThanOrEqual(compact.maxY, display.maxY)
        let expanded = IslandGeometry.frame(display: display, visible: visible, safeAreaTop: 0, size: CGSize(width: 400, height: 142))
        XCTAssertEqual(compact.maxY, expanded.maxY)
        let hidden = IslandGeometry.frame(display: display, visible: display, safeAreaTop: 0, size: CGSize(width: 224, height: 24), menuBarHeight: 30)
        XCTAssertEqual(hidden, compact)
    }

    func testMenuBarWindowMatchingHandlesHiddenAndOffsetDisplays() {
        let display = rect(0, 0, 3440, 1440)
        let menu = rect(0, 0, 3440, 30)
        XCTAssertEqual(IslandGeometry.menuBarFrame(display: display, primaryDisplayTop: 1440, menuWindowBounds: [menu]), rect(0, 1410, 3440, 30))
        for bounds in [[], [rect(0, -30, 3440, 30)], [rect(-2000, 0, 3440, 30)], [rect(0, 0, 3440, 400)]] {
            XCTAssertNil(IslandGeometry.menuBarFrame(display: display, primaryDisplayTop: 1440, menuWindowBounds: bounds))
        }
        let above = rect(-1440, 1440, 1440, 900)
        XCTAssertEqual(IslandGeometry.menuBarFrame(display: above, primaryDisplayTop: 1440, menuWindowBounds: [menu, rect(-1440, -900, 1440, 24)]), rect(-1440, 2316, 1440, 24))
        XCTAssertNil(IslandGeometry.menuBarFrame(display: above, primaryDisplayTop: 1440, menuWindowBounds: [menu]))
    }

    func testNotchBandKeepsCameraCutoutEmpty() {
        let display = rect(0, 0, 1710, 1107)
        let compact = IslandGeometry.frame(display: display, visible: rect(0, 0, 1710, 1073), safeAreaTop: 33, size: CGSize(width: 285, height: 33), attachedToNotch: true, centerOffset: -22)
        XCTAssertEqual(compact.maxY, display.maxY)
        XCTAssertEqual(compact.minY, display.maxY - 33)
        XCTAssertEqual(compact.minX + 72, display.midX - 185 / 2)
        let expanded = IslandGeometry.frame(display: display, visible: display, safeAreaTop: 33, size: CGSize(width: 360, height: 211), attachedToNotch: true)
        XCTAssertEqual(expanded.maxY, compact.maxY)
        XCTAssertEqual(expanded.midX, display.midX)
    }

    func testHoverRegionsFollowTheSurfaceAndExcludeInvisibleCanvas() {
        let canvas = rect(641, 948, 428, 159)
        func hit(_ point: CGPoint, expanded: Bool) -> Bool {
            IslandGeometry.containsPointer(point, canvas: canvas, headerWidth: 241,
                headerHeight: 33, headerOffset: 0, expandedHeight: 133, expanded: expanded)
        }
        XCTAssertTrue(hit(CGPoint(x: 855, y: 1090), expanded: false))
        XCTAssertFalse(hit(CGPoint(x: 750, y: 1000), expanded: false))
        XCTAssertTrue(hit(CGPoint(x: 750, y: 1000), expanded: true))
        XCTAssertTrue(hit(CGPoint(x: 991, y: 1090), expanded: true))
        XCTAssertFalse(hit(CGPoint(x: 850, y: 960), expanded: true))
        XCTAssertFalse(hit(CGPoint(x: 735, y: 1075), expanded: false))
        XCTAssertTrue(hit(CGPoint(x: 700, y: 1090), expanded: true))
        XCTAssertTrue(IslandGeometry.containsPointer(CGPoint(x: 855, y: 1060), canvas: canvas,
            headerWidth: 241, headerHeight: 33, headerOffset: 0, expandedHeight: 133,
            expanded: false, expansion: 0.5))
    }

    private func temporaryDefaults() -> UserDefaults {
        let suite = "FocusCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }
}
