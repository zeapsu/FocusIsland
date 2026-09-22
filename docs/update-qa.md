# Release and updater verification

Verified September 21, 2026 on a notched Apple Silicon Mac running macOS 26.5.1.

## Automated checks

- [CI for build 1002](https://github.com/zeapsu/FocusIsland/actions/runs/35670039452) passed: 109 portable assertions in seven groups, 18 XCTest tests with zero failures, universal arm64/x86_64 packaging, and bundle validation.
- [Release workflow](https://github.com/zeapsu/FocusIsland/actions/runs/35670191686) passed: restored the tested bundle, signed the archive and appcast, verified both signatures, published complete assets, and checked the downloaded public bytes against the signed originals.
- Local debug/release builds and portable checks passed. Sparkle's verifier accepted the original archive/feed and rejected separately altered copies of each.
- Bundle validation checks the application identifier, version/build, tracked public key, signed-feed requirement, verification before extraction, disabled profiling, framework search path, code signature, and both architectures for every executable in CI.
- The first hosted build caught an ambiguous CGFloat/Double conversion under the runner's Swift compiler. An explicit conversion fixed it; the failed build published no release.

## Native update test

A real installed build 1000 checked the public GitHub feed and updated to build 1002 through Sparkle's native controls. No test feed, replacement installer, or QA timer flags were used.

1. The automatic first check showed the tray update indicator and `Update to v1.1.0 (1002)…` without presenting a modal prompt.
2. The menu opened directly below its status item and showed the active checkpoint session alongside the update.
3. `Remind Me Later` dismissed Sparkle's prompt while preserving the tray indicator and update action.
4. `Install Update`, followed by `Install and Relaunch`, downloaded the published archive and relaunched the application in `/Applications/Focus Island.app` at build 1002.
5. The original session ID, start/checkpoint/hard-stop timestamps, and timer settings matched exactly after installation. The session was still at its checkpoint. One app process was running.
6. The installed universal bundle passed strict code-signature and configuration validation. A subsequent manual check displayed `You’re up to date!` and cleared the availability indicator.
7. Disabling automatic checks in Settings persisted the change. Re-enabling restored the original enabled setting. Notification permission remained enabled.
8. The installed release passed popup dismissal checks and desktop/maximized/full-screen visibility, hover, menu access, and two full-screen round trips without changing the session. Two earlier harness attempts did not enter full screen despite successful AXPress return values; those are not passing evidence. The completed run used real mouse clicks for the fixture’s full-screen button and independently verified the Space and foreground app.

The test used native Accessibility inspection, actual mouse clicks, application-window screenshots, and direct reads of the installed bundle and persisted state. Local evidence is under ignored `qa/updates/`; private session records are not published.

The next automatic publication exposed a propagation delay: GitHub initially served the previous signed feed after the new release was published. The post-publication check was corrected to retry until the downloaded feed matches the expected signed bytes, rather than accepting the first HTTP 200 response. It still fails if the expected feed does not become available.

## Scope and limits

The separate static review found no remaining material issue in the updater, signing flow, release permissions, or session-preserving termination. Runtime checks complement that review.

Only one physical Apple Silicon Mac was available. Intel slices were verified in the distributed bundle but were not executed on Intel hardware. The releases are ad-hoc signed and Sparkle-authenticated; they are not Developer ID signed or notarized. The first-download Gatekeeper path on a clean Mac remains part of [issue #2](https://github.com/zeapsu/FocusIsland/issues/2).
