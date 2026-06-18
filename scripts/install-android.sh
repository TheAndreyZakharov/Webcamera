#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

ANDROID_DIR="$ROOT_DIR/android-app"
GRADLEW="$ANDROID_DIR/gradlew"

APK="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"

DEVICE_SERIAL="${1:-}"

find_adb() {
  local candidate

  for candidate in \
    "$(command -v adb 2>/dev/null || true)" \
    "/opt/homebrew/bin/adb" \
    "/usr/local/bin/adb" \
    "$HOME/Library/Android/sdk/platform-tools/adb" \
    "$HOME/Android/Sdk/platform-tools/adb"
  do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

ADB="$(find_adb || true)"

if [ -z "$ADB" ]; then
  echo "Error: adb was not found."
  exit 1
fi

if [ ! -f "$GRADLEW" ]; then
  echo "Error: Gradle wrapper was not found:"
  echo "$GRADLEW"
  exit 1
fi

chmod +x "$GRADLEW"

echo "Building Android application..."

(
  cd "$ANDROID_DIR"

  ./gradlew \
    --no-daemon \
    clean \
    assembleDebug
)

if [ ! -f "$APK" ]; then
  echo "Error: APK was not created:"
  echo "$APK"
  exit 1
fi

echo
echo "Connected Android devices:"

ADB_LIBUSB=0 "$ADB" devices -l

if [ -z "$DEVICE_SERIAL" ]; then
  mapfile -t DEVICES < <(
    ADB_LIBUSB=0 "$ADB" devices |
      awk 'NR > 1 && $2 == "device" { print $1 }'
  )

  if [ "${#DEVICES[@]}" -eq 0 ]; then
    echo "Error: no online Android device was found."
    exit 1
  fi

  if [ "${#DEVICES[@]}" -gt 1 ]; then
    echo "Error: more than one Android device is connected."
    echo
    echo "Run:"
    echo "  $0 DEVICE_SERIAL"
    exit 1
  fi

  DEVICE_SERIAL="${DEVICES[0]}"
fi

DEVICE_STATE="$(
  ADB_LIBUSB=0 "$ADB" \
    -s "$DEVICE_SERIAL" \
    get-state 2>/dev/null || true
)"

if [ "$DEVICE_STATE" != "device" ]; then
  echo "Error: Android device is not online:"
  echo "$DEVICE_SERIAL"
  exit 1
fi

echo
echo "Installing Webcamera on:"
echo "$DEVICE_SERIAL"

ADB_LIBUSB=0 "$ADB" \
  -s "$DEVICE_SERIAL" \
  install \
  -r \
  "$APK"

echo
echo "Starting Webcamera activity..."

ADB_LIBUSB=0 "$ADB" \
  -s "$DEVICE_SERIAL" \
  shell \
  am \
  start \
  -n \
  com.theandreyzakharov.webcamera.debug/com.theandreyzakharov.webcamera.ui.MainActivity

echo
echo "Android installation completed."
