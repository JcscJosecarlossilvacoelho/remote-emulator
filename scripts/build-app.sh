#!/bin/zsh
# Builds "Remote Emulator.app" into ./dist (universal binary, ad-hoc signed).
#   ./scripts/build-app.sh            → dist/Remote Emulator.app
#   ./scripts/build-app.sh --install  → also copies it to ~/Applications
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Remote Emulator"
BUNDLE_ID="dev.remote-emulator.app"
VERSION="$(cat VERSION 2>/dev/null || echo 0.1.0)"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "▸ Building release (arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/RemoteEmulator"

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RemoteEmulator"

if [[ ! -f Resources/AppIcon.icns ]]; then
  echo "▸ Rendering icon…"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  swift scripts/make-icon.swift "$ICONSET/icon_1024.png" >/dev/null
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICONSET/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$ICONSET/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  rm "$ICONSET/icon_1024.png"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/author.jpg "$APP/Contents/Resources/author.jpg"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>RemoteEmulator</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
echo "✓ $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/"$APP_NAME.app"
  cp -R "$APP" ~/Applications/
  echo "✓ Installed to ~/Applications/$APP_NAME.app"
fi
