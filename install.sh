#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/STM Desktop Listener.app"
DEST="/Applications/STM Desktop Listener.app"

if [[ ! -x "$ROOT/build.sh" ]]; then
  echo "Missing build.sh. Run this from the STM Desktop Listener project folder." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Install Apple Command Line Tools first:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

"$ROOT/build.sh"

stop_existing_instances() {
  osascript -e 'quit app "STM Desktop Listener"' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -x "STM Desktop Listener" >/dev/null 2>&1; then
      return
    fi
    sleep 0.1
  done
  pkill -TERM -x "STM Desktop Listener" >/dev/null 2>&1 || true
  sleep 0.5
  pkill -KILL -x "STM Desktop Listener" >/dev/null 2>&1 || true
}

stop_existing_instances

install_app() {
  if rm -rf "$DEST" 2>/dev/null && cp -R "$APP" "$DEST" 2>/dev/null; then
    return 0
  fi
  echo "Administrator permission is needed to copy into /Applications."
  sudo rm -rf "$DEST"
  sudo cp -R "$APP" "$DEST"
}

install_app
xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || sudo xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true
stop_existing_instances

echo "Installed: $DEST"
"$ROOT/install-native-host.sh" >/dev/null 2>&1 || true
open "$DEST"
