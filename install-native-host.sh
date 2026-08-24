#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
HOST_NAME="com.stm.desktop_listener"
EXTENSION_ID="${1:-${STM_EXTENSION_ID:-phhmonggcijfgpcenlbhaeoepiadnpjj}}"
INSTALLED_APP="/Applications/STM Desktop Listener.app/Contents/MacOS/STM Desktop Listener"
BUNDLED_APP="$ROOT/../MacOS/STM Desktop Listener"
LOCAL_APP="$ROOT/dist/STM Desktop Listener.app/Contents/MacOS/STM Desktop Listener"

if [[ -x "$INSTALLED_APP" ]]; then
  HOST_PATH="$INSTALLED_APP"
elif [[ -x "$BUNDLED_APP" ]]; then
  HOST_PATH="$(cd "$(dirname "$BUNDLED_APP")" && pwd)/STM Desktop Listener"
elif [[ -x "$LOCAL_APP" ]]; then
  HOST_PATH="$LOCAL_APP"
else
  echo "STM Desktop Listener binary was not found. Build or install the app first." >&2
  exit 1
fi

write_manifest() {
  local dir="$1"
  mkdir -p "$dir"
  local manifest="$dir/$HOST_NAME.json"
  cat > "$manifest" <<JSON
{
  "name": "$HOST_NAME",
  "description": "STM Desktop Listener native payload bridge",
  "path": "$HOST_PATH",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXTENSION_ID/"
  ]
}
JSON
  echo "Installed native messaging host: $manifest"
}

write_manifest "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
write_manifest "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
