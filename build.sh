#!/bin/bash
# Builds Slate.app from the Swift package.
# Usage: ./build.sh [--run]
set -euo pipefail

cd "$(dirname "$0")"

APP="Slate.app"
CONFIG="${CONFIG:-release}"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Slate"
if [ ! -x "$BIN" ]; then
  echo "error: binary not found at $BIN" >&2
  exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Slate"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "==> Generating icon"
  TMP=$(mktemp -d)
  swift Tools/make-icon.swift "$TMP/icon-1024.png" >/dev/null
  mkdir -p "$TMP/AppIcon.iconset"
  for spec in "16 16" "32 16@2x" "32 32" "64 32@2x" "128 128" "256 128@2x" "256 256" "512 256@2x" "512 512" "1024 512@2x"; do
    set -- $spec
    sips -z "$1" "$1" "$TMP/icon-1024.png" --out "$TMP/AppIcon.iconset/icon_$2.png" >/dev/null
  done
  iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$TMP"
fi

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed"

# Refresh Launch Services so the icon and name show up immediately.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true

echo "==> Built $APP"

# Launch Services resolves the bundle id to /Applications, so keep that copy in
# step with the one in the repo; otherwise launching by bundle id runs an old app.
if [ -w /Applications ]; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/$APP"
  cp -R "$APP" "/Applications/$APP"
  codesign --force --deep --sign - "/Applications/$APP" >/dev/null 2>&1 || true
fi

if [ "${1:-}" = "--run" ]; then
  echo "==> Launching"
  open "/Applications/$APP" --args "${@:2}"
fi
