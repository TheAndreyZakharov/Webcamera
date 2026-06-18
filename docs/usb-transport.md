# USB Transport

## Overview

Webcamera uses Android Debug Bridge port forwarding for wired Android camera sources.

One USB cable provides:

- phone charging;
- ADB access;
- control transport;
- encoded video transport.

No Wi-Fi connection is required for Android sources.

Built-in and USB cameras connected directly to the Mac do not use this transport.

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
    Decoder
          ↓
    Preview and recording

## Ports

Android-side ports:

    Control port: 27283
    Video port:   27284

The Android application listens on:

    127.0.0.1:27283
    127.0.0.1:27284

For one device, the Mac may use matching local ports.

For multiple Android devices, each device receives different local Mac ports.

Example:

    Device A:
        Mac control: 27283
        Mac video:   27284

    Device B:
        Mac control: 27383
        Mac video:   27384

Both devices still use Android ports 27283 and 27284.

## Control connection

The control connection carries JSON messages for:

- device identity;
- camera discovery;
- resolution discovery;
- FPS discovery;
- zoom capabilities;
- focus capabilities;
- exposure capabilities;
- flash and torch capabilities;
- encoder discovery;
- configuration;
- stream control;
- runtime controls;
- status;
- errors;
- keepalive.

## Video connection

The video connection carries framed H.264 packets.

It is independent of the control connection so:

- large video frames do not delay commands;
- controls remain responsive;
- video can restart without losing device metadata;
- each Android source can have its own decoder.

## Multiple Android devices

The macOS application may manage several Android devices simultaneously.

Each Android source uses:

- its own ADB serial;
- its own forwarding rules;
- its own control socket;
- its own video socket;
- its own decoder;
- its own selected phone camera;
- its own recording session.

The Mac must never send an ADB command without the selected serial when multiple devices are connected.

Commands use:

    adb -s DEVICE_SERIAL

## Forwarding lifecycle

For every selected Android device, the Mac:

1. verifies that the device is online;
2. allocates unused local ports;
3. removes stale forwarding rules for those ports;
4. creates control forwarding;
5. creates video forwarding;
6. starts or verifies the Android application;
7. connects to the control server;
8. connects to the video server when streaming starts.

Forwarding rules are recreated after:

- cable reconnection;
- ADB restart;
- phone restart;
- application restart;
- device selection change.

## Torch commands

Torch state is sent through the control connection.

Torch video data does not require a separate channel.

A torch request is valid only when:

- the selected Android camera reports flash support;
- the selected mode supports continuous torch;
- the Android camera session is active.

Android returns success or an error.

Torch failure must not close the video transport.

## Runtime camera controls

The following commands may travel through the existing control connection:

    zoom
    focus
    autofocus trigger
    exposure
    flash
    torch
    bitrate
    mirroring

Some commands can be applied without restarting capture.

Other configuration changes require:

    stop
    configure
    start

Resolution and FPS changes normally restart the Android camera and encoder.

## Recording

Android video is recorded on the Mac.

The USB transport does not write files on the phone.

This avoids:

- consuming phone storage;
- transferring completed files later;
- maintaining two recording implementations.

Each Android source supplies frames to an independent Mac recording writer.

Recording several Android devices creates several simultaneous video files.

## Bandwidth

Raw frames are not sent over ADB.

Android encodes H.264 before transmission.

Total USB and processing load increases with:

- number of Android sources;
- resolution;
- frame rate;
- bitrate;
- torch-related thermal load;
- simultaneous recording.

The application must report failures rather than silently reducing quality unless an explicit automatic-quality mode is added.

## 4K transport

4K is shown only when:

- the camera supports the output;
- the encoder supports the size;
- the selected FPS is valid;
- the encoder starts;
- transport remains stable.

Multiple simultaneous 4K Android sources may exceed practical hardware or storage limits.

The application may warn the user when a selected combination is likely to be unstable.

## Stability and recovery

The transport manager distinguishes between:

    device disconnected
    device offline
    Android application stopped
    control server unavailable
    video server unavailable
    forwarding missing
    protocol error
    decoder error

One Android source failure must not interrupt:

- local Mac cameras;
- USB cameras;
- other Android devices;
- recordings from other sources.

## Security

Android servers bind only to loopback.

They are reachable from the Mac through ADB forwarding only.

The initial protocol does not use encryption because the transport remains inside the USB and ADB connection.

## Diagnostics

List devices:

    ADB_LIBUSB=0 adb devices -l

Check one device:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL get-state

Test shell:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL shell echo connected

Create forwarding:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward tcp:LOCAL_CONTROL_PORT tcp:27283
    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward tcp:LOCAL_VIDEO_PORT tcp:27284

List forwarding rules:

    ADB_LIBUSB=0 adb forward --list

Remove one rule:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward --remove tcp:LOCAL_CONTROL_PORT

## iPhone support

The ADB transport is Android-specific.

Old iPhones are not supported by this wired transport.

Adding iPhone support would require a separate iOS application and another communication system.
