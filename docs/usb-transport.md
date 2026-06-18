# USB Transport

## Overview

Webcamera uses Android Debug Bridge port forwarding as its initial wired transport.

The Android phone connects to the Mac through a USB cable.

The same cable provides:

- device charging;
- ADB communication;
- control-message transport;
- encoded video transport.

No Wi-Fi connection is required for the Android source.

## Runtime topology

    Android camera
          ↓
    H.264 encoder
          ↓
    Android loopback TCP servers
          ↓
    ADB port forwarding
          ↓
    macOS localhost TCP clients
          ↓
    Decoder and preview

## Ports

Webcamera uses two TCP connections:

    Control port: 27283
    Video port:   27284

The Android application listens on:

    127.0.0.1:27283
    127.0.0.1:27284

The macOS application creates matching local forwarding rules:

    adb forward tcp:27283 tcp:27283
    adb forward tcp:27284 tcp:27284

The macOS application then connects to:

    127.0.0.1:27283
    127.0.0.1:27284

## Control connection

The control connection carries newline-delimited JSON messages.

It is used for:

- device identification;
- camera discovery;
- format discovery;
- resolution selection;
- frame-rate selection;
- bitrate selection;
- focus control;
- flash control;
- stream start and stop commands;
- status updates;
- errors;
- keepalive messages.

The control connection carries only small messages.

## Video connection

The video connection carries binary H.264 packets.

It is separated from control messages because video frames:

- are much larger;
- arrive continuously;
- require independent buffering;
- must not delay control commands;
- may need to be restarted without rebuilding the control session.

Each video packet contains:

1. a fixed-size header;
2. an encoded payload.

The packet header includes:

    magic
    protocol version
    flags
    sequence number
    presentation timestamp
    payload length

## Forwarding lifecycle

The macOS application is responsible for ADB forwarding.

At startup, it:

1. locates connected Android devices;
2. verifies that exactly one usable device is available;
3. removes stale Webcamera forwarding rules;
4. creates control and video forwarding rules;
5. starts or verifies the Android application;
6. connects to the local forwarded ports.

After USB reconnection, the application recreates the forwarding rules.

ADB forwarding is not assumed to survive:

- cable disconnection;
- ADB daemon restart;
- phone reboot;
- USB mode change;
- developer-option changes.

## Device selection

The application must not hardcode a phone serial number.

When one Android device is connected, it is selected automatically.

When multiple Android devices are connected, the macOS interface must display them and allow the user to choose one.

ADB commands for a selected device use:

    adb -s DEVICE_SERIAL

The selected serial is used for:

- shell commands;
- application launch;
- port forwarding;
- device information;
- diagnostics.

## USB stability

Before streaming, the macOS application verifies:

    adb get-state
    adb shell echo connected

During streaming, the control connection acts as the main liveness signal.

If the connection fails, the application checks ADB again and attempts to recreate the transport.

The transport manager must distinguish between:

- Android application stopped;
- TCP server stopped;
- ADB device offline;
- USB cable disconnected;
- forwarding rule missing;
- decoder failure.

## Bandwidth

Raw video is not transported over ADB.

The Android application encodes video as H.264 before transmission.

Approximate bitrate is configured according to:

- resolution;
- frame rate;
- camera capabilities;
- encoder capabilities;
- thermal stability;
- USB stability.

The user may request a bitrate, but Android must validate it against the selected encoder.

## 4K transport

A 4K option is shown only when the complete Android pipeline supports it.

The application checks:

- camera output size;
- encoder input size;
- frame-rate compatibility;
- successful encoder configuration;
- successful capture startup.

A camera advertising 4K photography does not automatically guarantee stable 4K real-time H.264 streaming.

If 4K configuration fails, the application reports the error and preserves lower-resolution options.

## Security

The Android TCP servers bind only to the loopback interface.

They are not exposed to Wi-Fi or mobile networks.

The Mac reaches them only through ADB forwarding.

The initial protocol does not include encryption because traffic remains inside the USB and local ADB transport.

## Diagnostics

List devices:

    ADB_LIBUSB=0 adb devices -l

Check the selected device:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL get-state

Test shell access:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL shell echo connected

Create forwarding rules:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward tcp:27283 tcp:27283
    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward tcp:27284 tcp:27284

List forwarding rules:

    ADB_LIBUSB=0 adb forward --list

Remove forwarding rules:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward --remove tcp:27283
    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward --remove tcp:27284

## iPhone support

The current wired transport is Android-specific because it relies on ADB.

Old iPhones are not supported by this transport.

Supporting an iPhone would require a separate iOS application and a different communication layer.

That work is outside the current project scope.
