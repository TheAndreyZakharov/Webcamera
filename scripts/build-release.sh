#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

ANDROID_DIR="$ROOT_DIR/android-app"
MACOS_PROJECT="$ROOT_DIR/macos-app/Webcamera/Webcamera.xcodeproj"

RELEASE_DIR="$ROOT_DIR/release"
DERIVED_DATA_DIR="$ROOT_DIR/macos-app/ReleaseDerivedData"

APP_NAME="Webcamera"
SCHEME_NAME="Webcamera"

VERSION="${1:-1.0.0}"

ANDROID_APK_SOURCE="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
ANDROID_APK_OUTPUT="$RELEASE_DIR/Webcamera-Android-$VERSION.apk"

MACOS_APP="$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME.app"
MACOS_ZIP="$RELEASE_DIR/Webcamera-macOS-$VERSION.zip"

echo "Building Webcamera release $VERSION"
echo

rm -rf "$RELEASE_DIR"
rm -rf "$DERIVED_DATA_DIR"

mkdir -p "$RELEASE_DIR"

if [ -f "$ANDROID_DIR/gradlew" ]; then
    echo "Building Android application..."

    cd "$ANDROID_DIR"

    ./gradlew clean assembleDebug

    if [ ! -f "$ANDROID_APK_SOURCE" ]; then
        echo "Error: Android APK was not created:"
        echo "$ANDROID_APK_SOURCE"
        exit 1
    fi

    cp "$ANDROID_APK_SOURCE" "$ANDROID_APK_OUTPUT"

    echo "Android artifact created:"
    echo "$ANDROID_APK_OUTPUT"
    echo
else
    echo "Android Gradle project is not ready yet."
    echo "Skipping Android build."
    echo
fi

if [ ! -d "$MACOS_PROJECT" ]; then
    echo "Error: macOS Xcode project was not found:"
    echo "$MACOS_PROJECT"
    exit 1
fi

echo "Building macOS application..."

xcodebuild \
    -project "$MACOS_PROJECT" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

if [ ! -d "$MACOS_APP" ]; then
    echo "Error: macOS application was not created:"
    echo "$MACOS_APP"
    exit 1
fi

echo "Applying ad-hoc signature..."

codesign \
    --force \
    --deep \
    --sign - \
    "$MACOS_APP"

echo "Verifying signature..."

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
    "$MACOS_ZIP"

rm -rf "$DERIVED_DATA_DIR"

echo
echo "Release files:"
echo

find "$RELEASE_DIR" \
    -maxdepth 1 \
    -type f \
    -print

echo
echo "Release build completed."
