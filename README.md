# Focus Island

A small native macOS focus timer with one floating island and a menu-bar control. Defaults are a gentle checkpoint at 50 minutes, a hard stop at 90 minutes, and a 10-minute break. The checkpoint leaves focus running. At the hard stop, the island stays expanded until you start a break or end the session.

## Build and run

Requires macOS 14 or newer and Swift 6 or newer. Apple Command Line Tools are sufficient for the app and portable tests; no dependencies or developer signing account are needed.

```sh
cd /Users/andrypaez/projects/FocusIsland
./scripts/build-app.sh release
open "dist/Focus Island.app"
```

Quit a running copy before rebuilding. The script creates an ad-hoc signed app bundle. It is suitable for local use. Distribution to other Macs would require normal Developer ID signing and notarization. Open the bundle, rather than running the bare executable, so native notifications have a bundle identity.

The app has no Dock icon. Open its menu-bar icon to start focus, start a break, open Settings, or quit. Hover the island to expand it. Quitting preserves the active session. End or cancel a timer to clear it.

## Architecture

- `FocusCore` contains the explicit state machine, timestamp validation, local JSON persistence, duration validation, and a pure notification planner.
- `SessionController` is the sole app-side session owner. The island, menu popover, and Settings observe it. A display refresh reads the wall clock; it never decrements a counter. Wake events and relaunch reconcile the same deadlines.
- `IslandWindowController` manages one nonactivating AppKit panel. Its transparent canvas stays fixed while a shared animation value drives both the visible shape and pointer hit testing. Hover has a 100 ms entry delay and 240 ms exit grace period; Reduce Motion skips the morph.
- `NotificationManager` serializes native notification updates. Settings requests permission when no choice has been recorded; otherwise its button opens the app's notification page in System Settings. Returning to the app refreshes permission and updates the active session's reminder schedule. The timer remains usable without permission.
- SwiftUI views use semantic system colors or the canonical Solarized palette. Explicit themes also set AppKit appearance.

The state path is `idle → focusBeforeCheckpoint → checkpointReached → focusAfterCheckpoint → hardStopReached`. A delayed refresh can skip directly to hard stop. Starting a break enters `onBreak`; completion returns to idle. Ignoring a checkpoint never stops the timer and never bypasses the hard stop.

Durations are whole minutes. Checkpoint accepts 1–239, hard stop 2–240 and greater than checkpoint, and break 1–120. Saving preferences does not move an active deadline. Focus settings apply when focus starts; break settings apply when a break starts.

## Tests and fast UI QA

```sh
./scripts/test-core.sh
swift run -c release FocusCoreChecks
# Full Xcode also supports the XCTest suite:
swift test

./scripts/build-app.sh debug
open "dist/Focus Island.app" --args --qa-speed --qa-artifacts "$PWD/qa/live"
```

The debug-only `--qa-speed` flag uses a separate preference domain and runs time at 20× speed. Set 1/2/1 minutes in Settings for checkpoint/hard stop/break at 3/6/3 seconds. Use 5/10/3 for 15/30/9 seconds when testing controls. Production validation is unchanged and release builds ignore QA flags. `--qa-artifacts` captures the running app's own views and window metadata, not the desktop. It is compiled out of release builds.

See [QA report](docs/qa-report.md) for executed scenarios and limits, and [QA helper](docs/qa-environment.md) for Accessibility and mouse automation commands.

## Window behavior and limits

The single island uses the cursor's display at launch and whenever the menu is opened. It reselects a display when screen geometry or the active Space changes. It stays on that display during normal pointer movement. On notched Macs, the compact shell occupies the menu-bar band itself: a countdown sits to the left of the camera and a state icon to the right. The camera cutout stays empty. Hover widens the entire shell across the menu bar, moving the timer and icon outward while controls appear below. The right-hand icon opens the same timer menu as the status item; the island folds away while that menu is open. Moving away restores access to neighboring menu-bar items. On rectangular displays, the themed pill sits four points below the menu bar.

The island stays available on desktop Spaces, over maximized windows, and in native full-screen apps. It keeps the same compact notch position and expands on hover without activating the app. The hard-stop prompt expands in full screen too. AppKit manages Space membership; the app does not infer full screen from another window's size, inspect other apps' windows, or require Accessibility or screen-recording permission. Native window behavior is tested on one notched display running macOS 26.5.1; multiple physical displays remain unverified.

The menu-bar icon keeps a fixed width. Its popover measures its content before opening and anchors directly below that icon, including after timer-state changes. Clicking inside the popup, elsewhere in the app, or in another app dismisses it. A clicked control performs its action before dismissal. Clicking the status icon again or pressing Escape also closes it. Visual references for the notch interaction were [MacNotch](https://macnotch.io/), [Notchy](https://notchy.dev/blog/make-macbook-notch-useful/), and the user’s supplied NotchNook screenshot. The outward top flares also follow the concave-corner pattern described in [NotchKit](https://github.com/duongductrong/NotchKit/blob/master/docs/architecture.md).

System controls the menu-bar glyph and notification banner appearance. In System mode, the island on a notched display stays black to blend into the hardware; its menu, Settings, and rectangular-display island follow macOS appearance. Explicit Solarized Light/Dark themes apply their canonical colors to every app surface. Notification delivery also depends on macOS Focus and notification preferences. Absolute wall-clock timestamps survive suspension and restarts; manually changing the system clock can change remaining time.

Pause, login launch, session history, multiple islands, custom sounds, accounts, sync, and distribution signing are intentionally omitted.
