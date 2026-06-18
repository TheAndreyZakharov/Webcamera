# Webcamera Protocol

## Overview

The Webcamera protocol connects an Android capture application to the macOS multi-camera viewer and recorder.

The protocol is used only by Android sources transported through ADB over USB.

Built-in Mac cameras, USB cameras, and other AVFoundation devices are controlled directly by the macOS application.

Every Android device has independent:

- control connection;
- video connection;
- camera configuration;
- decoder state;
- preview state;
- recording state.

## Protocol version

Initial version:

    1

Every JSON control message contains a `version` field.

Unsupported versions are rejected with an explicit error.

## Android ports

    Control port: 27283
    Video port:   27284

Android binds to:

    127.0.0.1:27283
    127.0.0.1:27284

Local Mac ports are allocated separately for each connected Android device.

## Connection lifecycle

1. Android starts control and video servers.
2. Mac detects the device through ADB.
3. Mac allocates local ports.
4. Mac creates forwarding rules.
5. Mac connects to the control server.
6. Android sends `hello`.
7. Mac sends `getCapabilities`.
8. Android sends `capabilities`.
9. Mac sends `configure`.
10. Android sends `configured`.
11. Mac connects to the video server.
12. Mac sends `start`.
13. Android sends `status: streaming`.
14. Android sends codec configuration.
15. Android sends video frames.
16. Mac may send runtime control commands.
17. Mac records decoded frames when requested.
18. Mac sends `stop` when the source is stopped.

After reconnection, capabilities, configuration, and codec state are established again.

## Control transport

Control messages are newline-delimited UTF-8 JSON objects.

TCP receivers must support:

- partial messages;
- several messages in one read;
- malformed JSON;
- maximum message size;
- clean connection closure.

Maximum recommended control message size:

    1 MiB

## Common fields

Every control message contains:

    version
    type
    sequence
    timestamp

`timestamp` uses a monotonic millisecond clock when possible.

## Device identity

### hello

Fields:

    deviceId
    deviceName
    manufacturer
    model
    androidVersion
    apiLevel
    buildDisplay
    applicationVersion

The Android application must not rely on a hardcoded ADB serial.

The Mac associates the protocol connection with the ADB device that owns the forwarding rule.

## Capability discovery

### getCapabilities

Requests all current phone camera and encoder capabilities.

### capabilities

Contains:

    cameras
    encoders
    defaultConfiguration

Each camera may contain:

    id
    name
    facing
    sensorOrientation
    flashAvailable
    torchAvailable
    zoomSupported
    minimumZoom
    maximumZoom
    zoomRatios
    focusModes
    exposureModes
    exposureCompensationMinimum
    exposureCompensationMaximum
    exposureCompensationStep
    formats

Each format contains:

    width
    height
    frameRates

Frame rates may be fixed values or ranges.

Each encoder may contain:

    name
    mimeType
    hardwareAccelerated
    bitrateRange
    frameRateRange
    supportedWidths
    supportedHeights
    colorFormats

Only camera and encoder combinations expected to be usable should be reported.

## Configuration

### configure

Fields:

    cameraId
    width
    height
    frameRate
    bitRate
    focusMode
    exposureMode
    exposureCompensation
    flashMode
    zoom
    mirror
    orientationMode
    keyFrameInterval

### configured

Returns the final applied values:

    cameraId
    width
    height
    frameRate
    bitRate
    focusMode
    exposureMode
    exposureCompensation
    flashMode
    zoom
    mirror
    rotation
    encoderName

Android may adjust requested values only when the final values are reported explicitly.

### configurationRejected

Fields:

    code
    message
    requestedConfiguration
    suggestedConfiguration

Possible codes include:

    unknown_camera
    unsupported_resolution
    unsupported_frame_rate
    unsupported_zoom
    unsupported_focus_mode
    unsupported_exposure_mode
    unsupported_flash_mode
    encoder_unavailable
    encoder_configuration_failed
    camera_open_failed

## Stream control

### start

Starts capture, encoding, and transmission.

### stop

Stops streaming while preserving the control session.

### requestKeyFrame

Requests an immediate H.264 sync frame when supported.

## Zoom control

### setZoom

Fields:

    zoom

Android clamps or rejects values outside the reported range.

### zoomChanged

Returns:

    requestedZoom
    appliedZoom

## Focus control

### setFocusMode

Fields:

    focusMode

### triggerAutoFocus

Starts a one-time autofocus operation.

### setFocusPoint

Optional fields:

    x
    y

Coordinates are normalized from 0 to 1.

The command is available only when the selected camera supports focus areas.

### focusStatus

Possible states:

    idle
    focusing
    focused
    failed
    unsupported

## Exposure control

### setExposureMode

Fields:

    exposureMode

### setExposureCompensation

Fields:

    value

### setExposurePoint

Optional normalized coordinates:

    x
    y

Only reported capabilities may be requested.

## Flashlight and flash control

### setFlashMode

Fields:

    flashMode

Possible values:

    off
    torch
    auto
    on

