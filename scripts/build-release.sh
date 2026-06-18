#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

ANDROID_DIR="$ROOT_DIR/android-app"
MACOS_PROJECT="$ROOT_DIR/macos-app/Webcamera/Webcamera.xcodeproj"

RELEASE_DIR="$ROOT_DIR/release"
DERIVED_DATA_DIR="$ROOT_DIR/.release-derived-data"

APP_NAME="Webcamera"
MACOS_SCHEME="Webcamera"

VERSION="${1:-1.0.0}"

ANDROID_OUTPUT="$RELEASE_DIR/Webcamera-Android-$VERSION.apk"
MACOS_OUTPUT="$RELEASE_DIR/Webcamera-macOS-$VERSION.zip"

echo "Building Webcamera $VERSION"
echo

rm -rf "$RELEASE_DIR"
rm -rf "$DERIVED_DATA_DIR"

mkdir -p "$RELEASE_DIR"

echo "Building Android application..."

cd "$ANDROID_DIR"

./gradlew clean assembleDebug

ANDROID_APK="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"

if [ ! -f "$ANDROID_APK" ]; then
    echo "Android APK was not created:"
    echo "$ANDROID_APK"
    exit 1
fi

cp "$ANDROID_APK" "$ANDROID_OUTPUT"

echo "Android artifact:"
echo "$ANDROID_OUTPUT"
echo

if [ ! -d "$MACOS_PROJECT" ]; then
    echo "macOS Xcode project has not been created yet:"
    echo "$MACOS_PROJECT"
    echo
    echo "Android artifact was created successfully."
    exit 0
fi

echo "Building macOS application..."

xcodebuild \
    -project "$MACOS_PROJECT" \
    -scheme "$MACOS_SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

MACOS_APP="$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$MACOS_APP" ]; then
    echo "macOS application bundle was not created:"
    echo "$MACOS_APP"
    exit 1
fi

echo "Applying ad-hoc signature..."

codesign \
    --force \
    --deep \
    --sign - \
    "$MACOS_APP"

codesign \
    --verify \
    --deep \
    --strict \
    "$MACOS_APP"

echo "Creating macOS archive..."

ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "$MACOS_APP" \
    "$MACOS_OUTPUT"

rm -rf "$DERIVED_DATA_DIR"

echo
echo "Release artifacts:"
echo

find "$RELEASE_DIR" \
    -maxdepth 1 \
    -type f \
    -print

echo
echo "Build complete."
