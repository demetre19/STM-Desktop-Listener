#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
APP="$DIST/STM Desktop Listener.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
PKG_NAME="STM-Desktop-Listener-Mac-arm64-v$VERSION"
PKG_ROOT="$DIST/$PKG_NAME"
ZIP="$DIST/$PKG_NAME.zip"
DMG="$DIST/$PKG_NAME.dmg"

for command_name in swiftc hdiutil lipo; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required packaging tool not found: $command_name" >&2
    [[ "$command_name" == "swiftc" ]] && echo "Install Apple Command Line Tools with: xcode-select --install" >&2
    exit 1
  fi
done

BUILD_ARCH=arm64 UNIVERSAL=0 "$ROOT/build.sh"

verify_arm64_macho() {
  local path="$1"
  local archs
  archs="$(lipo -archs "$path")"
  if [[ "$archs" != "arm64" ]]; then
    echo "Expected an arm64-only Mach-O file, found '$archs': $path" >&2
    exit 1
  fi
}

verify_arm64_macho "$APP/Contents/MacOS/STM Desktop Listener"

while IFS= read -r -d '' candidate; do
  if file "$candidate" | grep -q 'Mach-O'; then
    verify_arm64_macho "$candidate"
  fi
done < <(find "$APP/Contents/Frameworks" -type f -name '*.dylib' -print0)

rm -rf "$DIST"/STM-Desktop-Listener-*.zip "$DIST"/STM-Desktop-Listener-*.dmg "$DIST"/STM-Desktop-Listener-Mac-v*/ "$DIST"/STM-Desktop-Listener-Mac-arm64-v*/ "$DIST/STM-Desktop-Listener-Mac" "$DIST/SHA256SUMS.txt"
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

hdiutil create -volname "STM Desktop Listener" -srcfolder "$PKG_ROOT" -ov -format UDZO "$DMG" >/dev/null

echo "Packaged: $ZIP"
echo "Packaged: $DMG"
