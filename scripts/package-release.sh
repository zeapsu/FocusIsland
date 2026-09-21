#!/bin/bash
# Create a Sparkle-signed ZIP and appcast with Sparkle's pinned official tools.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
version="$(tr -d '[:space:]' < VERSION)"
build_number="${BUILD_NUMBER:-1000}"
release_tag="${RELEASE_TAG:-v${version}-build.${build_number}}"
download_prefix="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/zeapsu/FocusIsland/releases/download/${release_tag}/}"
app_path="${1:-$root/dist/Focus Island.app}"
"$root/scripts/verify-app.sh" "$app_path"

tools_root="$root/.build/sparkle-tools-2.10.0"
archive_path="$tools_root/Sparkle-2.10.0.tar.xz"
tools_dir="$tools_root"
mkdir -p "$tools_root"
if [[ ! -f "$archive_path" ]]; then
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 -o "$archive_path" "https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz"
fi
expected_sha='c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c'
actual_sha="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
[[ "$actual_sha" == "$expected_sha" ]] || { echo "Sparkle tools checksum mismatch." >&2; exit 1; }
if [[ ! -x "$tools_dir/bin/generate_appcast" ]]; then tar -xJf "$archive_path" -C "$tools_root"; fi
generator="$tools_dir/bin/generate_appcast"
signer="$tools_dir/bin/sign_update"
[[ -x "$generator" && -x "$signer" ]] || { echo "Pinned Sparkle signing tools were not found." >&2; exit 1; }

output_dir="$root/dist/release"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/focus-island-release.XXXXXX")"
cleanup() { /bin/rm -rf "$work_dir"; }
trap cleanup EXIT
mkdir -p "$output_dir"
asset_name="Focus-Island-${version}-${build_number}.zip"
zip_path="$output_dir/$asset_name"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$work_dir/$asset_name"

# CI provides SPARKLE_PRIVATE_KEY and streams it to Sparkle. A developer's
# one-time generated local key remains in Keychain and is selected by account.
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$generator" --ed-key-file - --download-url-prefix "$download_prefix" --link 'https://github.com/zeapsu/FocusIsland' "$work_dir"
else
  "$generator" --account "${SPARKLE_KEYCHAIN_ACCOUNT:-focus-island-releases}" --download-url-prefix "$download_prefix" --link 'https://github.com/zeapsu/FocusIsland' "$work_dir"
fi
appcast_path="$work_dir/appcast.xml"
[[ -f "$appcast_path" ]] || { echo "generate_appcast did not produce appcast.xml." >&2; exit 1; }
grep -q 'sparkle:edSignature=' "$appcast_path" || { echo "Generated appcast has no EdDSA archive signature." >&2; exit 1; }
# Sparkle appends its detached signed-feed block after the XML document. The
# running updater verifies that block because SURequireSignedFeed is enabled.
grep -q '<!-- sparkle-signatures:' "$appcast_path" || { echo "Generated appcast is not signed as a feed." >&2; exit 1; }
grep -q "$asset_name" "$appcast_path" || { echo "Generated appcast does not reference $asset_name." >&2; exit 1; }
archive_signature="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$appcast_path" | head -1)"
[[ -n "$archive_signature" ]] || { echo "Could not extract the archive signature from appcast.xml." >&2; exit 1; }
# Verify both cryptographic signatures with Sparkle's official verifier before
# exposing these bytes to a publishing workflow.
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$signer" --ed-key-file - --verify "$work_dir/$asset_name" "$archive_signature"
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$signer" --ed-key-file - --verify "$appcast_path"
else
  "$signer" --account "${SPARKLE_KEYCHAIN_ACCOUNT:-focus-island-releases}" --verify "$work_dir/$asset_name" "$archive_signature"
  "$signer" --account "${SPARKLE_KEYCHAIN_ACCOUNT:-focus-island-releases}" --verify "$appcast_path"
fi
mv "$work_dir/$asset_name" "$zip_path"
cp "$appcast_path" "$output_dir/appcast.xml"
echo "$zip_path"
echo "$output_dir/appcast.xml"
