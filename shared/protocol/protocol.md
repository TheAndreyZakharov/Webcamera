# Webcamera Protocol

## Overview

The Webcamera protocol connects the Android camera application to the macOS Webcamera application.

The Android application has one primary responsibility:

    provide the Android phone camera to the Mac as a USB video source

The protocol is used only for Android sources transported through ADB over USB.

Built-in Mac cameras, USB cameras, virtual cameras, microphones, live monitoring, and local recording are handled directly by the macOS application.

The initial Android protocol is intentionally small.

It supports:

- device identity;
- basic camera capability discovery;
- stream configuration;
- stream start;
- stream stop;
- connection status;
- keepalive;
- errors;
- framed H.264 video.

The initial protocol does not include:

- recording commands;
- Android audio transport;
- zoom commands;
- focus commands;
- exposure commands;
- flash or torch commands;
- file transfer;
- Wi-Fi discovery.

Recording is performed on the Mac.

## Protocol version

Initial version:

    1

Every JSON control message contains a `version` field.

A receiver that does not support the requested version returns an explicit error.

## Android ports

Default Android-side ports:

    Control port: 27283
    Video port:   27284

The Android application binds to:

    127.0.0.1:27283
    127.0.0.1:27284

The Mac reaches the servers through ADB port forwarding.

Local Mac ports are allocated separately for every connected Android device.

## Per-device state

Every Android device has independent:

- ADB serial;
- control connection;
- video connection;
- selected phone camera;
- stream configuration;
- encoder state;
- packet sequence;
- macOS decoder state;
- preview state;
- Mac-side recording state.

The protocol itself handles one video stream per Android device.

Several Android devices may be combined by the macOS application.

## Connection lifecycle

1. Android starts the control server.
2. Android starts the video server.
3. Mac detects the device through ADB.
4. Mac creates forwarding rules.
5. Mac connects to the control server.
6. Android sends `hello`.
7. Mac sends `getCapabilities`.
8. Android sends `capabilities`.
9. Mac sends `configure`.
10. Android sends `configured`.
11. Mac connects to the video server.
12. Mac sends `start`.
13. Android starts camera capture and encoding.
14. Android sends `status` with `streaming`.
15. Android sends codec configuration.
16. Android sends encoded video frames.
17. Mac decodes, previews, and optionally records the source.
18. Mac sends `stop`.
19. Android sends an end-of-stream packet.
20. Android stops camera and encoder resources.

After reconnection, identity, capabilities, configuration, and codec state are established again.

## Control transport

Control messages are newline-delimited UTF-8 JSON objects.

Each object ends with:

    \n

A TCP receiver must support:

- partial JSON messages;
- several messages in one socket read;
- empty lines;
- malformed JSON;
- maximum message size;
- connection closure with an incomplete message.

Maximum recommended control message size:

    1 MiB

Messages larger than the configured maximum are rejected.

## Common control fields

Every control message contains:

    version
    type
    sequence
    timestamp

Example:

    {
      "version": 1,
      "type": "ping",
      "sequence": 12,
      "timestamp": 123456789,
      "nonce": "abc123"
    }

`sequence` is an unsigned message sequence number.

`timestamp` uses a monotonic millisecond clock when available.

Additional unknown optional fields may be ignored.

## Device identity

### hello

Sent by Android after the control connection is established.

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
      "timestamp": 1000,
      "deviceId": "android-device-id",
      "deviceName": "Meizu MX5",
      "manufacturer": "Meizu",
      "model": "MX5",
      "androidVersion": "5.1",
      "apiLevel": 22,
      "buildDisplay": "Flyme 6.2.0.0G",
      "applicationVersion": "1.0"
    }

The Android application does not need to know its ADB serial.

The Mac associates the connection with the ADB serial used to create the forwarding rule.

## Capability discovery

### getCapabilities

Requests the phone cameras and usable stream configurations.

Example:

    {
      "version": 1,
      "type": "getCapabilities",
      "sequence": 2,
      "timestamp": 1100
    }

### capabilities

Reports the Android cameras and configurations expected to work.

