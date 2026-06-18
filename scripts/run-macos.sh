#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/macos-app/Webcamera/Webcamera.xcodeproj"

if [ ! -d "$PROJECT" ]; then
    echo "Webcamera.xcodeproj has not been created yet."
    echo "Create the macOS application project before using this script."
    exit 1
fi

open "$PROJECT"