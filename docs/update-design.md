# GitHub releases and signed updates

Focus Island uses Sparkle 2.10 for update discovery, signature verification, installation, and relaunch. A custom installer or local file watcher is not used. The app remains usable offline and without an account.

## Release flow

1. Pull requests run tests and package validation without signing secrets or write permissions.
2. A push to `main` runs the same checks, builds a universal macOS app, and assigns an increasing internal build number. The readable version is in `VERSION`.
3. A trusted release job signs the update archive and appcast with Sparkle Ed25519 signing tools. The public key is committed in `config/sparkle-public-key.txt`. The private key is kept in the maintainer's macOS Keychain and the repository's encrypted Actions secret `SPARKLE_PRIVATE_KEY`, never in Git or log output.
4. CI uploads the archive and appcast to a draft GitHub Release and publishes only after every asset is uploaded. The updater reads `https://github.com/zeapsu/FocusIsland/releases/latest/download/appcast.xml` over HTTPS.
5. The installed app checks in the background. Its menu/status item indicates an available update and opens Sparkle's native update flow. Timer deadlines survive a graceful update/relaunch. The app does not force a restart during a focus session.

The updater must validate signed archives before extraction and require signed appcasts. It sends no Sparkle system profile. Update checking can be disabled. Unknown/misconfigured builds must remain usable as timers and explain why updates are unavailable.

## Trust and distribution

The public repository is `zeapsu/FocusIsland`, licensed MIT. Generated QA captures and live session metadata are excluded. README media must show only the app against a neutral background. CI uses pinned actions, minimal permissions, and never signs or publishes pull-request code. External contributions require maintainer review before entering `main`.

No Developer ID certificate is available on this Mac. Initial builds are ad-hoc code signed for integrity and their update archives/feed are independently authenticated with Sparkle's Ed25519 signatures. They are not notarized. The README must state the first-install Gatekeeper limitation honestly. Developer ID signing/notarization is a tracked release-engineering follow-up, not a claimed completed capability.

The alternative local build/installer design was superseded by the user's choice of GitHub releases before implementation. HealthKit, analytics, and optional sign-in are roadmap proposals only; none of them are added to the current timer or update path.