Fields:

    cameras
    defaultConfiguration

Each camera contains:

    id
    name
    facing
    sensorOrientation
    formats

`facing` values:

    front
    rear
    external
    unknown

Each format contains:

    width
    height
    frameRates
    bitRates

Example:

    {
      "version": 1,
      "type": "capabilities",
      "sequence": 3,
      "timestamp": 1200,
      "cameras": [
        {
          "id": "0",
          "name": "Rear Camera",
          "facing": "rear",
          "sensorOrientation": 90,
          "formats": [
            {
              "width": 1280,
              "height": 720,
              "frameRates": [30],
              "bitRates": [4000000]
            }
          ]
        },
        {
          "id": "1",
          "name": "Front Camera",
          "facing": "front",
          "sensorOrientation": 270,
          "formats": [
            {
              "width": 1280,
              "height": 720,
              "frameRates": [30],
              "bitRates": [3000000]
            }
          ]
        }
      ],
      "defaultConfiguration": {
        "cameraId": "0",
        "width": 1280,
        "height": 720,
        "frameRate": 30,
        "bitRate": 4000000
      }
    }

The Android application should report only camera and encoder combinations expected to be usable.

It does not need to report every camera mode exposed by the device.

## Stream configuration

### configure

Requests one camera and one stream configuration.

Required fields:

    cameraId
    width
    height
    frameRate
    bitRate

Optional fields:

    mirror
    keyFrameInterval

Example:

    {
      "version": 1,
      "type": "configure",
      "sequence": 4,
      "timestamp": 1300,
      "cameraId": "0",
      "width": 1280,
      "height": 720,
      "frameRate": 30,
      "bitRate": 4000000,
      "mirror": false,
      "keyFrameInterval": 2
    }

### configured

Reports the values actually applied by Android.

Fields:

    cameraId
    width
    height
    frameRate
    bitRate
    mirror
    rotation
    encoderName

Example:

    {
      "version": 1,
      "type": "configured",
      "sequence": 5,
      "timestamp": 1400,
      "cameraId": "0",
      "width": 1280,
      "height": 720,
      "frameRate": 30,
      "bitRate": 4000000,
      "mirror": false,
      "rotation": 90,
      "encoderName": "OMX.vendor.h264.encoder"
    }

Android may adjust a requested value only when the final applied value is reported explicitly.

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
    unsupported_bitrate
    encoder_unavailable
    encoder_configuration_failed
    camera_open_failed
    camera_configuration_failed

Example:

    {
      "version": 1,
      "type": "configurationRejected",
      "sequence": 6,
      "timestamp": 1450,
      "code": "unsupported_resolution",
      "message": "The selected camera cannot stream at the requested resolution.",
      "requestedConfiguration": {
        "cameraId": "0",
        "width": 3840,
        "height": 2160,
        "frameRate": 30,
        "bitRate": 12000000
      },
      "suggestedConfiguration": {
        "cameraId": "0",
        "width": 1920,
        "height": 1080,
        "frameRate": 30,
        "bitRate": 8000000
      }
    }

## Stream control

### start

Starts:

- phone camera capture;
- H.264 encoding;
- transmission to the connected video client.

Example:

    {
      "version": 1,
      "type": "start",
      "sequence": 7,
      "timestamp": 1500
    }

Android should reject `start` when:

- no configuration has been applied;
- no video client is connected;
- camera permission is missing;
- camera startup fails;
- encoder startup fails.

### stop

Stops streaming while preserving the control connection and current valid configuration.

Example:

    {
      "version": 1,
      "type": "stop",
      "sequence": 8,
      "timestamp": 2000
    }

Android should:

1. stop accepting new camera frames;
2. signal encoder end of stream when practical;
3. send an `endOfStream` video packet;
4. stop and release the encoder;
5. stop and release camera resources;
6. send a final status update.

### requestKeyFrame

Optional first-version message.

Requests an H.264 sync frame when the encoder supports the operation.

Example:

    {
      "version": 1,
      "type": "requestKeyFrame",
      "sequence": 9,
      "timestamp": 2100
    }

