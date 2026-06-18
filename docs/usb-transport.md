# USB Transport

## Overview

Webcamera uses Android Debug Bridge port forwarding to connect an Android phone to the macOS application over USB.

The Android application has one primary purpose:

    send the phone camera image to the Mac as a Webcamera video source

One USB cable provides:

- phone charging;
- ADB access;
- control transport;
- encoded video transport.

No Wi-Fi connection is required.

Built-in Mac cameras and cameras connected directly to the Mac do not use this transport.

## First-version scope

The first Android transport supports:

- device identification;
- basic camera capability reporting;
- stream configuration;
- stream start;
- stream stop;
- H.264 video transport;
- connection status;
- keepalive;
- errors;
- reconnection.

The first version does not require:

- audio transport;
- phone-side recording;
- remote zoom;
- remote focus;
- remote exposure;
- remote torch;
- remote white balance;
- file transfer;
- media synchronization;
- Wi-Fi fallback.

Recording is performed by the macOS application.

## Runtime topology

    Android camera
          ↓
    Android camera capture
          ↓
    MediaCodec H.264 encoder
          ↓
    Android loopback TCP servers
          ↓
    ADB USB port forwarding
          ↓
    macOS localhost TCP clients
          ↓
    H.264 packet parser
          ↓
    VideoToolbox decoder
          ↓
    Webcamera preview
          ↓
    Mac-side recording

## Android-side ports

Default Android ports:

    Control port: 27283
    Video port:   27284

The Android application listens on:

    127.0.0.1:27283
    127.0.0.1:27284

Binding to loopback prevents normal network access to the servers.

The Mac reaches them through ADB forwarding.

## Local Mac ports

For one device, the Mac may use the same local port numbers:

    Mac control: 27283
    Mac video:   27284

For multiple devices, every device must receive different local Mac ports.

Example:

    Device A:
        Mac control: 27283
        Mac video:   27284

    Device B:
        Mac control: 27383
        Mac video:   27384

Both phones still use Android-side ports 27283 and 27284.

## Device identity

Every Android phone is identified by its ADB serial.

List devices:

    ADB_LIBUSB=0 adb devices -l

Example:

    SERIAL_A    device product:... model:...
    SERIAL_B    device product:... model:...

The ADB serial must not be hardcoded.

All device-specific commands use:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL ...

## Control connection

The control connection uses newline-delimited UTF-8 JSON messages.

It carries:

- protocol version;
- device identity;
- available phone cameras;
- supported stream configurations;
- selected stream configuration;
- start command;
- stop command;
- status updates;
- keepalive;
- errors.

The control connection is intentionally small in the first Android version.

Advanced camera controls can be added later without changing the separate video transport.

## Video connection

The video connection carries framed H.264 packets.

It is separate from the control connection so that:

- large video packets do not delay commands;
- keepalive remains responsive;
- control errors can be reported independently;
- the video connection can restart;
- decoder state remains source-specific;
- future multiple Android devices remain isolated.

## Stream lifecycle

A normal stream lifecycle is:

1. Android application starts its local servers.
2. Mac detects the phone through ADB.
3. Mac creates forwarding rules.
4. Mac connects to the control server.
5. Android sends device identity.
6. Mac requests capabilities.
7. Android reports cameras and usable stream configurations.
8. Mac sends a configuration.
9. Android applies the configuration.
10. Mac connects to the video server.
11. Mac sends `start`.
12. Android starts camera capture.
13. Android starts the H.264 encoder.
14. Android sends codec configuration.
15. Android sends encoded frames.
16. Mac decodes and displays frames.
17. Mac records frames when requested.
18. Mac sends `stop`.
19. Android sends end-of-stream information.
20. Android stops camera and encoder resources.

## Forwarding creation

Create forwarding for one device:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward tcp:LOCAL_CONTROL_PORT tcp:27283

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward tcp:LOCAL_VIDEO_PORT tcp:27284

Example:

    ADB_LIBUSB=0 adb -s SERIAL_A forward tcp:27283 tcp:27283

    ADB_LIBUSB=0 adb -s SERIAL_A forward tcp:27284 tcp:27284

## Forwarding lifecycle

For every Android source, the Mac:

1. verifies that the ADB device is online;
2. resolves its ADB serial;
3. allocates unused local ports;
4. removes stale forwarding rules for those local ports;
5. creates a control forwarding rule;
6. creates a video forwarding rule;
7. starts or verifies the Android application when supported;
8. connects to the control server;
9. connects to the video server when streaming begins.

Forwarding rules are recreated after:

- cable reconnection;
- ADB daemon restart;
- phone restart;
- Android application restart;
- macOS application restart;
- local-port conflict.

## Removing forwarding

List forwarding rules:

    ADB_LIBUSB=0 adb forward --list

Remove one control rule:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward --remove tcp:LOCAL_CONTROL_PORT

Remove one video rule:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward --remove tcp:LOCAL_VIDEO_PORT

Remove all rules for a device when appropriate:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward --remove-all

The Mac should remove only rules that belong to Webcamera.

## Android application startup

During development, the Mac or scripts may start the Android activity with ADB.

The exact component name depends on the Android package.

Example structure:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL shell am start -n PACKAGE_NAME/.MainActivity

A foreground service may continue streaming after the activity is no longer visible.

