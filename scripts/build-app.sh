#!/usr/bin/env bash
# Builds a self-contained NexusBar.app bundle under build/.
#
# Usage:
#   scripts/build-app.sh                    # builds build/NexusBar.app
#   scripts/build-app.sh /Applications      # builds + installs to /Applications
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="NexusBar"
BUNDLE_ID="com.lucasferraz.nexusbar"
VERSION="1.0.0"
BUILD_NUM="1"
DEST="${1:-}"
APP="build/${APP_NAME}.app"

echo "==> Building release binary"
swift build -c release --product "$APP_NAME"

BIN="$(swift build -c release --product "$APP_NAME" --show-bin-path)/$APP_NAME"
[[ -x "$BIN" ]] || { echo "binary not found at $BIN" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                       <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>                <string>Nexus Bar</string>
    <key>CFBundleExecutable</key>                 <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>                 <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>                    <string>${BUILD_NUM}</string>
    <key>CFBundleShortVersionString</key>         <string>${VERSION}</string>
    <key>CFBundlePackageType</key>                <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>      <string>6.0</string>
    <key>LSMinimumSystemVersion</key>             <string>13.0</string>
    <key>LSUIElement</key>                        <true/>
    <key>NSHighResolutionCapable</key>            <true/>
    <key>NSPrincipalClass</key>                   <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>           <string>MIT licensed. Not affiliated with Corsair.</string>
</dict>
</plist>
PLIST

cat > "$APP/Contents/PkgInfo" <<<"APPL????"

echo "==> Ad-hoc code-signing (so launch services trusts the bundle)"
codesign --force --deep --sign - --options runtime "$APP" 2>/dev/null || \
    codesign --force --deep --sign - "$APP"

echo "==> Verify"
codesign --verify --verbose=1 "$APP" || true
spctl --assess --type execute --verbose "$APP" 2>&1 | head -3 || true

if [[ -n "$DEST" ]]; then
    DEST="${DEST%/}"
    echo "==> Installing to $DEST/$APP_NAME.app"
    rm -rf "$DEST/$APP_NAME.app"
    cp -R "$APP" "$DEST/$APP_NAME.app"
    echo "Installed."
fi

echo
echo "Done. Open with:"
echo "  open '$PWD/$APP'"
[[ -n "$DEST" ]] && echo "  open '$DEST/$APP_NAME.app'"
