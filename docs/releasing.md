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

## Code signing

Releases are signed with the project's self-signed certificate, "Focus Island
Code Signing", valid until 2046-10-10. Its SHA-1 fingerprint is tracked in
`config/code-signing-certificate.txt`. The release job fails once the
certificate is within a year of expiry. macOS keys the Accessibility permission
to the app's designated requirement, which for this certificate is
`identifier "local.focusisland.app" and certificate leaf = H"<fingerprint>"`.
That requirement stays the same across builds, so the permission survives
updates. Ad hoc signatures change with every build and would revoke it.

CI builds stay ad hoc. The release job restores the tested bundle, imports the
certificate into a temporary keychain, re-signs the bundle with
`scripts/sign-app.sh`, and deletes the keychain. `verify-app.sh` with
`EXPECT_PROJECT_SIGNATURE=1` fails any release that does not carry the
certificate.

One-time setup, in addition to the Sparkle key:

1. Keep `FocusIsland-CodeSigning.p12` and its password somewhere durable, such
   as a password manager. Losing them forces one more Accessibility re-grant
   for every user when a new certificate replaces this one.
2. Add two repository Actions secrets: `CODE_SIGNING_P12` (the `.p12` file,
   base64-encoded, for example `base64 -i FocusIsland-CodeSigning.p12 | pbcopy`)
   and `CODE_SIGNING_P12_PASSWORD`.
3. Optional for local QA builds: import the `.p12` into your login keychain and
   build with `CODE_SIGN_IDENTITY="$(cat config/code-signing-certificate.txt)"`
   so local copies keep their Accessibility grant too.

Only the Sparkle EdDSA key authorizes updates. With
`SUVerifyUpdateBeforeExtraction`, Sparkle checks the EdDSA signature before
extracting; its code-signing fallback requires a Developer ID team and never
applies to this app. The certificate only has to produce a valid signature,
so the one-time move from ad hoc to it needed no special handling, and losing
the EdDSA private key would still cut every user off from updates.

Add both secrets before merging a release. If they are missing, the release job
fails before creating a tag; add them and re-run that Release run within the
7-day artifact retention. The build number does not change.

### Creating or rotating the certificate

A replacement certificate changes the designated requirement, so every user
grants Accessibility once more. Rotate only when necessary, and publish a
release note saying so.

1. Create the certificate with OpenSSL (code-signing usage, 20-year validity):

   ```sh
   cat > cert.cnf <<'CNF'
   [req]
   distinguished_name = dn
   x509_extensions = ext
   prompt = no
   [dn]
   CN = Focus Island Code Signing
   [ext]
   basicConstraints = critical, CA:false
   keyUsage = critical, digitalSignature
   extendedKeyUsage = critical, codeSigning
   CNF
   openssl req -x509 -newkey rsa:3072 -nodes -keyout key.pem -out cert.pem -days 7300 -config cert.cnf
   openssl rand -base64 24 | tr -d '\n' > p12-password.txt
   openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -out FocusIsland-CodeSigning.p12 \
     -passout file:p12-password.txt -name "Focus Island Code Signing"
   rm key.pem
   ```

   Keep the subject to a CN: an OU can become a Team ID that Sparkle's helpers
   then require. `-legacy` keeps the `.p12` importable by `security import`.
2. Write the new SHA-1 (`openssl x509 -in cert.pem -noout -fingerprint -sha1`,
   colons removed) to `config/code-signing-certificate.txt` and update the
   expiry date above.
3. Replace both repository secrets as described in the setup steps.

## Distribution limits

The certificate is self-signed, not a Developer ID, and releases are not
notarized. Gatekeeper still treats the app as coming from an unidentified
developer on first launch. Sparkle's Ed25519 signatures protect update
integrity. These artifacts must not be described as notarized.
