# Webcamera Android Protocol

## Overview

The Webcamera Android protocol connects the Android camera application to the macOS Webcamera application through ADB USB forwarding.

The protocol provides:

- Android device and camera capabilities;
- phone camera selection;
- video configuration;
- phone microphone configuration;
- stream start and stop;
- status reporting;
- key-frame requests;
- torch control;
- H.264 video transport;
- AAC phone microphone transport;
- error reporting.

Recording commands are not sent to Android.

The final recording is created on macOS.

---

## Protocol version

Current protocol version:

```text
1
```

Control messages contain:

```json
{
  "version": 1
}
```

Binary media packets contain the same version in their fixed header.

Unsupported versions must be rejected explicitly.

---

## Ports

Default Android ports:

```text
Control: 27283
Media:   27284
```

Android binds to:

```text
127.0.0.1:27283
127.0.0.1:27284
```

The Mac connects through ADB port forwarding.

---

# Control protocol

## Transport

Control messages are UTF-8 JSON objects separated by newline bytes.

Wire format:

```text
<JSON>\n
```

Receivers must support:

- partial messages;
- several messages in one socket read;
- empty lines;
- invalid UTF-8;
- invalid JSON;
- connection closure;
- implementation-defined maximum message size.

---

## Common fields

macOS-generated messages include:

```text
version
type
sequence
timestamp
```

Example:

```json
{
  "version": 1,
  "type": "getStatus",
  "sequence": 123,
  "timestamp": 456789
}
```

`sequence` is an unsigned identifier.

`timestamp` is a monotonic millisecond value based on process uptime.

Unknown optional fields may be ignored.

---

## hello

Android may send `hello` after the control connection is established.

Example:

```json
{
  "version": 1,
  "type": "hello",
  "sequence": 1,
  "timestamp": 1000,
  "deviceName": "Meizu MX5",
  "manufacturer": "Meizu",
  "model": "MX5",
  "androidVersion": "5.1",
  "apiLevel": 22,
  "applicationVersion": "1.0"
}
```

The Mac associates this connection with the ADB serial used to create forwarding.

---

## getCapabilities

Requests Android camera capabilities.

```json
{
  "version": 1,
  "type": "getCapabilities",
  "sequence": 2,
  "timestamp": 1100
}
```

---

## capabilities

Reports available phone cameras.

The macOS implementation currently reads camera fields:

```text
id
name
facing
flashAvailable
torchAvailable
```

Example:

```json
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
      "flashAvailable": true,
      "torchAvailable": true
    },
    {
      "id": "1",
      "name": "Front Camera",
      "facing": "front",
      "flashAvailable": false,
      "torchAvailable": false
    }
  ]
}
```

`facing` values include:

```text
rear
front
unknown
```

The rear camera is preferred by the macOS UI when available.

---

## configure

Requests the active phone camera and stream settings.

Current fields:

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
  "sequence": 4,
  "timestamp": 1300,
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

Android should validate:

- camera ID;
- resolution;
- frame rate;
- encoder support;
- audio support;
- flash mode;
- runtime state.

---

## configured

Confirms that the requested configuration has been applied.

Example:

```json
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
  "audioEnabled": true,
  "audioBitRate": 128000,
  "flashMode": "off",
  "zoom": 1.0
}
```

If Android changes requested values, it should report the values actually applied.

---

## start

Starts camera capture, video encoding, optional phone audio encoding, and media transmission.

```json
{
  "version": 1,
  "type": "start",
  "sequence": 6,
  "timestamp": 1500
}
```

Android may reject `start` when:

- no valid configuration exists;
- the camera cannot open;
- the encoder cannot start;
- the media client is missing;
- permission is missing;
- streaming is already in an incompatible state.

---

## stop

Stops the active stream.

```json
{
  "version": 1,
  "type": "stop",
  "sequence": 7,
  "timestamp": 2000
}
```

