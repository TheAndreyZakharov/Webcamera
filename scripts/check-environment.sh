#!/usr/bin/env bash

set -u

echo "=== SYSTEM ==="
uname -m
sw_vers

echo
echo "=== GIT ==="
git --version

echo
echo "=== VS CODE ==="
code --version

echo
echo "=== XCODE ==="
xcode-select -p
xcodebuild -version
swift --version

echo
echo "=== JAVA ==="
java -version

echo
echo "=== GRADLE ==="
gradle --version

echo
echo "=== ANDROID SDK ==="
echo "ANDROID_HOME=${ANDROID_HOME:-}"
echo "ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-}"
sdkmanager --version

echo
echo "=== ADB ==="
which adb
adb version
ADB_LIBUSB=0 adb devices -l

echo
echo "=== FFMPEG ==="
ffmpeg -version | head -n 1
