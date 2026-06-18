#!/usr/bin/env bash

set -euo pipefail

CONTROL_PORT=27283
VIDEO_PORT=27284

echo "Restarting ADB..."
pkill -f adb 2>/dev/null || true
ADB_LIBUSB=0 adb start-server

echo
echo "Connected devices:"
ADB_LIBUSB=0 adb devices -l

DEVICE_COUNT="$(
    ADB_LIBUSB=0 adb devices |
    awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }'
)"

if [ "$DEVICE_COUNT" -ne 1 ]; then
    echo "Expected exactly one connected Android device."
    exit 1
fi

echo
echo "Testing shell..."
ADB_LIBUSB=0 adb shell echo connected

echo
echo "Creating forwarding rules..."
ADB_LIBUSB=0 adb forward --remove-all
ADB_LIBUSB=0 adb forward \
    "tcp:$CONTROL_PORT" \
    "tcp:$CONTROL_PORT"
ADB_LIBUSB=0 adb forward \
    "tcp:$VIDEO_PORT" \
    "tcp:$VIDEO_PORT"

echo
echo "Active forwarding rules:"
ADB_LIBUSB=0 adb forward --list

echo
echo "Monitoring ADB stability for 30 seconds..."

for i in $(seq 1 30); do
    if ! ADB_LIBUSB=0 adb get-state >/dev/null 2>&1; then
        echo "ADB connection was lost on iteration $i."
        exit 1
    fi

    printf "."
    sleep 1
done

echo
echo
echo "USB transport test passed."