Expected Android behavior:

1. stop accepting new frames;
2. finish or stop audio encoding;
3. finish or stop video encoding;
4. send `endOfStream`;
5. release camera resources;
6. report final state.

The control connection may remain open.

---

## getStatus

Requests current Android state.

```json
{
  "version": 1,
  "type": "getStatus",
  "sequence": 8,
  "timestamp": 2100
}
```

---

## status

Reports current Android state.

Common fields:

```text
state
streaming
torchEnabled
message
```

Example:

```json
{
  "version": 1,
  "type": "status",
  "sequence": 9,
  "timestamp": 2200,
  "state": "streaming",
  "streaming": true,
  "torchEnabled": false,
  "message": "Streaming"
}
```

Current macOS behavior treats the source as running when:

```text
state == "streaming"
```

or:

```text
streaming == true
```

---

## requestKeyFrame

Requests an H.264 synchronization frame.

```json
{
  "version": 1,
  "type": "requestKeyFrame",
  "sequence": 10,
  "timestamp": 2300
}
```

Android should request an encoder sync frame when supported.

---

## setFlashMode

Changes Android flash or torch mode.

Enable torch:

```json
{
  "version": 1,
  "type": "setFlashMode",
  "sequence": 11,
  "timestamp": 2400,
  "flashMode": "torch"
}
```

Disable:

```json
{
  "version": 1,
  "type": "setFlashMode",
  "sequence": 12,
  "timestamp": 2500,
  "flashMode": "off"
}
```

Current supported values:

```text
torch
off
```

---

## flashStatus

Reports the result of a flash-mode command.

Example:

```json
{
  "version": 1,
  "type": "flashStatus",
  "sequence": 13,
  "timestamp": 2600,
  "available": true,
  "appliedMode": "torch",
  "message": "Torch enabled"
}
```

Fields:

```text
available
appliedMode
message
```

When `available` is false, the Mac displays the returned error.

---

## error

Reports a control or Android runtime error.

Fields currently used by macOS:

```text
code
message
```

Recommended additional fields:

```text
fatal
relatedSequence
```

Example:

```json
{
  "version": 1,
  "type": "error",
  "sequence": 14,
  "timestamp": 2700,
  "code": "camera_open_failed",
  "message": "The selected Android camera could not be opened.",
  "fatal": false,
  "relatedSequence": 6
}
```

Common error codes may include:

```text
invalid_message
unsupported_protocol
unsupported_message
invalid_state
camera_permission_denied
unknown_camera
camera_open_failed
camera_configuration_failed
video_encoder_failed
audio_encoder_failed
media_client_missing
flash_unavailable
transport_failed
internal_error
```

When Android reports `invalid_state` while macOS is already receiving frames, macOS may preserve the existing streaming state.

---

# Binary media protocol

## Packet structure

Every media packet contains:

1. a fixed 36-byte header;
2. a payload of `payloadLength` bytes.

Header:

```text
Offset  Size  Field
0       4     magic
4       1     version
5       1     packetType
6       2     flags
8       8     sequence
16      8     presentationTimestamp
24      8     decodeTimestamp
32      4     payloadLength
```

All multi-byte integers use big-endian network byte order.

---

## Magic

ASCII:

```text
WBCM
```

Bytes:

```text
0x57 0x42 0x43 0x4D
```

Packets with another magic value are invalid.

---

## Maximum payload

Maximum accepted payload size:

```text
32 MiB
```

The receiver rejects larger values before extracting the payload.

---

## Packet types

Current packet values:

```text
1  videoConfiguration
2  videoFrame
3  audioConfiguration
4  audioFrame
5  endOfStream
```

Unknown packet types are rejected.

---

## Flags

Current flags:

```text
0x0001  key frame
0x0002  codec configuration
```

`videoFrame` uses the key-frame flag.

Configuration packet types may also use the codec-configuration flag.

---

## Sequence

