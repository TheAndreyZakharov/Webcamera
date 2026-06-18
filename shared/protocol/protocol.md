# Webcamera Protocol

## Overview

The Webcamera protocol connects the Android capture application to the macOS viewer application.

It is used only for Android camera sources transported through ADB over USB.

Built-in Mac cameras, USB cameras, and other AVFoundation devices do not use this protocol. They are accessed directly by the macOS application through AVFoundation.

The Android transport uses two independent TCP connections:

- a control connection for commands, capabilities, status, and errors;
- a video connection for encoded H.264 packets.

## Protocol version

The initial protocol version is:

    1

Every control message includes a `version` field.

The receiver must reject unsupported major protocol versions and report a clear compatibility error.

## Ports

Default Android ports:

    Control port: 27283
    Video port:   27284

The Android application binds both servers to the loopback interface:

    127.0.0.1:27283
    127.0.0.1:27284

The macOS application reaches them through ADB port forwarding.

The local Mac ports may differ when multiple Android devices are connected.

For example:

    Device A:
        Mac control port: 27283
        Mac video port:   27284

    Device B:
        Mac control port: 27383
        Mac video port:   27384

The Android-side ports remain unchanged.

## Transport lifecycle

The expected connection sequence is:

1. The Android application starts its control and video servers.
2. The macOS application detects the Android device through ADB.
3. The macOS application creates forwarding rules.
4. The Mac connects to the control server.
5. Android sends `hello`.
6. The Mac sends `getCapabilities`.
7. Android sends `capabilities`.
8. The Mac sends `configure`.
9. Android validates the requested configuration.
10. Android sends `configured`.
11. The Mac connects to the video server.
12. The Mac sends `start`.
13. Android sends `status` with the `streaming` state.
14. Android sends codec configuration and encoded frames.
15. The Mac sends `stop` or closes the connection when streaming ends.

After reconnection, configuration and codec state must be established again.

## Control transport

Control messages are UTF-8 JSON objects separated by newline characters.

Each line contains one complete JSON object.

Example:

    {
      "version": 1,
      "type": "hello",
      "sequence": 1,
      "timestamp": 12540
    }

TCP is a byte stream.

The receiver must:

- buffer incomplete data;
- split complete messages using newline characters;
- process multiple messages from one read;
- preserve trailing partial data;
- reject malformed JSON safely;
- enforce a maximum message size.

## Common control fields

Every control message should contain:

    version
    type
    sequence
    timestamp

### version

Integer protocol version.

### type

String message type.

### sequence

Unsigned logical message sequence number.

Sequence numbers are generated independently by each endpoint.

### timestamp

Monotonic timestamp in milliseconds when possible.

The timestamp is used for diagnostics and latency measurements. It is not a wall-clock time.

## Android device identity

### hello

Sent by Android immediately after the control connection is established.

Fields:

    deviceId
    deviceName
    manufacturer
    model
    androidVersion
    apiLevel
    buildDisplay
    applicationVersion

Example:

    {
      "version": 1,
      "type": "hello",
      "sequence": 1,
      "timestamp": 12540,
      "deviceId": "85UBBMD222YN",
      "deviceName": "Meizu MX5",
      "manufacturer": "Meizu",
      "model": "MX5",
      "androidVersion": "5.1",
      "apiLevel": 22,
      "buildDisplay": "Flyme 6.2.0.0G",
      "applicationVersion": "1.0.0"
    }

The protocol must not require a hardcoded device serial.

The macOS application obtains the ADB serial independently and may associate it with the connected control session.

## Capability discovery

### getCapabilities

Sent by macOS to request current Android camera and encoder capabilities.

Example:

    {
      "version": 1,
      "type": "getCapabilities",
      "sequence": 2,
      "timestamp": 12600
    }

### capabilities

Sent by Android in response to `getCapabilities`.

Fields:

    cameras
    encoders
    defaultConfiguration

Each camera entry may include:

    id
    name
    facing
    sensorOrientation
    flashAvailable
    focusModes
    formats

Each format entry includes:

    width
    height
    frameRates

Each frame-rate entry may be:

- a fixed value;
- a minimum and maximum range.

Each encoder entry may include:

    name
    mimeType
    hardwareAccelerated
    supportedWidths
    supportedHeights
    bitrateRange
    frameRateRange
    colorFormats

