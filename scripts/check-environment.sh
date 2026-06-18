#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

FAILURES=0

section() {
  printf '\n=== %s ===\n' "$1"
}

check_command() {
  local command_name="$1"
  local required="${2:-required}"

  if command -v "$command_name" >/dev/null 2>&1; then
    printf '%-18s %s\n' "$command_name" "$(command -v "$command_name")"
    return 0
  fi

  if [ "$required" = "required" ]; then
    echo "ERROR: required command not found: $command_name"
    FAILURES=$((FAILURES + 1))
  else
    echo "Optional command not found: $command_name"
  fi

  return 1
}

section "System"

uname -a

if command -v sw_vers >/dev/null 2>&1; then
  sw_vers
fi

section "Repository"

echo "Root: $ROOT_DIR"

test -d "$ROOT_DIR/.git" ||
  echo "Warning: repository metadata was not found."

test -f "$ROOT_DIR/macos-app/Webcamera/Webcamera.xcodeproj/project.pbxproj" ||
  {
    echo "ERROR: macOS Xcode project was not found."
    FAILURES=$((FAILURES + 1))
  }

test -f "$ROOT_DIR/android-app/gradlew" ||
  {
    echo "ERROR: Android Gradle wrapper was not found."
    FAILURES=$((FAILURES + 1))
  }

section "Git"

if check_command git; then
  git --version
fi

section "Xcode and Swift"

if check_command xcode-select; then
  xcode-select -p || true
fi

if check_command xcodebuild; then
  xcodebuild -version
fi

if check_command swift; then
  swift --version
fi

section "Java"

if check_command java; then
  java -version
fi

section "Android SDK"

ANDROID_SDK_PATH="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"

echo "ANDROID_HOME=${ANDROID_HOME:-}"
echo "ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-}"
echo "Resolved SDK path: $ANDROID_SDK_PATH"

if [ -d "$ANDROID_SDK_PATH" ]; then
  echo "Android SDK directory exists."
else
  echo "ERROR: Android SDK directory was not found."
  FAILURES=$((FAILURES + 1))
fi

section "ADB"

ADB_PATH=""

for candidate in \
  "$(command -v adb 2>/dev/null || true)" \
  "/opt/homebrew/bin/adb" \
  "/usr/local/bin/adb" \
  "$HOME/Library/Android/sdk/platform-tools/adb" \
  "$HOME/Android/Sdk/platform-tools/adb"
do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    ADB_PATH="$candidate"
    break
  fi
done

if [ -z "$ADB_PATH" ]; then
  echo "ERROR: adb was not found."
  FAILURES=$((FAILURES + 1))
else
  echo "ADB: $ADB_PATH"

  ADB_LIBUSB=0 "$ADB_PATH" version

  echo
  echo "Connected devices:"

  ADB_LIBUSB=0 "$ADB_PATH" devices -l || true
fi

section "Gradle wrapper"

if [ -f "$ROOT_DIR/android-app/gradlew" ]; then
  chmod +x "$ROOT_DIR/android-app/gradlew"

  (
    cd "$ROOT_DIR/android-app"
    ./gradlew --version
  )
fi

section "Optional tools"

if check_command ffmpeg optional; then
  ffmpeg -version | head -n 1
fi

if check_command ffprobe optional; then
  ffprobe -version | head -n 1
fi

check_command code optional || true

section "Result"

if [ "$FAILURES" -ne 0 ]; then
  echo "Environment check failed with $FAILURES problem(s)."
  exit 1
fi

echo "Environment check passed."
