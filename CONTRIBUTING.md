# Contributing to Focus Island

Thanks for helping keep Focus Island small, calm, and reliable.

## Development setup

Use macOS 14 or later with Swift 6. Apple Command Line Tools are sufficient for the portable build and core checks.

```sh
git clone https://github.com/zeapsu/FocusIsland.git
cd FocusIsland
./scripts/build-app.sh debug
open "dist/Focus Island.app"
```

The app has no third-party service account or local configuration requirement. Quit a running copy before rebuilding the bundle.

## Before opening a pull request

Run the portable checks:

```sh
./scripts/test-core.sh
swift run -c release FocusCoreChecks
./scripts/build-app.sh release
```

If you have full Xcode installed, also run the XCTest suite:

```sh
swift test
```

Changes to timer behavior should add focused coverage to `FocusCoreChecks` and, when appropriate, `Tests/FocusCoreTests`. The timer logic accepts a clock so tests must use injected times instead of waiting for real minutes.

For island, menu, window-behavior, or Settings changes, exercise the debug-only UI QA flow in [docs/qa-environment.md](docs/qa-environment.md). It needs Accessibility permission for the local automation helper and uses a separate preference domain so it cannot alter normal app settings.

## Project conventions

- Keep timing based on persisted absolute timestamps. A display refresh is for presentation only.
- Keep the explicit session state machine as the source of transitions; do not add scattered state flags.
- Keep the menu bar, island, and Settings backed by the same session controller.
- Preserve offline operation when notification permission is denied.
- Add accessibility labels to controls and respect Reduce Motion when changing hover behavior.
- Prefer Apple frameworks and avoid features that require accounts, cloud state, or analytics unless the roadmap proposal has been accepted.

## Pull requests

Explain the user-visible change, the timer/window behavior it affects, and the checks you ran. Include a short screen recording or screenshots for visual interaction changes when practical. Do not include personal desktop content in captures.

## Security and privacy

Do not put credentials, signing keys, update private keys, personal timer data, or captured desktop material in the repository. Report a security issue privately to the maintainers rather than publishing sensitive details in a public issue.
