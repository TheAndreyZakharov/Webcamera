#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PROJECT="$ROOT_DIR/macos-app/Webcamera/Webcamera.xcodeproj"
SCHEME="Webcamera"

DERIVED_DATA="${TMPDIR:-/tmp}/WebcameraDerivedData"
APP="$DERIVED_DATA/Build/Products/Debug/Webcamera.app"

LOG_FILE="${TMPDIR:-/tmp}/webcamera-macos-build.log"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild is not available."
  exit 1
fi

if [ ! -f "$PROJECT/project.pbxproj" ]; then
  echo "Error: Xcode project was not found:"
  echo "$PROJECT"
  exit 1
fi

echo "Project:"
echo "$PROJECT"

echo
echo "Derived Data:"
echo "$DERIVED_DATA"

echo
echo "Cleaning previous build..."

rm -rf "$DERIVED_DATA"
rm -f "$LOG_FILE"

echo
echo "Building Webcamera Debug..."

set +e

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  clean build \
  2>&1 | tee "$LOG_FILE"

BUILD_STATUS="${PIPESTATUS[0]}"

set -e

if [ "$BUILD_STATUS" -ne 0 ]; then
  echo
  echo "Build failed."
  echo
  echo "Compiler errors:"

  grep -nE \
    "error:|BUILD FAILED|SwiftCompile.*failed" \
    "$LOG_FILE" |
    head -n 150 ||
    true

  exit "$BUILD_STATUS"
fi

if [ ! -d "$APP" ]; then
  echo "Error: application bundle was not created:"
  echo "$APP"
  exit 1
fi

echo
echo "Applying ad-hoc signature..."

codesign \
  --force \
  --deep \
  --sign - \
  "$APP"

echo
echo "Launching Webcamera..."

pkill -x Webcamera 2>/dev/null || true

open "$APP"

echo
echo "Webcamera started:"
echo "$APP"
