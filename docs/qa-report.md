# Verification report

## Current appearance

Version 1.1.1 removes the theme selector and both Solarized palettes. The attached notch stays black, while the menu and Settings follow macOS appearance. Loading older settings ignores their retired theme field without resetting custom durations. Earlier theme-selection checks below describe historical builds, not current options.

- Debug and release builds and bundle signature checks passed. Portable core checks passed **111 assertions in 7 groups**, including migration of all three former theme values with custom durations.
- Native Settings, menu, compact notch, and expanded notch were captured and visually inspected in actual macOS light and dark appearance. The theme selector is absent, Settings and the menu change appearance, and the notch stays black. The original system appearance was restored.
- Installing and relaunching the local release preserved the active session ID, state, and all absolute timestamps, along with the saved timer durations. The retired theme field was removed from persisted settings.
- A separate read-only review found no material issue in the migration, appearance handling, or documentation. The README Settings screenshot was replaced with a capture of this build. Evidence is under `qa/system-appearance/`.

## GitHub releases and updates

The real GitHub release pipeline and native Sparkle update from build 1000 to 1002 passed, preserving the active session and preferences. CI passed 109 portable assertions and 18 XCTest tests. See the [release and updater verification](update-qa.md) for the executed steps, workflow links, and distribution limits.

## Current: notification permission action

The installed app reported notification permission denied but still offered Enable Notifications. An AX activation of that control left the same denied state and label. The implementation repeated `requestAuthorization` after a recorded decision, which [Apple documents as not prompting again](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications). The button now requests only an undecided permission; otherwise it opens Focus Island's page in System Settings. Returning to the app refreshes permission and updates the current reminder plan without changing timer deadlines.

- Debug and release builds passed. Core checks passed **109 assertions in 7 groups** in both configurations.
- The updated release was installed in `/Applications/Focus Island.app`; its signature validates and its executable matches the built release.
- `scripts/qa-notifications.py` passed with a real mouse click, after confirming the actual hit target. It starts System Settings on Appearance to avoid a false pass from an already-open notification page, then verifies that the app action opens Focus Island's notification page. Returning to the app leaves a usable status and action. The initial QA setup needed an actual title-bar click because opening an accessory window through AX did not bring it in front; that incomplete run is not passing evidence.
- The app initially reported denied permission and now reports Notifications enabled. QA did not toggle the system permission. First-time permission prompting and native notification banner delivery were not exercised in this correction.
- A separate review found no material issue in the permission routing, asynchronous scheduler, errors, or accessibility.

Evidence is under `qa/notifications/`. The original production session ID and all saved deadlines were verified unchanged after installation and QA. Earlier statements below about denied permission describe those earlier runs; current authorization is enabled.

## Availability in full-screen apps

The user requested that the island remain available in full-screen apps now that it occupies the notch band. The panel now uses `fullScreenAuxiliary` together with `canJoinAllSpaces`. The compact placement, hover morph, popup dismissal, and timer model are unchanged. The hard-stop prompt appears in full screen too. The hiding policy documented below is historical and no longer applies.

- Debug and release portable core checks passed **109 assertions in 7 groups**.
- The updated `scripts/qa-visibility.py` passed with the debug app: normal desktop and maximized desktop visibility, two native full-screen round trips, compact and expanded visibility, menu access, and click-away dismissal. Passive hover kept the full-screen fixture in front and stayed in its Space.
- `scripts/qa-placement.py` passed: popup anchoring, expanded controls in full screen, the visible hard-stop prompt, break completion in full screen, and desktop return. The prompt screenshot was visually inspected.
- Actual Start Focus and Cancel Focus mouse clicks on the island passed in full screen without leaving that Space. These actions used the isolated QA session.
- A separate read-only review found no material issues in Space membership, focus handling, input guards, timer prompts, or the native regression coverage.

The release build passed launch directly into native full screen, compact and expanded visibility, passive focus, the island's menu shortcut, popup click-away, and desktop return. Actual full-screen screenshots were captured and visually inspected. One initial launch check stopped before launching because the fixture was not on the active Space; the complete check passed after reactivating the fixture. Signature and Info.plist validation passed, and the release contains no debug QA flags.

Current evidence is under `qa/fullscreen-available/`. Timer-changing checks used the isolated DEBUG preference domain. The release was left running with the user's original session ID and exact start, checkpoint, and hard-stop timestamps. The fixture was closed.

## Earlier desktop visibility and popup dismissal

