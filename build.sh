#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p "$ROOT/dist"
LOCK_DIR="$ROOT/dist/.build.lock"
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  sleep 0.5
done
trap 'rm -rf "$LOCK_DIR"' EXIT

APP="$ROOT/dist/STM Desktop Listener.app"
BIN="$APP/Contents/MacOS/STM Desktop Listener"
TMP="$ROOT/dist/build-tmp"
SHERPA_DIR="$ROOT/Vendor/sherpa-onnx"
SHERPA_LIB="$SHERPA_DIR/libsherpa-onnx.a"
PARAKEET_BRIDGE_HEADER="$ROOT/Sources/ParakeetBridge.h"
ONNXRUNTIME_DIR="$ROOT/Vendor/onnxruntime"
ONNXRUNTIME_LIB="$ONNXRUNTIME_DIR/libonnxruntime.1.27.0.dylib"
WEBP_DIR="$ROOT/Vendor/webp"
WEBP_LIB="$WEBP_DIR/libwebp.a"
SHARPYUV_LIB="$WEBP_DIR/libsharpyuv.a"
ONNXRUNTIME_BUNDLE_NAME="libonnxruntime.1.dylib"
PUNCTUATION_SOURCE="$ROOT/Resources/PunctuationModel"
PUNCTUATION_MODEL_SHA256="9d611f445fe4a46186080fe161be6059d87d72eb88d3a8cb00c1a06e83a6067e"
PUNCTUATION_VOCAB_SHA256="e118b7ad88c54db562517df49e1cffd4836d166c34fb190fd311d7f34eb238f5"

rm -rf "$APP" "$TMP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$TMP"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

ICON_SRC="$ROOT/assets/AppIcon.png"
ICONSET="$TMP/AppIcon.iconset"
if [[ -f "$ICON_SRC" ]]; then
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  sips -z 16 16 "$ICON_SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.png"
fi

SHUTTER_SRC="$ROOT/assets/camera-shutter.mp3"
if [[ -f "$SHUTTER_SRC" ]]; then
  cp "$SHUTTER_SRC" "$APP/Contents/Resources/camera-shutter.mp3"
fi

INSTALLER_SRC="$ROOT/install-native-host.sh"
if [[ -f "$INSTALLER_SRC" ]]; then
  cp "$INSTALLER_SRC" "$APP/Contents/Resources/install-native-host.sh"
fi
if [[ -f "$SHERPA_DIR/LICENSE" ]]; then
  cp "$SHERPA_DIR/LICENSE" "$APP/Contents/Resources/sherpa-onnx-LICENSE"
fi
cp "$ONNXRUNTIME_LIB" "$APP/Contents/Frameworks/$ONNXRUNTIME_BUNDLE_NAME"
cp "$ONNXRUNTIME_DIR/LICENSE" "$APP/Contents/Resources/onnxruntime-LICENSE"
cp "$WEBP_DIR/LICENSE" "$APP/Contents/Resources/webp-LICENSE"
cp "$ONNXRUNTIME_DIR/ThirdPartyNotices.txt" "$APP/Contents/Resources/onnxruntime-ThirdPartyNotices.txt"
PUNCTUATION_MODEL_ACTUAL="$(shasum -a 256 "$PUNCTUATION_SOURCE/model.int8.onnx" | cut -d ' ' -f 1)"
PUNCTUATION_VOCAB_ACTUAL="$(shasum -a 256 "$PUNCTUATION_SOURCE/bpe.vocab" | cut -d ' ' -f 1)"
if [[ "$PUNCTUATION_MODEL_ACTUAL" != "$PUNCTUATION_MODEL_SHA256" || "$PUNCTUATION_VOCAB_ACTUAL" != "$PUNCTUATION_VOCAB_SHA256" ]]; then
  echo "Punctuation model integrity verification failed." >&2
  exit 1
fi
mkdir -p "$APP/Contents/Resources/PunctuationModel"
cp "$PUNCTUATION_SOURCE/model.int8.onnx" "$APP/Contents/Resources/PunctuationModel/model.int8.onnx"
cp "$PUNCTUATION_SOURCE/bpe.vocab" "$APP/Contents/Resources/PunctuationModel/bpe.vocab"
cp "$PUNCTUATION_SOURCE/MODEL_METADATA.txt" "$APP/Contents/Resources/PunctuationModel/MODEL_METADATA.txt"

