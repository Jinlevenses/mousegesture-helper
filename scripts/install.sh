#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="$HOME/Library/Application Support/MouseGestureHelper"
INSTALL_BIN="$INSTALL_DIR/mousegesture-helper"
PLIST="$HOME/Library/LaunchAgents/com.local.mousegesture-helper.plist"
LOG_DIR="$HOME/Library/Logs"
LOG_PATH="$LOG_DIR/MouseGestureHelper.log"
KARABINER_DIR="$HOME/.config/karabiner/assets/complex_modifications"
KARABINER_FILE="$KARABINER_DIR/mousegesture-helper.json"
LABEL="com.local.mousegesture-helper"
DOMAIN="gui/$UID"

"$ROOT/scripts/build.sh"
mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$LOG_DIR" "$KARABINER_DIR"
cp "$ROOT/build/mousegesture-helper" "$INSTALL_BIN"
chmod 755 "$INSTALL_BIN"
cp "$ROOT/karabiner/button3-to-f20.json" "$KARABINER_FILE"

sed \
  -e "s|__HELPER_PATH__|$INSTALL_BIN|g" \
  -e "s|__LOG_PATH__|$LOG_PATH|g" \
  "$ROOT/scripts/com.local.mousegesture-helper.plist.template" > "$PLIST"

launchctl bootout "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "$DOMAIN" "$PLIST"
launchctl kickstart -k "$DOMAIN/$LABEL" >/dev/null 2>&1 || true

echo
echo "Installed MouseGestureHelper."
echo "1) Karabiner-Elements > Complex Modifications > Add predefined rule"
echo "   Enable: MouseGesture Helper: reserve button3 as F20"
echo "2) Approve MouseGestureHelper in System Settings > Privacy & Security > Accessibility."
echo "3) If macOS requests Input Monitoring, enable it as well."
echo "4) After changing permissions, restart with:"
echo "   launchctl kickstart -k $DOMAIN/$LABEL"
echo
echo "Log: $LOG_PATH"
