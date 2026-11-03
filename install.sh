#!/bin/bash
# Installs the latest Remote Emulator release into ~/Applications.
#   curl -fsSL https://raw.githubusercontent.com/JcscJosecarlossilvacoelho/remote-emulator/main/install.sh | bash
#
# The app is open source but not notarized (no paid Apple Developer account),
# so this script removes the download quarantine flag — read it before running.
set -euo pipefail

REPO="JcscJosecarlossilvacoelho/remote-emulator"
URL="https://github.com/$REPO/releases/latest/download/Remote-Emulator.zip"
DEST="$HOME/Applications"
APP="$DEST/Remote Emulator.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Downloading Remote Emulator…"
curl -fsSL "$URL" -o "$TMP/Remote-Emulator.zip"
ditto -x -k "$TMP/Remote-Emulator.zip" "$TMP"

echo "→ Installing to $DEST"
mkdir -p "$DEST"
osascript -e 'tell application id "dev.remote-emulator.app" to quit' >/dev/null 2>&1 || true
rm -rf "$APP"
mv "$TMP/Remote Emulator.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "✓ Installed. Opening Remote Emulator…"
open "$APP"
