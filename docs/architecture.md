# Architecture

## Overview

Webcamera is a macOS camera viewer with support for multiple video sources.

The application can display:

- video streamed from the Android Webcamera application through USB;
- the built-in Mac camera;
- connected USB cameras;
- other camera devices exposed to macOS through AVFoundation.

The user selects the active source from the camera menu in the macOS application.

The initial release displays video inside the Webcamera window.

It does not register itself as a system virtual camera.

## Main components

The project contains:

- an Android capture application;
- a macOS viewer and camera-control application;
- a shared control and video protocol;
- ADB-based USB transport;
- release and development tooling.

## Source model

All video inputs are represented by a common camera-source abstraction.

A source provides:

- a stable identifier;
- a display name;
- a source type;
- available formats;
- supported frame rates;
- available controls;
- current state;
- a stream of decoded video frames.

Source types include:

    Android phone
    Built-in Mac camera
    USB camera
    Other AVFoundation camera

This allows the user interface and preview system to work with every source through the same model.

## macOS application

The macOS application is a standard windowed application.

Its main window contains:

- a video preview;
- a camera-selection menu;
- resolution selection;
- frame-rate selection;
- source-specific controls;
- connection status;
- stream statistics;
- start and stop controls.

The camera-selection menu is placed in the window toolbar.

Changing the selected camera:

1. stops the current source;
2. releases its capture resources;
3. loads formats for the new source;
4. selects a compatible default format;
5. starts the new source;
6. updates the preview.

## Local macOS camera sources

Local cameras use AVFoundation.

The application discovers available video capture devices and observes connection changes.

For each local camera, it reads:

- supported capture formats;
- dimensions;
- pixel formats;
- frame-rate ranges;
- device position;
- transport type where available.

The user may select a supported resolution and frame rate.

The application configures the selected device format and frame duration.

Controls that are not supported by a device are hidden or disabled.

Possible local-camera controls include:

- exposure;
- focus;
- white balance;
- zoom;
- mirroring;
- rotation.

Actual availability depends on the selected camera.

## Android camera source

The Android source uses two TCP connections transported through ADB:

    Control connection
    Video connection

The Android application:

- discovers phone cameras;
- discovers supported resolutions;
- discovers frame-rate ranges;
- configures camera capture;
- encodes video as H.264;
- sends encoded video to the Mac;
- reports status and errors.

The macOS application:

- detects the Android phone;
- creates ADB forwarding rules;
- connects to the Android servers;
- receives capabilities;
- selects a configuration;
- receives H.264 packets;
- decodes them with VideoToolbox;
- publishes decoded frames to the common preview pipeline.

## Runtime flow for Android

    Android camera
          ↓
    Camera API
          ↓
    MediaCodec H.264 encoder
          ↓
    Android video server
          ↓
    ADB over USB
          ↓
    macOS video connection
          ↓
    VideoToolbox decoder
          ↓
    Common frame pipeline
          ↓
    Preview window

## Runtime flow for local cameras

    macOS camera
          ↓
    AVCaptureSession
          ↓
    AVCaptureVideoDataOutput
          ↓
    Common frame pipeline
          ↓
    Preview window

## Shared frame pipeline

All decoded or captured frames are converted into a common frame representation.

A frame contains:

    pixel buffer
    presentation timestamp
    width
    height
    source identifier

The preview does not need to know whether a frame originated from Android, the built-in camera, or a USB camera.

This separation also makes future recording, screenshots, effects, and virtual-camera output easier to add.

## Android camera implementation

The target Android platform is:

    Android 5.1
    API 22

The first implementation evaluates the legacy Camera API and Camera2 support available on the Meizu MX5.

Camera2 is used only if the device implementation is sufficiently functional.

The legacy Camera API remains available as a compatibility path.

Video encoding uses `MediaCodec`.

The application prefers a hardware H.264 encoder.

## Camera capability discovery

Android reports only configurations that can be used by the complete pipeline.

A candidate configuration contains:

    camera identifier
    facing direction
    width
    height
    frame rate
    encoder
    bitrate range

Resolution options are created from the intersection of camera and encoder capabilities.

The application does not assume 4K support.

## 4K support

4K is exposed only when:

- the selected phone camera provides the required output size;
- the H.264 encoder accepts that size;
- the requested frame rate is supported;
- the encoder starts successfully;
- the stream remains stable.

The macOS preview supports large frames, but the source determines whether 4K is available.

Local macOS and USB cameras expose only the formats reported by AVFoundation.

## Android background operation

Streaming runs from an Android foreground service.

The service owns:

- camera capture;
- the video encoder;
- TCP servers;
- the wake lock;
- the persistent notification.

The activity is used for:

- permissions;
- local preview;
- source configuration;
- status display.

The activity may hide or stop its local preview while streaming continues.

The screen is allowed to dim or turn off.

Flyme-specific power management behavior must be tested on the target phone.

## Screen and thermal behavior

Keeping the phone screen off reduces display power and heat, but camera capture and H.264 encoding still generate heat.

The Android application monitors failures and may later report:

- encoder errors;
- dropped frames;
- device temperature where available;
- capture restarts.

The application does not promise unlimited 4K operation.

## Control protocol

Control messages use newline-delimited JSON.

Important message types include:

    hello
    capabilities
    configure
    start
    stop
    status
    ping
    pong
    error

## Video protocol

Video data uses framed binary H.264 packets.

The stream includes:

- codec configuration;
- key frames;
- regular frames;
- timestamps;
- sequence numbers.

The macOS decoder is recreated after:

- source changes;
- resolution changes;
- codec configuration changes;
- stream restart;
- transport reconnection.

## Threading

### Android

The Android UI runs on the main thread.

Camera callbacks, encoder processing, and network operations use background threads.

Video writes must not block the camera callback thread.

### macOS

Camera discovery and UI state are coordinated by the application model.

Local capture uses dedicated AVFoundation queues.

Android transport uses Network framework or dedicated socket queues.

VideoToolbox decoding runs outside the main UI thread.

Preview updates are dispatched safely to the rendering layer.

## Reliability

The application must recover from:

- USB cable disconnection;
- ADB daemon restart;
- Android application restart;
- Android encoder restart;
- camera removal;
- USB camera connection;
- local camera becoming unavailable;
- malformed control messages;
- incomplete video packets;
- decoder failure;
- format changes.

The active source reports explicit states:

    unavailable
    connecting
    configuring
    streaming
    stopped
    failed

## iPhone scope

The project does not include an iOS 12 wired camera application.

The Android wired transport relies on ADB and cannot be reused for iPhone.

Older iPhones may be considered in a separate project using a different transport, most likely local networking.

## Virtual camera scope

The first version shows video only inside the Webcamera application.

System-wide virtual-camera output is intentionally postponed.

The common frame pipeline is designed so a Camera Extension can be added later without replacing the source implementations.
