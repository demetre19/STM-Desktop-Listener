#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
APP="$DIST/STM Desktop Listener.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
PKG_NAME="STM-Desktop-Listener-Mac-v$VERSION"
PKG_ROOT="$DIST/$PKG_NAME"
ZIP="$DIST/$PKG_NAME.zip"
DMG="$DIST/$PKG_NAME.dmg"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Install Apple Command Line Tools first:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

"$ROOT/build.sh"

rm -rf "$DIST"/STM-Desktop-Listener-*.zip "$DIST"/STM-Desktop-Listener-*.dmg "$DIST"/STM-Desktop-Listener-Mac-v*/ "$DIST/STM-Desktop-Listener-Mac"
mkdir -p "$PKG_ROOT"
cp -R "$APP" "$PKG_ROOT/"
cp "$ROOT/README.md" "$PKG_ROOT/README.md"
cp "$ROOT/LLM-INSTALL.md" "$PKG_ROOT/LLM-INSTALL.md"
cp "$ROOT/credentials.example.json" "$PKG_ROOT/credentials.example.json"
cp "$ROOT/install-native-host.sh" "$PKG_ROOT/install-native-host.sh"

cat > "$PKG_ROOT/install.command" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/STM Desktop Listener.app"
DEST="/Applications/STM Desktop Listener.app"

if [[ ! -d "$APP" ]]; then
  echo "STM Desktop Listener.app was not found next to this installer." >&2
  exit 1
fi

osascript -e 'quit app "STM Desktop Listener"' >/dev/null 2>&1 || true

install_app() {
  if rm -rf "$DEST" 2>/dev/null && cp -R "$APP" "$DEST" 2>/dev/null; then
    return 0
  fi
  echo "Administrator permission is needed to copy into /Applications."
  sudo rm -rf "$DEST"
  sudo cp -R "$APP" "$DEST"
}

install_app

# This package is intended for trusted direct sharing, not App Store distribution.
# Remove download quarantine so macOS can launch the app while preserving its signature.
xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || sudo xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true

open "$DEST"
"$DIR/install-native-host.sh" >/dev/null 2>&1 || true
echo ""
echo "Installed STM Desktop Listener to: $DEST"
echo "Use the menu bar icon to import credentials, grant permissions, and test actions."
read -r -p "Press Return to close this window..." _
INSTALLER
chmod +x "$PKG_ROOT/install.command"

(
  cd "$DIST"
  ditto -c -k --sequesterRsrc --keepParent "$PKG_NAME" "$PKG_NAME.zip"
)

if command -v hdiutil >/dev/null 2>&1; then
  hdiutil create -volname "STM Desktop Listener" -srcfolder "$PKG_ROOT" -ov -format UDZO "$DMG" >/dev/null
fi

echo "Packaged: $ZIP"
[[ -f "$DMG" ]] && echo "Packaged: $DMG"