The user reported that the island was missing on the desktop. This was reproduced with a maximized ordinary window whose `AXFullScreen` value was false. The former foreground-window-size heuristic incorrectly hid the island. It has been removed. A disposable native panel experiment also found that simply omitting `fullScreenAuxiliary` did not exclude this panel from a foreign full-screen Space on macOS 26.5.1. Explicit `fullScreenNone` did, including when launched within full screen. That was the policy for this earlier verification pass.

Earlier visibility assertions were insufficient: `NSWindow.isVisible` can remain true while the window is on another Space. Current diagnostics and native regression checks use the WindowServer's actual on-screen window list, alongside the fixture's independent AX full-screen state. Earlier full-screen pass claims below are historical and superseded by this correction.

- Debug and release portable checks passed **109 assertions in 7 groups**. Six tests of the removed, incorrect window-size heuristic were deleted; the remaining timer, persistence, theme, notification-plan, and notch geometry checks are unchanged.
- `scripts/qa-visibility.py` passed with both debug and release apps: visible over normal and maximized desktop windows, usable hover, absent in real native full screen, accessible menu during full screen, and restored visibility after two complete Space round trips per run.
- `scripts/qa-popup.py --actions` passed with real mouse clicks: clicking another app, popup background, the notch, or Settings dismisses the popup; repeated status-icon toggles do not reopen it accidentally. Settings and Start/Cancel controls execute before dismissal.
- `scripts/qa-placement.py` passed using the corrected on-screen assertion: hover and menu access did not resurrect the island in native full screen; a hard stop remained hidden there, reappeared on desktop return, and led through break completion to idle. Popup anchoring stayed correct after timer-state changes.
- `scripts/qa-hover.py` passed again: quick flybys, outward header movement, control travel, collapse reversal, Start/Cancel clicks, transparent boundaries, and the island menu shortcut all worked.
- The independent read-only review found no material issues in native Space membership, input suppression, popup action ordering, delayed-close generation checks, or permission requirements. See [review notes](review.md).

The release was also launched while the fixture was already in native full screen: the island stayed absent, the menu worked, and returning to the desktop restored the island. Its normal production session reconstructed with the exact original session ID, start, checkpoint, and hard-stop timestamps. The ad-hoc signature and Info.plist validate, and the release binary contains neither debug QA launch flag.

The release popup script passed again without timer actions, preserving the active session. After closing the fixture, the island was confirmed on the user's actual maximized ChatGPT desktop window (`AXFullScreen=false`, position 0,34 and size 1710×1073). Compact and expanded release screenshots were captured and visually inspected: the notch is visible, the header and controls are readable, and the surface expands continuously. The release app was left running with the original focus session, and the test fixture was closed.

Evidence is under `qa/visibility/`. `desktop-maximized-before.json` is the reproduced failure; `desktop-maximized-after.json` is the corrected behavior. `probe-*.json` records the disposable panel experiment, not the shipped app. `release-launch-*.json` records the release launch and desktop return; `active-session-before.json` and `active-session-after.json` confirm preservation. All timer-changing QA ran in the isolated debug domain.

## Hover transformation and corner correction

The user's screenshot clarified the intended interaction: the notch itself expands over the menu bar, with its timer and icon moving outward around the fixed camera gap. That is now one continuous surface. Its top corners flare outward with concave curves: 6 points collapsed and 14 points expanded. The native canvas remains fixed at 428×159 points on the tested display, reserving room for the flares around the 400-point content width. Visible heights are 33 points collapsed, 133 expanded idle, and 151 expanded active.

In that earlier build, System mode kept the notched island black while the menu and Settings followed macOS appearance. The former Solarized choices colored every app surface; version 1.1.1 removes those choices. The right-hand island icon opens the same anchored menu as the native status item. The island folds away while that menu is open and preserves pending hard-stop prompts.

