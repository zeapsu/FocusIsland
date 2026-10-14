#!/bin/bash
# Test the actual AppKit controller with a controlled pointer position.
# Requires a logged-in macOS display session, but no Accessibility permission.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
swift build --target FocusCore
bin_path="$(swift build --show-bin-path)"
# Swift 6.4 builds through swift-build: modules and a merged object sit in the bin path.
if [[ -d "$bin_path/Modules" ]]; then
  modules="$bin_path/Modules"; objects=("$bin_path"/FocusCore.build/*.swift.o)
else
  modules="$bin_path"; objects=("$bin_path/FocusCore.o")
fi
mkdir -p .build/hover-checks
swiftc -swift-version 5 -parse-as-library \
  -I "$modules" \
  "$root/Sources/FocusIsland/IslandWindowController.swift" \
  "$root/scripts/island-hover-checks.swift" \
  "${objects[@]}" \
  -o "$root/.build/hover-checks/IslandHoverChecks"
"$root/.build/hover-checks/IslandHoverChecks"
