# Architecture

## Overview

Webcamera is a multi-source camera viewer, controller, and recorder for macOS.

The application can work with:

- the built-in Mac camera;
- USB cameras recognized by macOS;
- other cameras exposed through AVFoundation;
- one or more Android phones connected through USB and ADB.

The user can select one camera for a large preview or enable multiple sources and display them simultaneously in a grid.

Each enabled source can also be recorded independently.

The initial application displays and records camera feeds inside Webcamera. It does not register a system-wide virtual camera.

## Main components

The project contains:

- a macOS multi-camera viewer and recorder;
- an Android camera capture application;
- a common macOS camera-source abstraction;
- a shared Android control and video protocol;
- ADB-based USB transport;
- video decoding and recording components;
- build, development, and release tooling.

## Source model

Every available camera is represented by a common camera-source abstraction.

A source provides:

- a stable identifier;
- a display name;
- a source type;
- connection state;
- available video formats;
- supported frame-rate ranges;
- available camera controls;
- current configuration;
- a stream of video frames;
- recording state;
- performance statistics.

Source types include:

    Android phone camera
    Built-in Mac camera
    USB camera
    Other AVFoundation camera

The macOS interface uses the same source model regardless of how frames are produced.

## Multi-source operation

The application supports multiple active sources.

Each source has its own:

- capture session;
- selected camera;
- resolution;
- frame rate;
- controls;
- preview state;
- recording session;
- output file;
- statistics;
- error state.

The user can:

- display one selected camera;
- display several cameras in a grid;
- start or stop each source independently;
- record one selected source;
- record several sources simultaneously;
- stop one recording without interrupting other recordings.

The implementation must not assume that only one camera is active.

## macOS application

The macOS application is a standard windowed application.

Its main window contains:

- a toolbar;
- a camera-source menu;
- a source-selection panel;
- a single-source or grid preview;
- format and frame-rate controls;
- source-specific camera controls;
- recording controls;
- recording destination controls;
- connection information;
- performance statistics.

The toolbar includes a camera menu that lists all discovered sources.

The user can mark one or more cameras as active.

## Preview layouts

The application supports at least two preview modes:

### Single preview

One selected source fills the main preview area.

This mode is intended for detailed monitoring and camera configuration.

### Grid preview

Several active sources are displayed at the same time.

The grid adjusts to the number of selected sources.

Each preview tile shows:

- source name;
- connection state;
- current resolution;
- current FPS;
- recording indicator;
- source error when present.

A source failure must not stop previews or recordings from other sources.

## Local macOS camera sources

Local cameras use AVFoundation.

The application discovers available video devices and observes connection changes.

For each device, it reads:

- supported formats;
- dimensions;
- pixel formats;
- frame-rate ranges;
- device position;
- transport information where available;
- supported camera controls.

The application configures only values reported by the selected device.

Possible controls include:

- resolution;
- frame rate;
- video zoom;
- focus mode;
- focus point;
- exposure mode;
- exposure point;
- exposure bias;
- white balance;
- mirroring;
- rotation.

Controls unavailable on a device are hidden or disabled.

Not every USB camera exposes manual controls through AVFoundation.

## Android camera source

Every Android phone is represented as a separate camera source.

An Android device uses:

- one ADB device serial;
- one control connection;
- one video connection;
- one decoder;
- one set of camera capabilities;
- one selected phone camera;
- one recording state on the Mac.

The Android application:

- discovers front and rear cameras;
- discovers supported resolutions;
- discovers supported frame rates;
- reports zoom support and zoom range;
- reports focus modes;
- reports flash and torch support;
- configures camera capture;
- encodes video as H.264;
- sends encoded frames through USB;
- receives control commands from the Mac;
- reports errors and streaming statistics.

The macOS application:

- detects connected Android devices;
- creates ADB forwarding rules;
- connects to Android control and video servers;
- requests capabilities;
- sends configuration and runtime controls;
- decodes H.264 through VideoToolbox;
- publishes decoded frames to the common frame pipeline.