- Debug and release portable core checks pass **115 assertions in 7 groups**. Geometry cases cover rounded corners, invisible canvas, opening and closing phases, menu-band expansion, and both outward flares and their transparent surroundings.
- The native hover regression failed against the original release on quick pointer transit. It passes with the final implementation: brief flybys stay closed; header elements move outward; movement into controls stays open; re-entry during collapse reverses the morph; actual Start/Cancel clicks work; empty canvas passes input through. The island menu shortcut opens the correctly anchored popup and folds the island away.
- `scripts/qa-placement.py` passed: real native full-screen suppression, menu access during full screen, a hidden hard stop, prompt restoration after exiting, and break completion. On the final run, the island stayed hidden until the fixture left full screen.
- `scripts/qa-lifecycle.py` passed: checkpoint without stopping focus, Continue through the island after closing the menu, hard stop, break completion, early break, and repeated start/cancel.
- Native screenshots of the final flared shell, expanded hard stop, Solarized Light, Solarized Dark, and System were inspected. Evidence includes `qa/hover/flared-*.png`, `qa/hover/result.json`, and the latest records under `qa/placement/` and `qa/final/`.
- A separate reviewer inspected the shared animation/input path, delayed-work invalidation, menu handoff, fixed camera gap, and flared-corner geometry. The final review found no remaining material issue. See [review notes](review.md).

Intermediate runs during interactive design were interrupted when the foreground app or Space changed, and were repeated. They are not passing evidence. The final native runs above completed successfully.

The final release bundle passed the same native hover, moving-header, Start/Cancel, island-to-menu handoff, and popup-anchor checks. Its ad-hoc signature and Info.plist validate, and its binary contains no QA timer flag. The release was left running and idle; the disposable full-screen fixture was closed. `qa/hover/release-flared.png` shows that exact release.

The timer model and notification behavior were unchanged. Earlier environment limits below still apply: one physical display, notification permission denied, and portable checks instead of XCTest on the installed Command Line Tools.

## Earlier placement correction

The user found three issues missed by the first visual pass: the island sat below the notch, it overlaid full-screen apps, and its popup appeared too far below the menu-bar icon. The lower-boundary placement described in the original report below is superseded.

- Debug and release core checks now pass **95 assertions in 7 groups**, including screen-top placement, camera-gap alignment, menu-bar hiding, and display-covering geometry.
- `scripts/qa-placement.py` passed using actual pointer clicks, Accessibility controls, and a separate native full-screen fixture. The compact island occupies y=0…33 on the tested display. The header leaves the camera cutout empty; hover expands the controls below it.
- A real click directly from the expanded island to the status icon opens the popup. Transparent shoulders pass clicks through. The icon frame was x=979, y=5, 24×24; the popup top was y=28, centered at the same x=991. The pre-fix popup top was y=147. The anchor remained correct after starting focus and in full screen.
- The island hides while the fixture is natively full screen, remains hidden during hover and menu interaction, and stays hidden when a real timer reaches hard stop. Exiting full screen restores the pending movement prompt. Starting a break then completing it returned to idle.
- The regular lifecycle script also passed again: checkpoint, Continue from the island, hard stop, break completion, early break, and rapid start/cancel cycles. The final reduced 183-point active layout was subsequently checked at a real hard stop and through break completion. Solarized Dark, Solarized Light, and System snapshots were visually inspected.
- Window snapshots and AX records for these checks are in `qa/placement/`. Early files named `before-*` and `*-first-fix` document reproduced defects, not passing evidence. The reusable fixture is `scripts/fullscreen-fixture.swift` and is never bundled into the timer app.
- The full-screen fallback uses only foreground-window geometry from public APIs. It also hides the island for edge-to-edge maximized windows with an auto-hidden Dock. If macOS supplies global presentation flags, a full-screen app on another screen can hide the single island. Only one physical monitor was available.

An attempted follow-up 1/2/1-minute shortcut did not reliably commit every field through AX and was not counted as a passing custom-duration test. The passing full-lifecycle runs used verified 5/10/3 values. An additional keyboard cleanup attempt appended digits, confined to the isolated QA preference domain. That domain was reset to 5/10/3 after quitting the debug app; production preferences were untouched.

The separate reviewer found no remaining material code issue after inspecting the new layout, click-through hit regions, popover sizing, and suppression policy. Its documentation finding was addressed in the README and here.

The final release build passed the same native hover-to-status click smoke test, showed the normal 50/90/10 defaults, and produced exact 3000/5400-second focus deadlines. Start/Cancel returned it to idle. Its ad-hoc signature validates and the binary contains no QA timer flag. The disposable fixture was closed; the release timer was left running and idle.

## Original full application verification

Tested September 21, 2026 on macOS 26.5.1, Apple Silicon, Swift 6.3.2, with one 1710 × 1107-point notched display. The screen reports a 33-point top safe area and a 185-point camera cutout. QA used an isolated preference domain and 20× speed, with committed 5/10/3-minute settings giving 15/30/9-second timers.

## Automated checks