Example structure:

    {
      "version": 1,
      "type": "capabilities",
      "sequence": 3,
      "timestamp": 12700,
      "cameras": [
        {
          "id": "0",
          "name": "Rear camera",
          "facing": "back",
          "sensorOrientation": 90,
          "flashAvailable": true,
          "focusModes": [
            "auto",
            "continuous-video"
          ],
          "formats": [
            {
              "width": 1920,
              "height": 1080,
              "frameRates": [
                30
              ]
            }
          ]
        }
      ],
      "encoders": [
        {
          "name": "OMX.example.h264.encoder",
          "mimeType": "video/avc",
          "hardwareAccelerated": true
        }
      ]
    }

Android should expose only configurations that are reasonably expected to work with both the camera and encoder.

The Mac must still handle configuration failure.

## Configuration

### configure

Sent by macOS to select the Android capture configuration.

Fields:

    cameraId
    width
    height
    frameRate
    bitRate
    focusMode
    flashMode
    mirror
    orientationMode
    keyFrameInterval

Example:

    {
      "version": 1,
      "type": "configure",
      "sequence": 4,
      "timestamp": 13000,
      "cameraId": "0",
      "width": 1920,
      "height": 1080,
      "frameRate": 30,
      "bitRate": 8000000,
      "focusMode": "continuous-video",
      "flashMode": "off",
      "mirror": false,
      "orientationMode": "display-upright",
      "keyFrameInterval": 2
    }

### configured

Sent by Android after successful validation and configuration.

Fields:

    cameraId
    width
    height
    frameRate
    bitRate
    focusMode
    flashMode
    mirror
    rotation
    encoderName

Android may adjust requested values to the nearest supported configuration.

The final applied values must be returned explicitly.

### configurationRejected

Sent when the requested configuration cannot be applied.

Fields:

    code
    message
    requestedConfiguration
    suggestedConfiguration

Possible codes:

    unknown_camera
    unsupported_resolution
    unsupported_frame_rate
    unsupported_focus_mode
    unsupported_flash_mode
    encoder_unavailable
    encoder_configuration_failed
    camera_open_failed

## Stream control

### start

Sent by macOS to start camera capture, encoding, and video transmission.

Example:

    {
      "version": 1,
      "type": "start",
      "sequence": 5,
      "timestamp": 13200
    }

### stop

Sent by macOS to stop streaming while preserving the control connection.

Example:

    {
      "version": 1,
      "type": "stop",
      "sequence": 6,
      "timestamp": 18000
    }

### requestKeyFrame

Sent by macOS when the decoder requires a new H.264 key frame.

Example:

    {
      "version": 1,
      "type": "requestKeyFrame",
      "sequence": 7,
      "timestamp": 18100
    }

Android should request an immediate sync frame from the encoder when supported.

## Runtime controls

Runtime controls may be changed without fully rebuilding the connection when supported.

### setFocusMode

Fields:

    focusMode

### triggerAutoFocus

Requests a one-time autofocus operation.

### setFlashMode

Fields:

    flashMode

Possible values may include:

    off
    torch
    auto

Only values reported in capabilities may be requested.

### setBitRate

Fields:

    bitRate

Android may apply the new bitrate dynamically when the encoder supports it.

Otherwise, it may report that an encoder restart is required.

### setMirror

Fields:

    mirror

Mirroring may be applied:

- on Android before encoding;
- on macOS during rendering.

The selected implementation must be reported in status or configuration data.

## Status messages

### status

Sent by Android whenever the state changes.

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

Additional fields may include:

    cameraId
    width
    height
    frameRate
    bitRate
    encodedFrames
    droppedFrames
    uptimeMilliseconds
    screenOn
    thermalState
    message

Example:

    {
      "version": 1,
      "type": "status",
      "sequence": 8,
      "timestamp": 14000,
      "state": "streaming",
      "width": 1920,
      "height": 1080,
      "frameRate": 30,
      "bitRate": 8000000,
      "encodedFrames": 120,
      "droppedFrames": 2
    }

## Keepalive

### ping

May be sent by either endpoint.

Fields:

    nonce

### pong

Sent in response to `ping`.

Fields:

    nonce

The receiver should answer promptly.

A missing response may trigger transport diagnostics and reconnection.

## Errors

### error

Reports a recoverable or fatal error.

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
    encoder_unavailable
    encoder_failed
    video_client_missing
    video_transport_failed
    internal_error

Example:

    {
      "version": 1,
      "type": "error",
      "sequence": 9,
      "timestamp": 14500,
      "code": "encoder_failed",
      "message": "The H.264 encoder stopped unexpectedly.",
      "fatal": true,
      "relatedSequence": 5
    }

## Video transport

The video connection carries binary packets.

It must not contain JSON or newline framing.

Each packet consists of:

1. a fixed-size header;
2. a payload with the exact declared length.

## Video packet header