This message may be used after decoder recovery or a detected discontinuity.

## Status

### status

Reports the Android stream state.

Possible states:

    idle
    waitingForVideoClient
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
    encodedFrames
    droppedFrames
    uptimeMilliseconds
    foregroundServiceActive
    activityVisible
    screenOn
    message

Example:

    {
      "version": 1,
      "type": "status",
      "sequence": 10,
      "timestamp": 2500,
      "state": "streaming",
      "cameraId": "0",
      "width": 1280,
      "height": 720,
      "frameRate": 30,
      "bitRate": 4000000,
      "encodedFrames": 300,
      "droppedFrames": 2,
      "uptimeMilliseconds": 10000,
      "foregroundServiceActive": true,
      "activityVisible": false,
      "screenOn": false,
      "message": "Streaming"
    }

Recording state is not included because recording is performed on the Mac.

## Keepalive

### ping

Fields:

    nonce

Example:

    {
      "version": 1,
      "type": "ping",
      "sequence": 11,
      "timestamp": 3000,
      "nonce": "ping-11"
    }

### pong

Returns the same nonce.

Example:

    {
      "version": 1,
      "type": "pong",
      "sequence": 12,
      "timestamp": 3010,
      "nonce": "ping-11"
    }

A missing `pong` may cause the Mac to close and recreate the connection.

## Errors

### error

Fields:

    code
    message
    fatal
    relatedSequence

Possible codes:

    invalid_message
    message_too_large
    unsupported_protocol
    unsupported_message
    invalid_state
    camera_permission_denied
    camera_unavailable
    camera_open_failed
    camera_configuration_failed
    encoder_unavailable
    encoder_configuration_failed
    encoder_failed
    video_client_missing
    video_transport_failed
    internal_error

Example:

    {
      "version": 1,
      "type": "error",
      "sequence": 13,
      "timestamp": 3200,
      "code": "video_client_missing",
      "message": "A video client must connect before streaming can start.",
      "fatal": false,
      "relatedSequence": 7
    }

A fatal error means that the current stream or connection cannot continue without reinitialization.

## Video transport

The video connection contains binary packets.

Every packet consists of:

1. a fixed-size header;
2. a payload.

Maximum recommended payload size:

    32 MiB

The receiver rejects larger payloads before allocating memory for them.

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

Total size:

    36 bytes

All multi-byte integers use network byte order.

## Magic value

ASCII:

    WBCM

Bytes:

    0x57 0x42 0x43 0x4D

A packet with another magic value is invalid.

## Packet types

Initial packet types:

    1  codecConfiguration
    2  videoFrame
    3  endOfStream

Unknown required packet types are rejected.

Unknown optional packet types may be skipped only when their payload length is valid.

## codecConfiguration

Contains H.264 codec configuration required by VideoToolbox.

It is sent:

- before the first frame;
- after encoder restart;
- after a resolution change;
- after video reconnection;
- after a discontinuity that invalidates decoder state.

The payload contains SPS and PPS data in the protocol’s selected H.264 representation.

The Mac must not decode regular frames before valid codec configuration has been received.

## videoFrame

Contains one encoded H.264 access unit.

A video-frame packet contains:

- one presentation timestamp;
- one decoding timestamp;
- one sequence number;
- key-frame information in flags;
- one complete access-unit payload.

A frame should not be split across several protocol packets in the first implementation.

TCP may still split the bytes across socket reads, so the receiver must buffer until the full packet is available.

## endOfStream

Marks an intentional stream stop.

The payload is normally empty.

The Mac uses it to:

- flush decoder state;
- finish pending frames;
- distinguish a normal stop from a broken socket.

## Flags

Initial flags:

    0x0001  key frame
    0x0002  codec configuration
    0x0004  end of stream
    0x0008  discontinuity
    0x0010  corrupted or incomplete

A sender must set packet type and flags consistently.

A receiver validates unsafe combinations.

## H.264 representation

The initial protocol uses length-prefixed H.264 NAL units suitable for VideoToolbox.

