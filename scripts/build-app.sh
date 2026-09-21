#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != release && "$configuration" != debug ]]; then
  echo "Usage: $0 [release|debug]" >&2
  exit 2
fi
swift build -c "$configuration"
bin_path="$(swift build -c "$configuration" --show-bin-path)"
app_path="$PWD/dist/Focus Island.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/FocusIsland" "$app_path/Contents/MacOS/FocusIsland"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FocusIsland</string>
<key>CFBundleIdentifier</key><string>local.focusisland.app</string>
<key>CFBundleName</key><string>Focus Island</string>
<key>CFBundleDisplayName</key><string>Focus Island</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app_path"
echo "$app_path"