The first implementation must not depend on the Android screen remaining on.

## Camera configuration

The Android application reports a list of usable stream configurations.

A configuration may contain:

- camera identifier;
- front or rear facing;
- width;
- height;
- frame rate;
- bitrate;
- encoder name.

The first version should expose only configurations expected to work reliably.

The Mac does not request arbitrary unsupported values.

## H.264 encoding

Raw camera frames are not transported through ADB.

Android encodes video with `MediaCodec`.

The initial codec is:

    H.264 / AVC

The encoded stream includes:

- SPS and PPS codec configuration;
- key frames;
- regular frames;
- presentation timestamps;
- sequence numbers;
- end-of-stream packets.

The Mac decodes H.264 through VideoToolbox.

## Video packet framing

TCP does not preserve application message boundaries.

Every H.264 payload therefore uses a fixed header followed by a payload.

The receiver must support:

- partial headers;
- partial payloads;
- several packets in one socket read;
- invalid packet lengths;
- connection closure during a packet;
- encoder discontinuities;
- new codec configuration after restart.

## Recording

The Android phone does not create Webcamera recording files.

Recording is controlled and performed on the Mac.

The Mac receives the Android video stream and writes the corresponding recording.

This keeps recording behavior consistent with local cameras:

- one destination folder;
- separate source files;
- unique names;
- independent recordings;
- Mac-side error reporting;
- common recording controls.

The initial Android source is video-only.

No microphone audio is sent from Android in the first version.

## Multiple Android devices

The architecture may support several connected Android phones.

Each phone uses:

- its own ADB serial;
- its own forwarding rules;
- its own local control port;
- its own local video port;
- its own control socket;
- its own video socket;
- its own packet parser;
- its own H.264 decoder;
- its own preview state;
- its own Mac-side recording state.

The same Android ports can be reused on every phone because ADB maps them to separate local Mac ports.

The Mac must never send a device-specific ADB command without the correct serial.

## Bandwidth

Total load increases with:

- resolution;
- frame rate;
- H.264 bitrate;
- number of connected phones;
- number of local cameras;
- simultaneous decoding;
- simultaneous recording;
- storage speed.

The first Android version should prioritize stable settings over maximum quality.

A practical first target may be:

    1280 × 720
    30 FPS
    hardware H.264
    moderate bitrate

Higher resolutions should be enabled only after successful device testing.

## Backpressure

Video transmission must not block the Android camera or encoder callback thread indefinitely.

The Android side should use:

- a bounded transmission queue;
- a dedicated socket-writing thread;
- frame dropping when the client cannot keep up;
- key-frame recovery after discontinuity.

The macOS side should use:

- bounded receive buffers;
- packet-size validation;
- decoder queue isolation;
- late-frame dropping for preview;
- explicit decoder restart after codec changes.

## Connection loss

The transport manager distinguishes between:

    ADB device disconnected
    ADB device offline
    forwarding missing
    Android application unavailable
    control server unavailable
    video server unavailable
    control protocol error
    invalid video packet
    encoder stopped
    decoder failed

A failure in one Android source must not interrupt:

- built-in Mac cameras;
- USB cameras connected to the Mac;
- another Android source;
- recordings from unrelated sources.

## Reconnection

After a disconnect, the Mac may:

1. mark the source unavailable;
2. close control and video sockets;
3. clear incomplete packet buffers;
4. reset decoder state;
5. wait for the same ADB serial;
6. recreate forwarding;
7. reconnect to the control server;
8. request capabilities again;
9. restore the previous valid configuration;
10. restart streaming when appropriate.

Codec configuration must be received again after every encoder or video connection restart.

## Keepalive

The control connection uses `ping` and `pong`.

Keepalive helps distinguish:

- an idle but healthy connection;
- a blocked Android process;
- a broken USB connection;
- a stale forwarding rule.

Video packets do not replace control keepalive.

## Security

The Android servers bind only to loopback.

They are reachable from the Mac only through ADB forwarding.

The first protocol does not use encryption or application-level authentication.

This is acceptable for the initial USB and ADB development transport.

The application must not expose the control or video server on:

    0.0.0.0

unless network transport is explicitly designed and secured in a future version.

## Diagnostics

List connected devices:

    ADB_LIBUSB=0 adb devices -l

Check device state:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL get-state

Test shell access:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL shell echo connected

List forwarding:

    ADB_LIBUSB=0 adb forward --list

Inspect Android logs:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL logcat -d | grep -i Webcamera

Check application process:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL shell ps | grep -i webcamera

Test a control forwarding rule:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward tcp:27283 tcp:27283

Test a video forwarding rule:

    ADB_LIBUSB=0 adb -s DEVICE_SERIAL forward tcp:27284 tcp:27284

## Logging

Useful transport logs include:

- ADB serial;
- Android device name;
- local control port;
- local video port;
- Android control port;
- Android video port;
- forwarding creation;
- control connection state;
- video connection state;
- selected camera;
- selected resolution;
- selected frame rate;
- selected bitrate;
- codec configuration received;
- first encoded frame;
- first decoded frame;
- frame sequence gaps;
- dropped frames;
- reconnect attempts;
- errors.

Logs must not contain raw camera frames.

## iPhone support

ADB transport is Android-specific.

iPhone is not supported by this USB transport.

Supporting iPhone would require a separate iOS application and a different communication system.