FRAMEWORKS=(
  -framework Cocoa
  -framework Accelerate
  -framework CoreML
  -framework CryptoKit
  -framework AVFoundation
  -framework Carbon
  -framework ApplicationServices
  -framework CoreGraphics
  -framework CoreImage
  -framework CoreMedia
  -framework CoreText
  -framework ScreenCaptureKit
  -framework ServiceManagement
  -framework UserNotifications
  -framework Vision
)

build_arch() {
  local arch="$1"
  local out="$2"
  local bridge_object="$TMP/ParakeetBridge-$arch.o"
  local webp_bridge_object="$TMP/WebPBridge-$arch.o"
  MACOSX_DEPLOYMENT_TARGET=14.0 xcrun clang \
    -arch "$arch" \
    -mmacosx-version-min=14.0 \
    -I"$SHERPA_DIR" \
    -c "$ROOT/Sources/ParakeetBridge.c" \
    -o "$bridge_object"
  MACOSX_DEPLOYMENT_TARGET=14.0 xcrun clang \
    -arch "$arch" \
    -mmacosx-version-min=14.0 \
    -c "$ROOT/Sources/WebPBridge.c" \
    -o "$webp_bridge_object"
  MACOSX_DEPLOYMENT_TARGET=14.0 swiftc Sources/*.swift \
    "$bridge_object" \
    "$webp_bridge_object" \
    "$SHERPA_LIB" \
    "$ONNXRUNTIME_LIB" \
    "$WEBP_LIB" \
    "$SHARPYUV_LIB" \
    -Xlinker -rpath \
    -Xlinker "@executable_path/../Frameworks" \
    -lc++ \
    -import-objc-header "$PARAKEET_BRIDGE_HEADER" \
    -debug-prefix-map "$ROOT=." \
    -file-prefix-map "$ROOT=." \
    -target "$arch-apple-macos14.0" \
    -o "$out" \
    "${FRAMEWORKS[@]}"
}

# sherpa-onnx 1.13.4 is built against ONNX Runtime 1.27.0, whose official
# macOS package is arm64-only. Keep the universal path for a future matching runtime.
ONNXRUNTIME_ARCHS="$(lipo -archs "$ONNXRUNTIME_LIB")"
if [[ "${UNIVERSAL:-1}" == "1" && "$ONNXRUNTIME_ARCHS" == *"x86_64"* ]] && command -v lipo >/dev/null 2>&1 \
  && build_arch arm64 "$TMP/STM Desktop Listener-arm64" \
  && build_arch x86_64 "$TMP/STM Desktop Listener-x86_64"; then
  lipo -create "$TMP/STM Desktop Listener-arm64" "$TMP/STM Desktop Listener-x86_64" -output "$BIN"
  echo "Built universal binary: arm64 + x86_64"
else
  BUILD_ARCH="${BUILD_ARCH:-$(uname -m)}"
  echo "Building current requested architecture: $BUILD_ARCH"
  build_arch "$BUILD_ARCH" "$BIN"
fi

chmod +x "$BIN"
rm -rf "$TMP"

if command -v codesign >/dev/null 2>&1; then
  SIGN_IDENTITY=""
  for CANDIDATE in "STM Desktop Listener Local Code Signing" "STM Transcriber Local Code Signing"; do
    if security find-identity -v -p codesigning 2>/dev/null | grep -F "$CANDIDATE" >/dev/null; then
      SIGN_IDENTITY="$CANDIDATE"
      break
    fi
  done
  if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/$ONNXRUNTIME_BUNDLE_NAME" >/dev/null
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP" >/dev/null
  else
    codesign --force --sign - "$APP/Contents/Frameworks/$ONNXRUNTIME_BUNDLE_NAME" >/dev/null
    codesign --force --deep --sign - "$APP" >/dev/null
  fi
fi

echo "Built: $APP"
file "$BIN" 2>/dev/null || true