## Android USB runtime flow

    Android camera
          ↓
    Camera controller
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
    Preview and recording

## Local camera runtime flow

    macOS or USB camera
          ↓
    AVCaptureSession
          ↓
    AVCaptureVideoDataOutput
          ↓
    Common frame pipeline
          ↓
    Preview and recording

## Shared frame pipeline

All captured or decoded frames are represented by a common frame structure.

A frame contains:

    source identifier
    pixel buffer
    presentation timestamp
    width
    height
    rotation
    mirroring state

The shared frame pipeline distributes frames to:

- the preview renderer;
- the recording subsystem;
- performance-statistics collectors;
- possible future effects;
- a possible future virtual-camera extension.

Preview rendering and recording must not block source capture threads.

## Recording subsystem

Recording is performed on the Mac.

Each active recording has its own recording session.

A recording session contains:

- source identifier;
- destination URL;
- container format;
- video codec;
- width;
- height;
- frame rate;
- start timestamp;
- written frame count;
- dropped frame count;
- recording state.

The user chooses a destination directory through a standard macOS folder picker.

The selected directory may be remembered using a security-scoped bookmark when sandboxing requires it.

Each camera is written to a separate file.

Example filenames:

    Webcamera_Meizu-MX5_Rear_2026-06-18_12-30-00.mp4
    Webcamera_FaceTime-HD-Camera_2026-06-18_12-30-00.mp4

Simultaneous recording creates one file per source.

Stopping one recording does not stop its preview or other recordings.

## Recording format

The initial recording container is:

    MP4

The preferred video codec is:

    H.264

Local cameras may be encoded on the Mac using AVAssetWriter and VideoToolbox.

Android streams already arrive as H.264, but the Mac may either:

- remux compatible encoded frames into MP4;
- decode and re-encode frames;
- use a fallback recording path when timestamps or codec data are incompatible.

The initial implementation may use decoded pixel buffers and a common Mac-side writer for consistency.

## Camera controls

The common source-control model includes optional controls for:

- resolution;
- frame rate;
- zoom;
- focus mode;
- autofocus trigger;
- focus point;
- exposure mode;
- exposure point;
- exposure compensation;
- white balance;
- mirroring;
- rotation;
- torch or flashlight;
- bitrate for Android video transport.

Every control declares whether it is:

- supported;
- readable;
- writable;
- available during streaming;
- available only after capture restart.

The interface must not display unsupported controls as functional.

## Android flashlight and torch

The Android rear camera may expose flash modes.

When supported, the Mac can request:

    off
    torch
    auto

The `torch` mode keeps the phone light enabled continuously while streaming.

Torch availability depends on:

- the selected camera;
- Android camera API support;
- Flyme firmware;
- the current capture mode;
- device temperature.

If the camera or firmware rejects the request, Android reports an error and the Mac returns the control to its previous state.

The torch control is not shown for cameras that do not report flash support.

## Zoom

Zoom is source-specific.

Android reports:

- whether zoom is supported;
- minimum zoom;
- maximum zoom;
- supported zoom steps or ratios.

Local AVFoundation cameras report their supported video zoom factor range.

The Mac interface normalizes zoom controls while preserving the actual source limits.

Digital zoom may reduce image quality.

## Focus

A source may support:

- locked focus;
- continuous autofocus;
- one-time autofocus;
- manual lens position;
- focus point selection.

Android 5.1 devices may expose only a subset of these options.

USB cameras often do not expose focus control through AVFoundation.

## Android camera implementation

The Android target platform is:

    Android 5.1
    API 22

The implementation evaluates both:

- Camera2;
- the legacy Camera API.

Camera2 is used only when its device implementation is sufficiently complete and stable.

The legacy Camera API remains the compatibility path for the Meizu MX5.

Video encoding uses MediaCodec and prefers a hardware H.264 encoder.

## Camera capability discovery

A usable Android configuration is the intersection of:

- camera output sizes;
- camera frame-rate ranges;
- encoder input sizes;
- encoder frame-rate support;
- encoder bitrate support;
- tested device stability.

The Android application reports only configurations that are expected to be usable.

Configuration may still fail at runtime and must return a clear error.

## 4K support

4K is displayed only when the complete selected-source pipeline supports it.

For Android this requires:

- a compatible camera output;
- a compatible H.264 encoder;
- a supported frame rate;
- successful capture and encoder startup;
- stable USB transport;
- acceptable thermal behavior.

For local cameras, 4K is shown only when AVFoundation reports a corresponding format.

Webcamera does not invent or upscale unsupported source formats.

## Android background operation

Android streaming runs from a foreground service.

The service owns:

- camera capture;
- H.264 encoding;
- TCP servers;
- wake lock;
- persistent notification;
- camera controls.

The activity is used for:

- camera permission;
- local preview;
- status display;
- diagnostics.

The activity may stop drawing its local preview while the service continues streaming.

The screen may dim or turn off.

Flyme power-management behavior must be tested on the target phone.

## Screen and thermal behavior

Turning off the phone screen reduces display power consumption but does not remove heat generated by the camera and encoder.

The Android application reports or logs when possible:

- encoder errors;
- camera errors;
- dropped frames;
- stream restarts;
- thermal information;
- torch state.

The application may disable the torch or stop the stream if the platform reports a critical failure.

## Control protocol

Control messages use newline-delimited JSON.

The protocol supports:

    device identity
    capability discovery
    camera selection
    resolution selection
    frame-rate selection
    bitrate selection
    zoom control
    focus control
    exposure control
    flash and torch control
    stream start and stop
    status messages
    keepalive
    errors

## Video protocol

Android video uses framed binary H.264 packets.

The stream contains:

- codec configuration;
- key frames;
- regular frames;
- timestamps;
- sequence numbers;
- end-of-stream packets.

Every Android source has an independent decoder.

## Threading

### Android

The Android UI runs on the main thread.

Camera callbacks, encoder output, and network operations run on background threads.

Video transmission must not block the camera or encoder callback threads.

### macOS

Each local camera has a dedicated capture session and processing queue.

Each Android camera has independent:

- transport queues;
- protocol buffers;
- decoder state;
- frame pipeline.

Recording uses independent writing queues.

Preview updates are delivered safely to the rendering layer.

The main thread is reserved for application state and interface updates.

## Performance management

Simultaneous high-resolution sources can consume significant:

- USB bandwidth;
- memory;
- CPU;
- GPU;
- hardware encoder and decoder resources;
- storage bandwidth.

The application must remain responsive when several cameras are active.

Possible safeguards include:

- limiting preview refresh rate;
- reducing inactive tile rendering rate;
- bounding frame queues;
- dropping late preview frames;
- displaying performance warnings;
- preventing unsupported recording combinations;
- allowing separate preview and recording quality.

## Reliability

The application must tolerate:

- Android USB disconnection;
- ADB daemon restart;
- Android application restart;
- Android encoder restart;
- local camera removal;
- USB camera insertion;
- camera becoming unavailable;
- malformed messages;
- incomplete video packets;
- decoder failure;
- writer failure;
- insufficient disk space;
- destination-folder loss;
- format changes;
- one source failing while others continue.

Each source reports an independent state:

    unavailable
    connecting
    configuring
    streaming
    recording
    stopped
    failed

Recording state is tracked separately from streaming state.

## iPhone scope

The current project does not include a wired iOS 12 capture application.

The Android USB transport depends on ADB and cannot be reused for iPhone.

Old iPhone support would require a separate iOS application, signing, installation, and another transport implementation.

It is outside the current project scope.

## Virtual camera scope

The initial version shows and records video only inside Webcamera.

System-wide virtual-camera output is postponed.

The common frame pipeline allows a Camera Extension to be added later without rewriting source capture, Android transport, preview, and recording systems.
