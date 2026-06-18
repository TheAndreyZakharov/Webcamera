#!/usr/bin/env bash

set -euo pipefail

CONTROL_PORT=27283
MEDIA_PORT=27284

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

echo "ADB:"
echo "$ADB"

echo
echo "Starting ADB server..."

ADB_LIBUSB=0 "$ADB" start-server

echo
echo "Connected devices:"

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

echo
echo "Using device:"
echo "$DEVICE_SERIAL"

DEVICE_STATE="$(
  ADB_LIBUSB=0 "$ADB" \
    -s "$DEVICE_SERIAL" \
    get-state 2>/dev/null || true
)"

if [ "$DEVICE_STATE" != "device" ]; then
  echo "Error: device is not online."
  exit 1
fi

echo
echo "Testing shell access..."

SHELL_RESULT="$(
  ADB_LIBUSB=0 "$ADB" \
    -s "$DEVICE_SERIAL" \
    shell \
    echo connected |
    tr -d '\r'
)"

if [ "$SHELL_RESULT" != "connected" ]; then
  echo "Error: ADB shell test failed."
  exit 1
fi

echo "Shell access works."

echo
echo "Removing stale Webcamera forwarding rules..."

ADB_LIBUSB=0 "$ADB" \
  -s "$DEVICE_SERIAL" \
  forward \
  --remove \
  "tcp:$CONTROL_PORT" \
  2>/dev/null ||
  true

ADB_LIBUSB=0 "$ADB" \
  -s "$DEVICE_SERIAL" \
  forward \
  --remove \
  "tcp:$MEDIA_PORT" \
  2>/dev/null ||
  true

echo
echo "Creating Webcamera forwarding rules..."

ADB_LIBUSB=0 "$ADB" \
  -s "$DEVICE_SERIAL" \
  forward \
  "tcp:$CONTROL_PORT" \
  "tcp:$CONTROL_PORT"

ADB_LIBUSB=0 "$ADB" \
  -s "$DEVICE_SERIAL" \
  forward \
  "tcp:$MEDIA_PORT" \
  "tcp:$MEDIA_PORT"

echo
echo "Active forwarding rules:"

ADB_LIBUSB=0 "$ADB" forward --list

FORWARD_LIST="$(
  ADB_LIBUSB=0 "$ADB" forward --list
)"

if ! grep -Fq \
  "$DEVICE_SERIAL tcp:$CONTROL_PORT tcp:$CONTROL_PORT" \
  <<<"$FORWARD_LIST"
then
  echo "Error: control forwarding rule is missing."
  exit 1
fi

if ! grep -Fq \
  "$DEVICE_SERIAL tcp:$MEDIA_PORT tcp:$MEDIA_PORT" \
  <<<"$FORWARD_LIST"
then
  echo "Error: media forwarding rule is missing."
  exit 1
fi

echo
echo "Testing ADB stability for 15 seconds..."

for iteration in $(seq 1 15); do
  CURRENT_STATE="$(
    ADB_LIBUSB=0 "$ADB" \
      -s "$DEVICE_SERIAL" \
      get-state 2>/dev/null || true
  )"

  if [ "$CURRENT_STATE" != "device" ]; then
    echo
    echo "Error: ADB connection was lost on iteration $iteration."
    exit 1
  fi

  printf '.'
  sleep 1
done

echo
echo
echo "USB transport test passed."

echo
echo "Control endpoint:"
echo "127.0.0.1:$CONTROL_PORT"

echo
echo "Media endpoint:"
echo "127.0.0.1:$MEDIA_PORT"
