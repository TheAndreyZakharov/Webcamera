#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/android-app"
APK="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"

cd "$ANDROID_DIR"

echo "Building Android application..."
./gradlew clean assembleDebug

if [ ! -f "$APK" ]; then
    echo "APK was not created: $APK"
    exit 1
fi

echo
echo "Checking connected devices..."
ADB_LIBUSB=0 adb devices -l

echo
echo "Installing Webcamera..."
ADB_LIBUSB=0 adb install -r "$APK"

echo
echo "Installation complete."