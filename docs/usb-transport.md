# Webcamera USB Transport

## Overview

Webcamera connects an Android phone to the macOS application through Android Debug Bridge port forwarding over USB.

The USB transport carries:

- control messages;
- H.264 video;
- AAC phone microphone audio;
- stream status;
- camera capability information;
- phone camera selection;
- Android stream configuration;
- torch commands;
- errors.

No Wi-Fi connection is required.

Local Mac cameras do not use this transport.

---

## Runtime topology

```text
Android camera
      ↓
Android camera capture
      ↓
H.264 MediaCodec encoder
      ↓
Android media server
      ↓
ADB USB forwarding
      ↓
macOS media connection
      ↓
H.264 packet parser
      ↓
VideoToolbox decoder
      ↓
CVPixelBuffer
      ↓
macOS preview and recording
```

Phone microphone audio follows:

```text
Android microphone
      ↓
AAC encoder
      ↓
Android media server
      ↓
ADB USB forwarding
      ↓
macOS media connection
      ↓
AAC packet parser
      ↓
AVAssetWriter
      ↓
macOS recording
```

---

## Android-side ports

Default ports:

```text
Control port: 27283
Media port:   27284
```

The Android application listens on loopback:

```text
127.0.0.1:27283
127.0.0.1:27284
```

The servers must not bind to:

```text
0.0.0.0
```

unless a separately secured network transport is implemented.

---

## Current macOS local ports

The current macOS controller forwards the same local port numbers:

```text
127.0.0.1:27283
127.0.0.1:27284
```

Forwarding commands:

```bash
ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward \
  tcp:27283 \
  tcp:27283

ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward \
  tcp:27284 \
  tcp:27284
```

Because the local ports are currently fixed, only one Android source can actively use the transport at a time without local-port conflicts.

Future multi-phone support requires unique local Mac ports per ADB serial.

---

## Device identity

Every Android phone is identified by its ADB serial.

List devices:

```bash
ADB_LIBUSB=0 adb devices -l
```

Example:

```text
SERIAL_NUMBER    device product:... model:... device:...
```

All device-specific ADB commands must use:

```bash
adb -s DEVICE_SERIAL
```

The device serial must not be hardcoded.

---

## ADB executable discovery

The macOS application searches common ADB paths:

```text
/opt/homebrew/bin/adb
/usr/local/bin/adb
~/Library/Android/sdk/platform-tools/adb
~/Android/Sdk/platform-tools/adb
```

The application sets:

```text
ADB_LIBUSB=0
```

This matches the scripts used during development.

---

## Android application startup

The macOS controller starts the Android debug activity:

```text
com.theandreyzakharov.webcamera.debug/com.theandreyzakharov.webcamera.ui.MainActivity
```

It also attempts to start:

```text
com.theandreyzakharov.webcamera.debug/com.theandreyzakharov.webcamera.service.CameraService
```

with action:

```text
com.theandreyzakharov.webcamera.START_SERVICE
```

Manual commands:

```bash
ADB_LIBUSB=0 adb -s DEVICE_SERIAL shell am start \
  -n \
  com.theandreyzakharov.webcamera.debug/com.theandreyzakharov.webcamera.ui.MainActivity
```

```bash
ADB_LIBUSB=0 adb -s DEVICE_SERIAL shell am startservice \
  -n \
  com.theandreyzakharov.webcamera.debug/com.theandreyzakharov.webcamera.service.CameraService \
  -a \
  com.theandreyzakharov.webcamera.START_SERVICE
```

---

## Control connection

The control connection uses newline-delimited UTF-8 JSON.

Every message is terminated by:

```text
\n
```

The macOS implementation supports:

- partial reads;
- multiple messages in one read;
- empty lines;
- JSON validation;
- connection failure;
- connection closure;
- asynchronous sends.

Outgoing macOS messages automatically include:

```text
version
type
sequence
timestamp
```

---

## Current control messages

macOS sends messages including:

```text
getCapabilities
getStatus
configure
start
stop
requestKeyFrame
setFlashMode
```

Android sends messages including:

```text
hello
capabilities
configured
status
flashStatus
error
```

---

## Android camera configuration

The current configure request contains:

```text
cameraId
width
height
frameRate
bitRate
audioEnabled
audioBitRate
flashMode
zoom
```

Example:

```json
{
  "version": 1,
  "type": "configure",
  "sequence": 123,
  "timestamp": 456789,
  "cameraId": "0",
  "width": 1280,
  "height": 720,
  "frameRate": 30,
  "bitRate": 4000000,
  "audioEnabled": true,
  "audioBitRate": 128000,
  "flashMode": "off",
  "zoom": 1.0
}
```

The selected format is source-specific.

The Android application should respond with `configured` only after applying the configuration successfully.

---

## Torch control

Torch changes use:

```text
setFlashMode
```

Enable:

```json
{
  "version": 1,
  "type": "setFlashMode",
  "sequence": 1,
  "timestamp": 1000,
  "flashMode": "torch"
}
```

Disable:

```json
{
  "version": 1,
  "type": "setFlashMode",
  "sequence": 2,
  "timestamp": 1100,
  "flashMode": "off"
}
```

Android responds with:

```text
flashStatus
```

The response may include:

```text
available
appliedMode
message
```

---

## Media connection

The binary media connection carries both video and phone audio.

The macOS implementation is named `VideoConnection` for historical reasons.

The supported packet types are:

```text
1  videoConfiguration
2  videoFrame
3  audioConfiguration
4  audioFrame
5  endOfStream
```

---

## Binary packet header

Every packet begins with a 36-byte header:

```text
magic                    4 bytes
version                  1 byte
packetType               1 byte
flags                    2 bytes
sequence                 8 bytes
presentationTimestamp    8 bytes
decodeTimestamp          8 bytes
payloadLength            4 bytes
```