The initial header layout is:

    magic                   4 bytes
    protocolVersion         1 byte
    packetType              1 byte
    flags                   2 bytes
    sequence                8 bytes
    presentationTimestamp   8 bytes
    decodingTimestamp       8 bytes
    payloadLength           4 bytes

Total header size:

    36 bytes

All multi-byte integer fields use network byte order.

## Video packet magic

The magic value is:

    WBCM

In bytes:

    0x57 0x42 0x43 0x4D

Packets with an invalid magic value must be rejected.

## Video packet types

### codecConfiguration

Contains H.264 decoder configuration.

The payload contains the codec-specific data required to build the VideoToolbox format description.

It must include valid SPS and PPS information.

Codec configuration is sent:

- before the first decodable frame;
- after encoder restart;
- after resolution change;
- after codec configuration change;
- after video reconnection.

### videoFrame

Contains one encoded access unit.

Flags identify whether the frame is:

- a key frame;
- a regular frame;
- discardable;
- the final packet before shutdown.

### endOfStream

Signals an intentional stream end.

Its payload may be empty.

## Video packet flags

Initial flags:

    0x0001  key frame
    0x0002  codec configuration
    0x0004  end of stream
    0x0008  discontinuity
    0x0010  corrupted or incomplete

Unknown flags must be ignored unless they affect safe parsing.

## H.264 representation

The Android sender and macOS receiver must agree on the H.264 payload representation.

The initial protocol uses length-prefixed NAL units suitable for VideoToolbox.

If the Android encoder returns Annex B start codes, Android converts them before transmission or clearly identifies the representation in codec configuration metadata.

The stream must not mix Annex B and length-prefixed frames without a decoder reset.

## Timestamps

Video timestamps use microseconds.

The timestamp origin is monotonic and local to the Android streaming session.

The Mac uses timestamps for:

- frame ordering;
- latency estimation;
- preview scheduling;
- stream statistics.

The Mac must not treat them as wall-clock timestamps.

## Sequence numbers

Video packets use a continuously increasing sequence number.

A gap may indicate:

- dropped packets before transmission;
- encoder output loss;
- sender restart;
- connection reset.

Because TCP is reliable, missing sequence numbers usually indicate sender-side dropping or a new session.

## Payload limits

The receiver must enforce safe limits.

Recommended initial maximum values:

    Control message: 1 MiB
    Video packet:    32 MiB

Payload lengths larger than the configured maximum must terminate the video session.

## Reconfiguration

Changing any of these values requires an encoder restart:

    camera
    width
    height
    frame rate
    encoder
    color format

The expected sequence is:

1. Mac sends `stop`.
2. Android sends `status: stopping`.
3. Android sends an `endOfStream` packet.
4. Android releases camera and encoder resources.
5. Mac sends `configure`.
6. Android sends `configured`.
7. Mac sends `start`.
8. Android sends new codec configuration.
9. Android resumes video frames.

Controls such as focus, flash, mirror, or bitrate may be applied without restart when supported.

## Screen-off operation

Android may continue streaming while the activity is not visible or the screen is off.

The control channel may report:

    screenOn
    activityVisible
    foregroundServiceActive

The Mac should not treat screen-off state as a stream failure.

Actual behavior depends on Android firmware.

## Multiple Android devices

The protocol supports one control and one video session per Android device.

The macOS application may manage multiple Android devices simultaneously, but each device uses:

- its own ADB serial;
- its own forwarding rules;
- its own local Mac ports;
- its own control session;
- its own video session;
- its own decoder state.

Only one source needs to be displayed in the main preview at a time.

Inactive Android sources may remain disconnected or stopped.

## Local macOS cameras

Built-in and USB cameras discovered through AVFoundation do not use this protocol.

Their capabilities come directly from `AVCaptureDevice`.

The common macOS source model converts both local cameras and Android cameras into the same application-level representation:

    source identifier
    source name
    formats
    frame rates
    controls
    frame stream
    status

## Compatibility rules

A receiver should:

- ignore unknown optional JSON fields;
- reject unsupported protocol versions;
- reject unknown required packet structures;
- preserve compatibility with added optional controls;
- report meaningful errors instead of silently disconnecting.

New message types should be optional unless introduced by a new protocol version.

## Security

The Android servers bind only to the loopback interface.

The protocol is transported through ADB forwarding over USB.

The initial version does not include encryption or authentication.

The Mac must connect only to ports created for the selected ADB device.

## Diagnostics

Implementations should log:

- connection creation;
- selected ADB serial;
- forwarding ports;
- protocol version;
- selected camera configuration;
- encoder name;
- codec configuration receipt;
- first decoded frame;
- dropped frames;
- reconnect attempts;
- errors and state transitions.

Logs must not include private user content or raw frame data.
