#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macOS is required to build the native helper." >&2
  exit 2
fi
if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found. Install Xcode Command Line Tools: xcode-select --install" >&2
  exit 2
fi

mkdir -p "$BUILD"

xcrun --sdk macosx clang \
  -fobjc-arc \
  -O2 \
  -std=c11 \
  -Wall -Wextra \
  -mmacosx-version-min=13.0 \
  -Isrc \
  "$ROOT/src/GestureLogic.c" \
  "$ROOT/src/DockSwipe.m" \
  "$ROOT/src/main.m" \
  -framework Cocoa \
  -framework ApplicationServices \
  -framework Carbon \
  -o "$BUILD/mousegesture-helper"

# Stable local identifier. This is ad-hoc signing, not Developer ID signing.
codesign --force --sign - --identifier com.local.mousegesture-helper "$BUILD/mousegesture-helper"

echo "Built: $BUILD/mousegesture-helper"
