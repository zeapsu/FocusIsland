# Independent review

Review date: September 21, 2026.

## Notification permission action

A separate reviewer inspected the already-denied permission path, asynchronous status refresh, scheduling, errors, and accessibility. No blocker, high, or medium findings. The action now requests authorization only for `notDetermined`, routes existing decisions to the app's System Settings page, and disables repeated clicks while checking. Returning to the app refreshes permission. A status change resynchronizes the existing notice plan through the serialized scheduler without changing timer timestamps. Request errors remain visible. A stable identifier was added to the menu Settings button so native QA distinguishes it from Open Notification Settings.

## Availability in full-screen apps

The user subsequently requested visibility in full-screen apps as well as on the desktop. A fresh independent reviewer inspected the change from `fullScreenNone` to `fullScreenAuxiliary`, alongside `canJoinAllSpaces`, the nonactivating panel, native Space input guards, and hard-stop pinning. No material findings. The review also checked the updated native regressions for actual on-screen presence, passive hover, menu dismissal, hard stop, break completion, and desktop return. Timer state and popup dismissal code are unchanged.

The earlier full-screen hiding policy below is historical. The current policy keeps the island available in full-screen Spaces.

## Earlier desktop visibility and popup dismissal

A fresh reviewer inspected the native Space policy, hover suppression, popup event ordering, and recorded native QA without editing files or operating the app. No material issues were found. The former window-size heuristic is removed: the panel now uses `canJoinAllSpaces` with `fullScreenNone`, and `isOnActiveSpace` gates input. Timer persistence and transitions are independent of visibility.

Popup event monitors pass clicks through, defer closing until an inside control finishes its mouse-up action, and guard against closing a newly opened popup. Status-item gestures clear their suppression flag after mouse-up or the next mouse-down. No new permission or entitlement is required. The reviewer identified only a coverage gap for clicking the notch while the popup is open; that case was added to the native popup script.

Earlier full-screen reviews below are historical. They missed the maximized-desktop false positive and relied on visibility evidence that did not distinguish an ordered window from an on-screen window. The current QA checks the WindowServer's actual on-screen window list and verifies the fixture's native full-screen state separately.

## Hover transformation correction

The user reported both unstable hover behavior and an awkward expanded layout, then clarified that the compact state should transform into the expanded view. A separate reviewer inspected the window controller, shared shape geometry, views, and regression checks without editing files or operating the app.

The first correction still used target-state hit regions during visual animation. Review identified this mismatch, rounded-corner interception, and a short click-through gap when restoring the panel. These were corrected with one shared path and animation progress, initial click-through behavior, and immediate pointer updates. A follow-up added generation checks for delayed entry/exit work and refreshed pointer state after display changes. The last geometry adjustment preserves the neighboring status item's lower corner as well as its center.

The user then supplied a reference and clarified that the expanded island should cover the menu bar, with header elements moving outward. The final implementation uses one full-width silhouette and a right-wing shortcut to the anchored menu. Opening the menu folds the island away without clearing a pending hard stop. A further requested refinement adds concave top corners, with six-point collapsed and fourteen-point expanded flares; the canvas reserves room for them while the content remains centered. Separate targeted reviews found no remaining material issue in the menu handoff, width separation, or shared curved hit path. The native window stays fixed throughout. The earlier native-window resizing approach described below is superseded. Runtime evidence is recorded in the [QA report](qa-report.md).

## Earlier implementation reviews

The architecture reviewer inspected the design before completion. Two independent implementation-review passes inspected the completed source. Reviewers made no source edits and did not operate the running app.

Issues addressed:

- Clarified that focus settings apply at focus start, break duration applies at break start, and active deadlines never move.
- Removed the app delegate's implicitly unwrapped model reference.
- Corrected panel-level setup order, because setting `isFloatingPanel` resets the level.
- Replaced an AppKit animator proxy that left the window frame unchanged with native animated window resizing.
- Added a pointer-position check to recover missed tracking events on a nonactivating panel.
- Made the panel eligible for keyboard focus on explicit interaction, while keeping hover and passive updates nonactivating. Added its floating-window accessibility role and parent. Live Accessibility QA then exposed island buttons and Settings controls.
- Used UTC calendar notification triggers and preserved newly due requests across natural deadline transitions, so a timer refresh does not cancel a notification awaiting whole-second delivery.
- Serialized notification changes and waited for scheduling work on a normal Quit.

The final source review found no unresolved blocker, high, or medium issues. Notification delivery and UI behavior still require runtime evidence; review does not substitute for the [QA results](qa-report.md).

A separate follow-up reviewer inspected the notch attachment and adaptive heights after the requested visual refinement. It found no actionable blocker, high, or medium issue. The shell meets the reported notch boundary; expanded content remains readable, and rectangular screens retain menu-bar clearance.

## Placement correction after user feedback

The previous visual pass did not catch the user's placement problems. That lower-boundary design is superseded: the compact panel now starts at the screen top and reserves the physical camera gap. A fresh reviewer inspected the geometry, shaped header, click-through shoulders, full-screen suppression, and explicit popover sizing. The final implementation uses `CGDisplayBounds(displayID)` directly for WindowServer coordinates. The reviewer found no remaining material code issue and required the README to describe full-screen hiding and its conservative edge-to-edge-window fallback. Those documentation changes are included.

Runtime QA, rather than the initial architectural assumption, determined the full-screen implementation. Removing `fullScreenAuxiliary` did not hide the accessory panel on this Mac. The documented `currentSystemPresentationOptions` also returned zero during a confirmed native full-screen session. The public window-geometry fallback was added for that case. Reviews did not substitute for those live checks.
