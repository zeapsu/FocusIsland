#!/bin/bash
# Build a self-contained Focus Island app bundle. It only writes to dist/.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
  echo "Usage: $0 [release|debug]" >&2
  exit 2
fi

version="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
  echo "VERSION must be a semantic version (for example 1.1.0)." >&2
  exit 2
fi
build_number="${BUILD_NUMBER:-1000}"
if [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
  echo "BUILD_NUMBER must be a positive integer." >&2
  exit 2
fi

public_key_file="$root/config/sparkle-public-key.txt"
if [[ ! -s "$public_key_file" ]]; then
  echo "Missing Sparkle public key at config/sparkle-public-key.txt." >&2
  exit 1
fi
public_key="$(tr -d '[:space:]' < "$public_key_file")"
if [[ ! "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  echo "config/sparkle-public-key.txt must contain one base64 Ed25519 public key." >&2
  exit 1
fi

swift_args=(build -c "$configuration")
if [[ "${FOCUS_ISLAND_UNIVERSAL:-0}" == "1" ]]; then
  swift_args+=(--arch arm64 --arch x86_64)
fi
swift "${swift_args[@]}"
bin_args=(build -c "$configuration" --show-bin-path)
if [[ "${FOCUS_ISLAND_UNIVERSAL:-0}" == "1" ]]; then
  bin_args+=(--arch arm64 --arch x86_64)
fi
bin_path="$(swift "${bin_args[@]}")"

app_path="$root/dist/Focus Island.app"
running_path="$app_path/Contents/MacOS/FocusIsland"
if pgrep -f "$running_path" >/dev/null 2>&1; then
  echo "Refusing to replace the running dist bundle: $app_path" >&2
  exit 1
fi
stage_root="$(mktemp -d "${TMPDIR:-/tmp}/focus-island-build.XXXXXX")"
cleanup() { /bin/rm -rf "$stage_root"; }
trap cleanup EXIT
stage_app="$stage_root/Focus Island.app"
mkdir -p "$stage_app/Contents/MacOS" "$stage_app/Contents/Resources" "$stage_app/Contents/Frameworks"
cp "$bin_path/FocusIsland" "$stage_app/Contents/MacOS/FocusIsland"

# SwiftPM resolves Sparkle as a binary framework. Embed it so the app never
# relies on a developer's local .build directory at runtime.
sparkle_framework="$root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$sparkle_framework" ]]; then
  echo "Expected SwiftPM Sparkle binary artifact is missing: $sparkle_framework" >&2
  exit 1
fi
ditto "$sparkle_framework" "$stage_app/Contents/Frameworks/Sparkle.framework"

plist="$stage_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string FocusIsland' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string local.focusisland.app' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string Focus Island' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Focus Island' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build_number" "$plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 14.0' "$plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$plist"
/usr/libexec/PlistBuddy -c 'Add :NSHighResolutionCapable bool true' "$plist"
/usr/libexec/PlistBuddy -c 'Add :NSPrincipalClass string NSApplication' "$plist"
/usr/libexec/PlistBuddy -c 'Add :SUFeedURL string https://github.com/zeapsu/FocusIsland/releases/latest/download/appcast.xml' "$plist"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $public_key" "$plist"
/usr/libexec/PlistBuddy -c 'Add :SUEnableAutomaticChecks bool true' "$plist"
/usr/libexec/PlistBuddy -c 'Add :SUEnableSystemProfiling bool false' "$plist"
/usr/libexec/PlistBuddy -c 'Add :SUSendProfileInfo bool false' "$plist"
/usr/libexec/PlistBuddy -c 'Add :SURequireSignedFeed bool true' "$plist"
/usr/libexec/PlistBuddy -c 'Add :SUVerifyUpdateBeforeExtraction bool true' "$plist"
plutil -lint "$plist" >/dev/null

# Sparkle has helper apps and XPC services inside its framework. Sign nested
# code first, then the framework, executable, and enclosing app.
install_name_tool -add_rpath '@executable_path/../Frameworks' "$stage_app/Contents/MacOS/FocusIsland" 2>/dev/null || true
identity="${CODE_SIGN_IDENTITY:--}"
sign() { codesign --force --sign "$identity" --timestamp=none "$1"; }
while IFS= read -r -d '' nested; do sign "$nested"; done < <(find "$stage_app/Contents/Frameworks/Sparkle.framework" \( -name '*.app' -o -name '*.xpc' \) -type d -print0)
sign "$stage_app/Contents/Frameworks/Sparkle.framework"
sign "$stage_app/Contents/MacOS/FocusIsland"
sign "$stage_app"
codesign --verify --deep --strict "$stage_app"

mkdir -p "$root/dist"
/bin/rm -rf "$app_path"
mv "$stage_app" "$app_path"
echo "$app_path"