The exact available values are reported by the camera.

`torch` means continuous light while the camera is active.

### flashStatus

Fields:

    requestedMode
    appliedMode
    available
    message

Failure to enable the torch is nonfatal unless camera capture also fails.

## Bitrate control

### setBitRate

Fields:

    bitRate

Android applies the value dynamically when supported.

Otherwise it responds that encoder restart is required.

## Mirror control

### setMirror

Fields:

    mirror

The response indicates whether mirroring is applied:

    onAndroid
    onMac

## Status

### status

Possible states:

    idle
    waitingForVideoClient
    configuring
    configured
    starting
    streaming
    stopping
    reconnecting
    failed

Optional fields:

    cameraId
    width
    height
    frameRate
    bitRate
    zoom
    focusMode
    flashMode
    torchEnabled
    encodedFrames
    droppedFrames
    uptimeMilliseconds
    screenOn
    activityVisible
    foregroundServiceActive
    thermalState
    message

Recording state is not part of the Android status because recording is performed on the Mac.

## Keepalive

### ping

Fields:

    nonce

### pong

Fields:

    nonce

## Errors

### error

Fields:

    code
    message
    fatal
    relatedSequence

Possible codes include:

    invalid_message
    unsupported_protocol
    invalid_state
    camera_permission_denied
    camera_unavailable
    camera_disconnected
    camera_configuration_failed
    zoom_failed
    focus_failed
    exposure_failed
    flash_failed
    torch_failed
    encoder_unavailable
    encoder_failed
    video_client_missing
    video_transport_failed
    internal_error

## Video transport

The video connection contains binary packets.

Each packet consists of:

1. a fixed-size header;
2. a payload.

Maximum recommended payload size:

    32 MiB

## Video header

Header layout:

    magic                   4 bytes
    protocolVersion         1 byte
    packetType              1 byte
    flags                   2 bytes
    sequence                8 bytes
    presentationTimestamp   8 bytes
    decodingTimestamp       8 bytes
    payloadLength           4 bytes

Total:

    36 bytes

All multi-byte integers use network byte order.

## Magic value

ASCII:

    WBCM

Bytes:

    0x57 0x42 0x43 0x4D

## Packet types

### codecConfiguration

Contains H.264 SPS and PPS information required by VideoToolbox.

Sent:

- before the first frame;
- after encoder restart;
- after resolution change;
- after codec change;
- after video reconnection.

### videoFrame

Contains one encoded H.264 access unit.

### endOfStream

Marks an intentional stream end.

## Flags

    0x0001  key frame
    0x0002  codec configuration
    0x0004  end of stream
    0x0008  discontinuity
    0x0010  corrupted or incomplete

## H.264 format

The initial protocol uses length-prefixed NAL units suitable for VideoToolbox.

Android converts Annex B output when required.

A stream must not mix representations without sending a discontinuity and new codec configuration.

## Timestamps

Video timestamps use microseconds and a monotonic session-local origin.

The Mac uses them for:

- frame ordering;
- preview timing;
- recording timing;
- latency statistics.

## Multiple Android devices

Each Android device has separate:

    ADB serial
    local Mac ports
    control session
    video session
    decoder
    source identifier
    preview
    recording writer

The same Android ports are reused on each phone because ADB forwarding maps them to different Mac ports.

## Multiple simultaneous sources

The protocol itself manages one stream per Android device.

The macOS application combines several protocol sessions with local camera sources.

No Android source is aware of other active cameras.

Stopping or reconfiguring one source must not modify another source.

## Recording behavior

Recording commands are not sent to Android.

The Mac records frames received from the Android source.

This keeps recording location, file format, naming, and simultaneous recording under macOS control.

Protocol timestamps must remain stable enough for Mac-side recording.

## Reconfiguration

Changes requiring restart include:

    selected phone camera
    resolution
    frame rate
    encoder
    encoder color format

Expected sequence:

1. Mac sends `stop`.
2. Android reports `stopping`.
3. Android sends `endOfStream`.
4. Android releases capture resources.
5. Mac sends `configure`.
6. Android sends `configured`.
7. Mac sends `start`.
8. Android sends codec configuration.
9. Android resumes frames.

Zoom, focus, exposure, flash, torch, mirror, and bitrate may be runtime controls when supported.

## Compatibility

Receivers should:

- ignore unknown optional JSON fields;
- reject unsupported protocol versions;
- reject unsafe packet sizes;
- preserve unknown optional flags;
- report meaningful errors;
- avoid silent fallback to unrelated settings.

## Security

Android servers bind only to loopback.

The Mac reaches them through ADB forwarding.

The initial protocol does not use encryption or authentication.

## Diagnostics

Implementations should log:

- ADB serial;
- local and Android ports;
- selected camera;
- selected resolution and FPS;
- selected encoder;
- zoom changes;
- focus changes;
- torch changes;
- codec configuration;
- first decoded frame;
- frame drops;
- transport recovery;
- errors.

Logs must not contain raw camera frames.
