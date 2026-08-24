#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="${1:-${GITHUB_REF_NAME:-}}"
INFO_PLIST="$ROOT/Info.plist"
DIST="$ROOT/dist"
APP="$DIST/STM Desktop Listener.app"
BINARY="$APP/Contents/MacOS/STM Desktop Listener"
EXPECTED_BUNDLE_ID="com.seotimemachines.stm-desktop-listener"

fail() {
  echo "Release gate failed: $*" >&2
  exit 1
}

[[ -n "$TAG" ]] || fail "a v-prefixed release tag is required"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]] || fail "Info.plist version is not semantic: $VERSION"
[[ "$TAG" == "v$VERSION" ]] || fail "tag $TAG does not match Info.plist version v$VERSION"

"$ROOT/package.sh"

ASSET_STEM="STM-Desktop-Listener-Mac-arm64-v$VERSION"
DMG_NAME="$ASSET_STEM.dmg"
ZIP_NAME="$ASSET_STEM.zip"
CHECKSUMS_NAME="SHA256SUMS.txt"
DMG_PATH="$DIST/$DMG_NAME"
ZIP_PATH="$DIST/$ZIP_NAME"
CHECKSUMS_PATH="$DIST/$CHECKSUMS_NAME"

[[ -s "$DMG_PATH" ]] || fail "missing or empty DMG: $DMG_NAME"
[[ -s "$ZIP_PATH" ]] || fail "missing or empty ZIP: $ZIP_NAME"
[[ -x "$BINARY" ]] || fail "packaged app executable is missing"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
[[ "$APP_VERSION" == "$VERSION" ]] || fail "packaged app version $APP_VERSION does not match $VERSION"
[[ "$APP_BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || fail "unexpected bundle identifier: $APP_BUNDLE_ID"
[[ "$(lipo -archs "$BINARY")" == "arm64" ]] || fail "main executable is not arm64-only"

RELEASE_INPUTS=(
  "$ROOT"/Sources/*.swift
  "$ROOT"/Sources/*.c
  "$ROOT"/Sources/*.h
  "$ROOT/Resources/PunctuationModel/MODEL_METADATA.txt"
  "$ROOT/Info.plist"
  "$ROOT/README.md"
  "$ROOT/LLM-INSTALL.md"
  "$ROOT/credentials.example.json"
  "$ROOT/install-native-host.sh"
  "$DIST/$ASSET_STEM/install.command"
)

scan_files() {
  local label="$1"
  local kind="$2"
  shift 2
  local scan_status=0
  "$ROOT/.github/scripts/scan-release-content.py" "$kind" "$@" || scan_status=$?
  if [[ "$scan_status" == "0" ]]; then
    echo "Release gate failed: $label found in release content; matching values are intentionally hidden." >&2
    exit 1
  fi
  [[ "$scan_status" == "1" ]] || fail "could not complete the $label scan"
}

scan_files "personal path or email" personal "${RELEASE_INPUTS[@]}"
scan_files "credential-like value" credential "${RELEASE_INPUTS[@]}"

EXPECTED_AUTH_PLACEHOLDER="paste-your-jitsi-transcribe-auth-token-here"
EXPECTED_API_PLACEHOLDER="optional-cloudflare-api-token-with-workers-ai-read"
AUTH_PLACEHOLDER="$(plutil -extract authToken raw "$ROOT/credentials.example.json")"
API_PLACEHOLDER="$(plutil -extract cloudflareApiToken raw "$ROOT/credentials.example.json")"
[[ "$AUTH_PLACEHOLDER" == "$EXPECTED_AUTH_PLACEHOLDER" ]] || fail "credentials.example.json contains a non-placeholder auth token"
[[ "$API_PLACEHOLDER" == "$EXPECTED_API_PLACEHOLDER" ]] || fail "credentials.example.json contains a non-placeholder API token"

STRINGS_FILE="$(mktemp "${TMPDIR:-/tmp}/stm-release-strings.XXXXXX")"
trap 'rm -f "$STRINGS_FILE"' EXIT
strings -a "$BINARY" > "$STRINGS_FILE"
scan_files "personal path or email" personal-binary "$STRINGS_FILE"
scan_files "credential-like value" credential "$STRINGS_FILE"

(
  cd "$DIST"
  shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > "$CHECKSUMS_NAME"
  shasum -a 256 -c "$CHECKSUMS_NAME"
)
[[ -s "$CHECKSUMS_PATH" ]] || fail "checksum manifest is empty"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "tag=$TAG"
    echo "version=$VERSION"
    echo "prerelease=$([[ "$VERSION" == *-* ]] && echo true || echo false)"
    echo "dmg_name=$DMG_NAME"
    echo "zip_name=$ZIP_NAME"
    echo "dmg_path=$DMG_PATH"
    echo "zip_path=$ZIP_PATH"
    echo "checksums_path=$CHECKSUMS_PATH"
  } >> "$GITHUB_OUTPUT"
fi

echo "Release assets passed all gates: $DMG_NAME, $ZIP_NAME, $CHECKSUMS_NAME"