Every packet contains a 64-bit sequence value.

Sequence values are useful for:

- logging;
- detecting sender restart;
- identifying gaps;
- debugging transport behavior.

TCP guarantees byte ordering, but sequence values remain useful for diagnostics.

---

## Timestamps

Presentation and decode timestamps use microseconds.

The macOS implementation creates `CMTime` values with:

```text
timescale = 1,000,000
```

Timestamps should be monotonic within one active stream.

---

## videoConfiguration

Packet type:

```text
1
```

Payload:

```text
H.264 Annex B codec configuration
```

The payload should contain SPS and PPS NAL units.

Example conceptual payload:

```text
00 00 00 01 <SPS>
00 00 00 01 <PPS>
```

macOS extracts NAL unit types:

```text
7  SPS
8  PPS
```

A new configuration must be sent after:

- encoder restart;
- resolution change;
- media reconnection;
- decoder-resetting discontinuity.

---

## videoFrame

Packet type:

```text
2
```

Payload:

```text
one H.264 Annex B frame or access unit
```

The sender sets:

```text
0x0001
```

for key frames.

The macOS decoder converts every Annex B NAL unit to a four-byte length-prefixed AVCC representation.

---

## audioConfiguration

Packet type:

```text
3
```

Payload:

```text
AAC AudioSpecificConfig or equivalent AAC codec cookie
```

The current macOS recorder constructs an AAC format description using:

```text
sample rate:       48000 Hz
format:            MPEG-4 AAC
profile:           AAC Low Complexity
frames per packet: 1024
channels:          1
```

The payload is supplied as the audio magic cookie.

Android should send this packet before the first audio frame.

It should send it again after audio encoder restart.

---

## audioFrame

Packet type:

```text
4
```

Payload:

```text
one compressed AAC packet
```

The macOS recorder currently assigns an audio duration of:

```text
1024 / 48000 seconds
```

The packet presentation timestamp should correspond to the beginning of that AAC packet.

---

## endOfStream

Packet type:

```text
5
```

The payload is normally empty.

It indicates an intentional stream stop.

macOS marks the Android stream as stopped and clears torch state.

---

# Media stream ordering

A typical media stream is:

```text
videoConfiguration
audioConfiguration
videoFrame
audioFrame
videoFrame
audioFrame
...
endOfStream
```

Video and audio packets may be interleaved.

The receiver uses packet timestamps rather than assuming alternating packet order.

---

# Recording behavior

Android receives no record or stop-record command.

The Android application does not need to know whether macOS is recording.

macOS may:

- preview only;
- record MOV;
- record MP4;
- use phone audio;
- use a Mac microphone;
- record without audio;
- display multiple previews.

Recording state remains entirely on the Mac.

---

# Reconfiguration

Changing the selected phone camera or stream format may require:

1. `stop`;
2. `endOfStream`;
3. release old camera and encoder resources;
4. `configure`;
5. `configured`;
6. `start`;
7. new `videoConfiguration`;
8. new `audioConfiguration`;
9. new media frames.

Torch changes may be applied without a full restart when supported.

---

# Compatibility requirements

Senders must:

- bind to loopback;
- use protocol version 1;
- use big-endian header values;
- send valid payload lengths;
- send SPS and PPS before video frames;
- send AAC configuration before audio frames;
- use monotonic timestamps;
- release resources after stop;
- report applied camera state.

Receivers must:

- support partial TCP reads;
- buffer incomplete packets;
- process several packets per read;
- validate magic;
- validate version;
- validate packet type;
- validate payload size;
- reset decoder state after reconnection;
- isolate Android errors from local cameras.

---

# Security

The current protocol assumes:

- USB connection;
- ADB authorization;
- Android loopback servers;
- macOS localhost clients.

It does not provide:

- encryption;
- application-level authentication;
- public network security.

A future network implementation requires a separate authenticated and encrypted protocol design.
