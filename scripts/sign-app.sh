#!/bin/bash
# Sign an app bundle inside-out: Sparkle's nested helpers, the framework, the
# executable, then the bundle. Usage: sign-app.sh <app> [identity]
# The identity defaults to ad hoc ("-"). Set CODE_SIGN_KEYCHAIN to sign from a
# keychain that is not in the search list, as the release workflow does.
set -euo pipefail

app_path="$1"
identity="${2:--}"
keychain_args=()
[[ -n "${CODE_SIGN_KEYCHAIN:-}" ]] && keychain_args=(--keychain "$CODE_SIGN_KEYCHAIN")
sign() { codesign --force --sign "$identity" "${keychain_args[@]+"${keychain_args[@]}"}" --timestamp=none "$1"; }
while IFS= read -r -d '' nested; do sign "$nested"; done < <(find "$app_path/Contents/Frameworks/Sparkle.framework" \( -name '*.app' -o -name '*.xpc' \) -type d -print0)
sign "$app_path/Contents/Frameworks/Sparkle.framework"
sign "$app_path/Contents/MacOS/FocusIsland"
sign "$app_path"
codesign --verify --deep --strict "$app_path"
