#!/bin/bash
# Test the actual AppKit controller with a controlled pointer position.
# Requires a logged-in macOS display session, but no Accessibility permission.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
swift build --target FocusCore
bin_path="$(swift build --show-bin-path)"
mkdir -p .build/hover-checks
swiftc -swift-version 5 -parse-as-library \
  -I "$bin_path/Modules" \
  "$root/Sources/FocusIsland/IslandWindowController.swift" \
  "$root/scripts/island-hover-checks.swift" \
  "$bin_path"/FocusCore.build/*.swift.o \
  -o "$root/.build/hover-checks/IslandHoverChecks"
"$root/.build/hover-checks/IslandHoverChecks"