Android converts Annex B encoder output when required.

The stream must not switch between Annex B and length-prefixed representations without:

1. marking a discontinuity;
2. sending new codec configuration;
3. resetting decoder state.

## Timestamps

Video timestamps use microseconds.

The origin is monotonic and local to the current stream session.

The Mac uses timestamps for:

- frame ordering;
- preview timing;
- decoder timing;
- Mac-side recording timing;
- latency statistics.

Timestamps must not use wall-clock time.

After an encoder restart, the sender may start a new timestamp origin only when it marks a discontinuity.

## Sequence numbers

Control messages and video packets use independent sequence spaces.

Video packet sequence numbers increase for every packet.

The Mac may use gaps to detect:

- dropped packets;
- sender restart;
- transport corruption;
- discontinuity.

TCP provides ordered and reliable bytes, but sequence numbers remain useful for diagnostics and reconnect detection.

## Video connection behavior

The Android video server accepts one active Mac video client for the current phone source.

When a second client connects, Android should either:

- reject the second connection;
- replace the stale connection only after closing it explicitly.

The behavior must be deterministic and logged.

## Reconfiguration

Changing these values requires stream restart:

    selected phone camera
    resolution
    frame rate
    encoder
    encoder input mode

Expected sequence:

1. Mac sends `stop`.
2. Android reports `stopping`.
3. Android sends `endOfStream`.
4. Android releases camera and encoder resources.
5. Mac sends `configure`.
6. Android sends `configured`.
7. Mac reconnects the video connection when needed.
8. Mac sends `start`.
9. Android sends new codec configuration.
10. Android sends new video frames.

The first version does not require runtime zoom, focus, exposure, or torch changes.

## Recording behavior

Recording commands are not sent to Android.

The Mac records the received Android video source.

The Android application does not need to know whether the Mac is:

- only previewing;
- recording;
- exporting MP4;
- writing MOV;
- displaying the source in several preview views.

This separation keeps Android simple and keeps recording behavior consistent with local macOS cameras.

## Audio behavior

The initial Android protocol is video-only.

It does not transport:

- phone microphone audio;
- system audio;
- audio format information;
- audio timestamps.

Mac-side microphone selection and monitoring apply to local AVFoundation camera controllers.

Android audio may be designed as a separate protocol extension later.

## Multiple Android devices

Each connected Android device uses separate:

    ADB serial
    local Mac control port
    local Mac video port
    control session
    video session
    packet parser
    decoder
    source identifier
    preview state
    recording state

The Android ports remain the same on every phone.

ADB maps them to unique local ports on the Mac.

No Android source is aware of another active source.

Stopping one Android source must not affect another Android source or a local Mac camera.

## Compatibility rules

Receivers should:

- ignore unknown optional JSON fields;
- reject unsupported protocol versions;
- reject invalid message types;
- reject unsafe packet sizes;
- tolerate partial TCP reads;
- preserve connection isolation between devices;
- report meaningful errors;
- avoid silent fallback to unrelated settings.

Senders should:

- report the configuration actually applied;
- send codec configuration before video frames;
- send new codec configuration after encoder restart;
- use monotonic timestamps;
- increment packet sequence numbers;
- release camera and encoder resources after stop;
- bind servers only to loopback.

## Security

Android servers bind only to:

    127.0.0.1

The Mac reaches them through ADB forwarding.

The first protocol does not use encryption or authentication.

The transport is intended for a USB-connected, ADB-authorized development device.

A future network transport would require a separate security design.

## Diagnostics

Implementations should log:

- ADB serial on the Mac;
- Android device identity;
- local and Android ports;
- protocol version;
- control connection state;
- video connection state;
- selected camera;
- selected resolution;
- selected frame rate;
- selected bitrate;
- encoder name;
- codec configuration;
- first encoded frame;
- first decoded frame;
- sequence gaps;
- dropped frames;
- stream start;
- stream stop;
- reconnect attempts;
- errors.

Logs must not contain:

- raw camera frames;
- encoded frame payloads;
- private user media.
