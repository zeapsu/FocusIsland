# QA environment

`scripts/ui-tool.swift` is a small native helper for QA. Build it from the project root:

```zsh
mkdir -p .build
swiftc scripts/ui-tool.swift -framework AppKit -framework ApplicationServices -framework CoreGraphics -o .build/ui-tool
```

It uses macOS Accessibility APIs to inspect and activate controls, and Core Graphics events for pointer movement and clicks. It never changes privacy settings. Grant the terminal or the built helper Accessibility access before running the commands that inspect or operate controls.

```zsh
.build/ui-tool apps
.build/ui-tool attributes <app-bundle-id>
.build/ui-tool windows <app-bundle-id>
.build/ui-tool onscreen-windows <app-bundle-id>
.build/ui-tool enable-enhanced <app-bundle-id>
.build/ui-tool at 855 55
.build/ui-tool qa-click 2 80 125
.build/ui-tool qa-text 3 "5"
.build/ui-tool qa-key 3 return
.build/ui-tool tree <app-bundle-id> 10
.build/ui-tool inspect <app-bundle-id> "Start Focus"
.build/ui-tool press <app-bundle-id> "Start Focus"
.build/ui-tool set-value <app-bundle-id> "Checkpoint" "1"
.build/ui-tool pointer
.build/ui-tool move 720 24
.build/ui-tool click 720 24
```

The query in `inspect`, `press`, and `set-value` matches an accessibility identifier, title, or description. Give FocusIsland's controls stable identifiers and labels, for example `startFocus`, `continueFocus`, `startBreak`, `endSession`, `checkpointDuration`, `hardStopDuration`, and `breakDuration`.

`enable-enhanced` asks the target app for its enhanced Accessibility hierarchy. It does not change macOS privacy settings. It only works if the app exposes `AXEnhancedUserInterface` as settable.

`at` finds the accessible element under a global Quartz coordinate. It helps inspect a menu-bar popover when the popover is not returned by the app's `AXWindows` attribute.

In a FocusIsland DEBUG build launched with `--qa-artifacts`, the `qa-*` commands submit one input event to the opt-in app-owned QA driver. The driver hit-tests the rendered AppKit view and dispatches the matching click, text, or key event. This is only for environments where macOS blocks external CGEvent clicks and does not replace native Accessibility testing.

Capture the display without a mouse cursor:

```zsh
caffeinate -u -t 3
screencapture -x /tmp/focus-island-qa.png
sips -g pixelWidth -g pixelHeight /tmp/focus-island-qa.png
```

If `screencapture` exits nonzero and produces a black image, first wake the display with the `caffeinate` command above and retry. That happened in the prepared environment. Finder's accessibility tree remained available, so the display session was awake. That initial failure later resolved without privacy-setting changes. Final QA successfully captured the desktop and inspected the app through Accessibility. Do not infer a persistent permission failure from one black capture. Do not change privacy permissions as part of app QA.

Screen capture and CGEvent posting have separate macOS privacy gates. Test each on the target machine before relying on it for QA evidence.

For the QA input driver, use the native `number` from `qa/live/live.json`, not the enumeration `index`. After submission, wait two fresh snapshots before asserting the result. For text editing, focus each field, edit the active field editor, and commit before Save. Setting an unfocused AX field value alone may update its display without committing its SwiftUI binding.

## Placement and full-screen QA

For a previously decided notification permission, `python3 scripts/qa-notifications.py` checks the Settings action with a real mouse click. It first opens a different System Settings pane, then verifies the app button navigates to Focus Island's own Notifications page. It returns to the app and checks the status/action remain usable. This check never toggles notification permission or changes a timer. Evidence is saved under `qa/notifications/`.

`scripts/qa-placement.py` runs against a separate native test window, so full-screen transitions do not change the user's documents. Build that disposable fixture:

```sh
mkdir -p .build/FullscreenFixture.app/Contents/MacOS
swiftc scripts/fullscreen-fixture.swift -o .build/FullscreenFixture.app/Contents/MacOS/FullscreenFixture
python3 - <<'PY'
import pathlib, plistlib
p = pathlib.Path('.build/FullscreenFixture.app/Contents/Info.plist')
p.write_bytes(plistlib.dumps({
    'CFBundleExecutable': 'FullscreenFixture',
    'CFBundleIdentifier': 'local.focusisland.fullscreen-qa',
    'CFBundleName': 'Fullscreen Fixture',
    'CFBundlePackageType': 'APPL',
    'NSPrincipalClass': 'NSApplication'
}))
PY
open .build/FullscreenFixture.app
```

Quit the production app first, then launch the debug bundle with isolated timer preferences and diagnostic output:

```sh
./scripts/build-app.sh debug
open "dist/Focus Island.app" --args --qa-speed --qa-artifacts
```

The speed flag uses the `local.focusisland.qa` preference domain and runs timers at 20× speed; updater checks are disabled. Set checkpoint/hard stop/break to 5/10/3 in Settings for 15/30/9-second test deadlines. Both flags are compiled out of release builds. After QA, quit this copy and reopen the installed production app to reconstruct its original absolute deadlines.

Run `python3 scripts/qa-placement.py` after saving those QA durations. This script's pointer coordinates and compact-height assertion target the tested 1710×1107 display with a 33-point notch band. Adapt those values when running it on another display. It checks native full-screen state through Accessibility, allows the temporary absence of the window during Space animation, and asserts the island's actual visibility. `python3 scripts/qa-lifecycle.py` then exercises the regular lifecycle. Neither script changes privacy permissions.

`python3 scripts/qa-hover.py` works with either debug or release builds on the same display. Start idle with the fixture in its normal window. It checks quick pointer flybys, movement through the expanded controls, re-entry during collapse, actual Start/Cancel mouse clicks, transparent canvas boundaries, outward motion of the header elements, and real clicks on the island menu shortcut. The native canvas remains 428×159 points throughout; the visible surface morphs inside it. Native screenshots and test output are saved under `qa/hover/`.

`python3 scripts/qa-visibility.py` checks visibility on normal desktop, maximized desktop, and native full screen, plus full-screen hover, popup dismissal, and repeated return to the desktop. Passive hover must keep the full-screen fixture in front. The fixture's Normal Window and Maximize on Desktop buttons distinguish maximization from its Toggle Full Screen button. This check works against debug or release builds without changing the timer or preferences. It uses `onscreen-windows`, backed by the WindowServer's on-screen list: AppKit's `isVisible` alone includes windows on other Spaces and is insufficient evidence. DEBUG snapshots also include an `onScreen` field. Current results are under `qa/fullscreen-available/`; the older `qa/visibility/` records describe the previously requested full-screen hiding policy.

The current `qa-placement.py` also exercises a visible hard-stop prompt and break completion inside full screen, followed by desktop return. It requires the isolated DEBUG session so it does not affect a real focus session.

`python3 scripts/qa-popup.py` uses real mouse clicks to verify dismissal in another app, on popup background, on the notch, in Settings, and by repeated status-icon toggles. Settings opens without losing its action. The optional `--actions` additionally starts and cancels a timer; use it only with the isolated QA app idle. Omit it when preserving a production session.

The native scripts temporarily activate the disposable fixture. Switching to another Space during a run changes the expected visibility; such interrupted runs must be repeated and are not passing evidence. The full-screen checks verify a real native full-screen window separately from a maximized desktop window.
