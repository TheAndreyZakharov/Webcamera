#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

ANDROID_DIR="$ROOT_DIR/android-app"
ANDROID_GRADLEW="$ANDROID_DIR/gradlew"

MACOS_PROJECT="$ROOT_DIR/macos-app/Webcamera/Webcamera.xcodeproj"

RELEASE_DIR="$ROOT_DIR/release"
DERIVED_DATA_DIR="${TMPDIR:-/tmp}/WebcameraReleaseDerivedData"

APP_NAME="Webcamera"
SCHEME_NAME="Webcamera"

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
  echo "Usage:"
  echo "  $0 VERSION"
  echo
  echo "Example:"
  echo "  $0 1.0.0"
  exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}([._-][A-Za-z0-9]+)*$ ]]; then
  echo "Error: invalid version:"
  echo "$VERSION"
  exit 1
fi

ANDROID_APK_SOURCE="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"

ANDROID_APK_OUTPUT="$RELEASE_DIR/Webcamera-Android-$VERSION.apk"

MACOS_APP="$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME.app"

MACOS_ZIP="$RELEASE_DIR/Webcamera-macOS-$VERSION.zip"

CHECKSUM_FILE="$RELEASE_DIR/SHA256SUMS.txt"

if [ ! -f "$ANDROID_GRADLEW" ]; then
  echo "Error: Android Gradle wrapper was not found:"
  echo "$ANDROID_GRADLEW"
  exit 1
fi

if [ ! -f "$MACOS_PROJECT/project.pbxproj" ]; then
  echo "Error: macOS Xcode project was not found:"
  echo "$MACOS_PROJECT"
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild is not available."
  exit 1
fi

if ! command -v codesign >/dev/null 2>&1; then
  echo "Error: codesign is not available."
  exit 1
fi

if ! command -v ditto >/dev/null 2>&1; then
  echo "Error: ditto is not available."
  exit 1
fi

echo "Building Webcamera release:"
echo "$VERSION"

echo
echo "Cleaning release directories..."

rm -rf "$RELEASE_DIR"
rm -rf "$DERIVED_DATA_DIR"

mkdir -p "$RELEASE_DIR"

echo
echo "Building Android debug APK..."

chmod +x "$ANDROID_GRADLEW"

(
  cd "$ANDROID_DIR"

  ./gradlew \
    --no-daemon \
    clean \
    assembleDebug
)

if [ ! -f "$ANDROID_APK_SOURCE" ]; then
  echo "Error: Android APK was not created:"
  echo "$ANDROID_APK_SOURCE"
  exit 1
fi

cp \
  "$ANDROID_APK_SOURCE" \
  "$ANDROID_APK_OUTPUT"

echo
echo "Android artifact:"
echo "$ANDROID_APK_OUTPUT"

echo
echo "Building macOS Release application..."

xcodebuild \
  -project "$MACOS_PROJECT" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  clean build

if [ ! -d "$MACOS_APP" ]; then
  echo "Error: macOS application was not created:"
  echo "$MACOS_APP"
  exit 1
fi

echo
echo "Applying ad-hoc signature..."

codesign \
  --force \
  --deep \
  --sign - \
  "$MACOS_APP"

echo
echo "Verifying macOS signature..."

codesign \
  --verify \
  --deep \
  --strict \
  "$MACOS_APP"

echo
echo "Creating macOS archive..."

ditto \
  -c \
  -k \
  --sequesterRsrc \
  --keepParent \
  "$MACOS_APP" \
  "$MACOS_ZIP"

if [ ! -f "$MACOS_ZIP" ]; then
  echo "Error: macOS archive was not created:"
  echo "$MACOS_ZIP"
  exit 1
fi

echo
echo "Creating SHA-256 checksums..."

(
  cd "$RELEASE_DIR"

  shasum \
    -a 256 \
    "$(basename "$ANDROID_APK_OUTPUT")" \
    "$(basename "$MACOS_ZIP")" \
    > "$(basename "$CHECKSUM_FILE")"
)

rm -rf "$DERIVED_DATA_DIR"

echo
echo "Release files:"

find "$RELEASE_DIR" \
  -maxdepth 1 \
  -type f \
  -print |
  sort

echo
echo "Checksums:"

cat "$CHECKSUM_FILE"

echo
echo "Release build completed."
echo
echo "Important:"
echo "  Android artifact is currently debug-signed."
echo "  macOS artifact is currently ad-hoc signed."
echo "  Public distribution requires proper platform signing."
