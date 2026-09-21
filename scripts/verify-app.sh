#!/bin/bash
# Validate a built application bundle without launching it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$root/dist/Focus Island.app}"
plist="$app_path/Contents/Info.plist"

[[ -x "$app_path/Contents/MacOS/FocusIsland" ]] || { echo "Missing FocusIsland executable." >&2; exit 1; }
[[ -d "$app_path/Contents/Frameworks/Sparkle.framework" ]] || { echo "Sparkle.framework is not embedded." >&2; exit 1; }
plutil -lint "$plist" >/dev/null
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }
[[ "$(value CFBundleIdentifier)" == "local.focusisland.app" ]] || { echo "Unexpected bundle identifier." >&2; exit 1; }
[[ "$(value CFBundleShortVersionString)" == "$(tr -d '[:space:]' < "$root/VERSION")" ]] || { echo "Bundle version does not match VERSION." >&2; exit 1; }
[[ "$(value CFBundleVersion)" =~ ^[0-9]+$ ]] || { echo "CFBundleVersion must be numeric." >&2; exit 1; }
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  [[ "$(value CFBundleVersion)" == "$BUILD_NUMBER" ]] || { echo "Bundle build number does not match BUILD_NUMBER." >&2; exit 1; }
fi
[[ "$(value SUFeedURL)" == "https://github.com/zeapsu/FocusIsland/releases/latest/download/appcast.xml" ]] || { echo "Unexpected Sparkle feed URL." >&2; exit 1; }
[[ "$(value SURequireSignedFeed)" == "true" ]] || { echo "Signed appcasts are required." >&2; exit 1; }
[[ "$(value SUVerifyUpdateBeforeExtraction)" == "true" ]] || { echo "Archives must be verified before extraction." >&2; exit 1; }
[[ "$(value SUEnableSystemProfiling)" == "false" ]] || { echo "System profiling must remain disabled." >&2; exit 1; }
[[ "$(value SUSendProfileInfo)" == "false" ]] || { echo "Profiling must remain disabled." >&2; exit 1; }
[[ "$(value SUPublicEDKey)" == "$(tr -d '[:space:]' < "$root/config/sparkle-public-key.txt")" ]] || { echo "Bundle public key differs from tracked public key." >&2; exit 1; }
codesign --verify --deep --strict "$app_path"
otool -L "$app_path/Contents/MacOS/FocusIsland" | grep -q 'Sparkle.framework' || { echo "Executable is not linked to Sparkle.framework." >&2; exit 1; }
otool -l "$app_path/Contents/MacOS/FocusIsland" | grep -A2 'LC_RPATH' | grep -q '@executable_path/../Frameworks' || { echo "Executable has no embedded-framework rpath." >&2; exit 1; }
if [[ "${EXPECT_UNIVERSAL:-0}" == "1" ]]; then
  while IFS= read -r candidate; do
    file "$candidate" | grep -q 'Mach-O' || continue
    architectures="$(lipo -archs "$candidate")"
    [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || { echo "Not universal: $candidate ($architectures)" >&2; exit 1; }
  done < <(find "$app_path/Contents" -type f -perm -111 -print)
fi
echo "PASS verified $app_path"