- Debug and release `FocusCoreChecks`: 7 groups, 86 assertions passed.
- Coverage includes exact deadlines; non-stopping checkpoints; Continue; hard stop; all early-break states; completion only once; cancellation; custom durations; invalid values; malformed persisted records; active/checkpoint/hard-stop reconstruction; expired breaks; all persisted themes; notification plans; and display geometry.
- Geometry checks cover notched, rectangular, auto-hidden menu-bar, resized, and negative-origin secondary-display coordinates, plus a shell attached to the notch boundary.
- Debug and release app builds pass. The release compiler initially exposed inconsistent CoreGraphics imports; explicit imports fixed it without SDK modifications.
- XCTest source is also included. `swift test` cannot execute on this Command Line Tools installation because XCTest is absent. The portable checks above were executed in both configurations.

## Real application QA

The app was launched as its signed `.app` bundle. Native Accessibility actions operated actual menu/island buttons. Pointer movement exercised hover. Settings were edited through native controls and committed field-editor input. Screenshots include both actual desktop captures and app-owned view captures, inspected visually. The optional DEBUG input driver was used while diagnosing initial UI automation problems; the final lifecycle uses Accessibility controls.

| Scenario | Result and evidence |
| --- | --- |
| Initial launch | One island and one status item; accessory activation policy, no Dock icon. Menu exposes Start Focus, Start Break, Settings, Quit. |
| Themes | Solarized Light/Dark inspected on Settings, menu content, and island. System followed an actual macOS dark-mode toggle and restoration. The attached notch shell stays black; its expanded content follows the theme. |
| Start and synchronization | Menu action starts focus; the island and status item update from the same model. `qa/final/focus-started.json` records the exact deadlines. |
| Hover | Pointer entry expands the real window; exit collapses it after the delay. The notch refinement keeps a flush top boundary and readable controls. A native CGEvent mouse click started focus. The frontmost application remained Google Chrome before and after passive hover. |
| Checkpoint | Reached at 15 seconds; focus remains active while the prompt waits. Continue from the island reaches `focusAfterCheckpoint`. |
| Hard stop | Reached at 30 seconds; expanded movement prompt exposes Start Break and End Session. `qa/final/hard-stop-window-0.png` was visually checked. |
| Break | Break countdown runs, focus controls disappear, completion returns to idle and shows Break complete. |
| Early break | Started a break at the checkpoint, then ended it manually. |
| Custom durations | Saved 5/10/3 and verified persisted JSON and actual 15/30/9-second QA deadlines. |
| Relaunch and suspension | Normal Quit preserves timestamps. Relaunch restores the same deadlines. A 17-second suspension of only the app process crossed the checkpoint correctly; the hard stop still occurred at its original deadline. Leaving the app closed for 31 seconds and reopening reconstructed the hard-stop prompt immediately. |
| Cross-surface actions | Started through menu controls and continued/started break through island controls; recorded state and clocks remained consistent. |
| Rapid actions | Three start/cancel/start cycles, eight rapid hover/unhover pairs, and six status-menu toggles completed without crash or corrupt state. Equal checkpoint/hard-stop values and a zero checkpoint were rejected inline; invalid Save did not change persisted preferences. |
| Notification denial | macOS reported native authorization status `denied`. The complete focus/checkpoint/hard-stop/break lifecycle passed in that state; no native pending requests accumulated. |

Reproducible UI scripts are `scripts/qa-lifecycle.py` and `scripts/qa-relaunch.py`. Final evidence is under `qa/final/`. Earlier diagnostic attempts under `qa/evidence/` include superseded failures and must not be treated as passing final evidence. One early timer mismatch was traced to uncommitted AX field edits: the saved values were still 5/90/10. The final run verified actual saved values before asserting deadlines.

The final release bundle also passed a separate smoke test: normal 50/90/10 defaults, actual 3000/5400-second focus deadlines, Start/Cancel through native controls, and no compiled QA launch flags. Its ad-hoc signature and Info.plist validate. It was left running and idle.

## Limits

Native notification banners and permitted notification scheduling were not verified because macOS denied notification permission. The in-app prompts remain usable, and pure notification planning plus scheduling code were reviewed. No privacy permissions were changed to bypass denial.

Only one physical display was available. Rectangular screens, negative display origins, and changed sizes were tested through the same geometry function the window controller uses, rather than by attaching another monitor. Real system sleep and display sleep were not forced; process suspension and relaunch were exercised.

Independent architecture and implementation reviewers, followed by a separate review of notch attachment, found no unresolved blocker, high, or medium code issue. See [review notes](review.md).
