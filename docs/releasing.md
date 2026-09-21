# Releasing Focus Island

Every successful push to `main` runs CI on macOS 15. CI resolves the pinned
dependencies, runs the portable core checks, builds a universal arm64/x86_64
bundle, verifies it, and stores it as a short-lived workflow artifact. Pull
requests use the same verification job but never receive a signing secret and
cannot publish a release.

A separate release workflow runs only after a successful `push` to `main`. It
uses `1000 + GitHub Actions run number` as `CFBundleVersion`, which strictly
increases across releases. `VERSION` is the user-facing version. The release
tag is immutable (`v<version>-build.<build>`), so each appcast enclosure points
at its own release asset. The workflow creates a draft, uploads the complete
ZIP and appcast, and publishes it only after both uploads finish.

## One-time setup

1. Create the public repository `zeapsu/FocusIsland` with `main` as its default
   branch and push this repository.
2. Generate a Sparkle Ed25519 key pair using Sparkle 2.10.0's `generate_keys`.
   Commit only the base64 public key in `config/sparkle-public-key.txt`.
3. Add the private key as the repository Actions secret `SPARKLE_PRIVATE_KEY`.
   Do not commit it. The workflow streams it to Sparkle's tool on standard
   input, so it is never written to disk.
4. Keep `main` protected. CI has `contents: read`; only the release job has the
   `contents: write` permission needed to create a GitHub Release.

The app pins its feed to
`https://github.com/zeapsu/FocusIsland/releases/latest/download/appcast.xml`.
It embeds the public Ed25519 key, disables system/profile reporting, requires a
signed appcast, and verifies an update archive before extraction.

## Local builds

```sh
./scripts/build-app.sh debug
./scripts/build-app.sh release
./scripts/verify-app.sh
```

`BUILD_NUMBER` defaults to `1000`; set it explicitly for a local candidate.
Set `FOCUS_ISLAND_UNIVERSAL=1` on a Mac with both target SDKs to make the same
universal executable as CI.

To assemble a publishable update locally, use the one-time Sparkle Keychain
account (`focus-island-releases`) created by `generate_keys`:

```sh
BUILD_NUMBER=1001 RELEASE_TAG=v1.1.0-build.1001 ./scripts/package-release.sh
```

The script downloads only Sparkle 2.10.0's official release tools, verifies its
SHA-256, creates the archive with `ditto`, and calls Sparkle's
`generate_appcast`. In CI, `SPARKLE_PRIVATE_KEY` replaces the Keychain lookup
and is streamed through standard input. Output is
`dist/release/Focus-Island-<version>-<build>.zip` and `dist/release/appcast.xml`.

## Distribution limits

Current builds are ad-hoc signed because this project does not have a Developer
ID certificate or notarization. Sparkle's Ed25519 signatures protect update
integrity, but Gatekeeper may warn for a downloaded app. A Developer ID-signed,
notarized release is future work; these artifacts must not be described as
notarized.
