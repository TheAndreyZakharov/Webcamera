#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PROJECT="$ROOT_DIR/macos-app/Webcamera/Webcamera.xcodeproj"
DERIVED_DATA="$ROOT_DIR/macos-app/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug/Webcamera.app"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "Error: xcodebuild is not available."
    exit 1
fi

if [ ! -d "$PROJECT" ]; then
    echo "Error: Xcode project was not found:"
    echo "$PROJECT"
    exit 1
fi

echo "Building Webcamera..."

rm -rf "$DERIVED_DATA"

xcodebuild \
    -project "$PROJECT" \
    -scheme Webcamera \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

if [ ! -d "$APP" ]; then
    echo "Error: Webcamera.app was not created:"
    echo "$APP"
    exit 1
fi

echo
echo "Starting Webcamera..."

open "$APP"