All multi-byte values use network byte order.

Magic bytes:

```text
57 42 43 4D
```

ASCII:

```text
WBCM
```

Maximum payload size:

```text
32 MiB
```

---

## Packet flags

Current flags include:

```text
0x0001  key frame
0x0002  codec configuration
```

Packet type remains the primary indicator of packet content.

---

## Video configuration packets

`videoConfiguration` contains H.264 codec setup data.

The current macOS decoder expects Annex B data containing:

- SPS;
- PPS.

The decoder must receive valid configuration before decoding normal frames.

Configuration should be sent:

- before the first frame;
- after encoder restart;
- after resolution change;
- after media reconnection.

---

## Video frame packets

`videoFrame` contains H.264 Annex B frame data.

The packet includes:

- presentation timestamp;
- decode timestamp;
- sequence;
- key-frame flag;
- complete frame payload.

The macOS decoder converts Annex B NAL units to AVCC before creating a sample buffer.

---

## Audio configuration packets

`audioConfiguration` contains AAC codec configuration.

The macOS recorder stores the configuration and creates a compressed audio format description.

The configuration must arrive before phone-microphone recording can begin.

---

## Audio frame packets

`audioFrame` contains one compressed AAC audio packet.

The packet uses the media header presentation timestamp.

The macOS recorder:

1. creates a block buffer;
2. copies AAC payload bytes;
3. creates a compressed audio sample buffer;
4. assigns duration and timestamp;
5. appends it to the Android recording.

---

## End-of-stream packets

`endOfStream` marks an intentional media stop.

The Mac uses it to update Android stream state.

The payload is normally empty.

---

## Stream lifecycle

A normal stream lifecycle is:

1. Mac discovers the ADB device.
2. Mac starts the Android activity.
3. Mac attempts to start the Android service.
4. Mac creates control forwarding.
5. Mac creates media forwarding.
6. Mac connects to the control server.
7. Mac connects to the media server.
8. Mac requests capabilities.
9. Android reports phone cameras.
10. Mac selects a camera and format.
11. Mac sends `configure`.
12. Android responds with `configured`.
13. Mac sends `start`.
14. Android starts camera and encoders.
15. Android sends H.264 configuration.
16. Android sends AAC configuration when audio is enabled.
17. Android sends video and audio packets.
18. macOS decodes and displays video.
19. macOS optionally records video and audio.
20. Mac sends `stop`.
21. Android sends end-of-stream.
22. Android releases streaming resources.

---

## Recording

The Android phone does not create the final Webcamera recording file.

Recording occurs on macOS.

The Mac can combine Android video with:

```text
Phone Microphone
macOS microphone
No Audio
```

The output format can be:

```text
MOV
MP4
```

The output folder and filename behavior match local-camera recordings.

---

## Forwarding inspection

List all forwarding rules:

```bash
ADB_LIBUSB=0 adb forward --list
```

Remove only the Webcamera control forwarding:

```bash
ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward \
  --remove \
  tcp:27283
```

Remove only the Webcamera media forwarding:

```bash
ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward \
  --remove \
  tcp:27284
```

Do not use `forward --remove-all` in normal project scripts because it may remove forwarding rules belonging to other applications.

---

## Connection loss

The transport may fail because of:

- USB disconnection;
- ADB daemon restart;
- unauthorized device;
- offline device;
- Android process termination;
- forwarding loss;
- control socket failure;
- media socket failure;
- malformed JSON;
- invalid packet header;
- unsupported protocol version;
- payload size violation;
- encoder failure;
- H.264 decoder failure.

A failure in the Android transport must not stop local Mac cameras.

---

## Reconnection requirements

A full reconnection should:

1. close control and media sockets;
2. clear incomplete receive buffers;
3. reset the H.264 decoder;
4. mark the source unavailable;
5. rediscover the same ADB serial;
6. recreate forwarding;
7. restart or reconnect to the Android application;
8. request capabilities again;
9. restore a valid camera and format;
10. receive codec configuration again;
11. restart streaming if appropriate.

---

## Backpressure

Android media writing must not block camera or encoder callbacks indefinitely.

Recommended Android behavior:

- dedicated socket writer thread;
- bounded media queue;
- controlled frame dropping;
- key-frame request or restart after discontinuity;
- explicit socket failure handling.

Recommended macOS behavior:

- bounded receive buffers;
- maximum payload validation;
- isolated decoder queue;
- source-specific error reporting;
- decoder reset on configuration change.

---

## Diagnostics

List devices:

```bash
ADB_LIBUSB=0 adb devices -l
```

Check state:

```bash
ADB_LIBUSB=0 adb -s DEVICE_SERIAL get-state
```

Test shell:

```bash
ADB_LIBUSB=0 adb -s DEVICE_SERIAL shell echo connected
```

List forwarding:

```bash
ADB_LIBUSB=0 adb forward --list
```

Read logs:

```bash
ADB_LIBUSB=0 adb -s DEVICE_SERIAL logcat |
  grep -i webcamera
```

Check application process:

```bash
ADB_LIBUSB=0 adb -s DEVICE_SERIAL shell ps |
  grep -i webcamera
```

Run the repository test:

```bash
./scripts/test-usb-transport.sh DEVICE_SERIAL
```

---

## Security

The Android servers bind to loopback and are reached through an ADB-authorized USB connection.

The current protocol does not provide:

- encryption;
- authentication;
- network discovery;
- public network access.

A future Wi-Fi transport requires a separate security design.

---

## iPhone scope

ADB is Android-specific.

This transport does not support iPhone.

iPhone support would require:

- a separate iOS application;
- Apple signing;
- a different wired or network protocol;
- a separate compatibility and release process.
