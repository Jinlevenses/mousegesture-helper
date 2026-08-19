#!/bin/bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.local.mousegesture-helper.plist"
INSTALL_DIR="$HOME/Library/Application Support/MouseGestureHelper"
KARABINER_FILE="$HOME/.config/karabiner/assets/complex_modifications/mousegesture-helper.json"
DOMAIN="gui/$UID"

launchctl bootout "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST" "$KARABINER_FILE"
rm -rf "$INSTALL_DIR"

echo "Removed MouseGestureHelper files."
echo "If the Karabiner rule is still enabled, disable/remove it in Karabiner-Elements."
