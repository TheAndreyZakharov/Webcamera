# Architecture

## Overview

Webcamera is a macOS multi-camera viewer, audio monitor, and recorder.

The macOS application supports:

- the built-in Mac camera;
- USB cameras recognized by macOS;
- virtual and other video devices exposed through AVFoundation;
- simultaneous preview of multiple cameras;
- independent configuration of every selected camera;
- independent recording of every selected camera;
- per-camera microphone selection;
- live microphone monitoring;
- stereo audio level meters;
- optional mono monitoring and mono recording;
- MOV and MP4 output.

A companion Android application is planned as a focused USB camera source.

Its purpose is limited to:

- opening a camera on the Android phone;
- encoding the camera image;
- sending the video stream to the Mac over USB and ADB;
- allowing the phone to appear inside Webcamera as another selectable camera.

The Android application is not intended to duplicate the macOS recording interface, manage recordings on the phone, or become a general remote camera-control application.

Webcamera displays and records video inside its own macOS application. It does not currently register a system-wide macOS virtual camera.

## Project components

The repository contains or plans to contain:

- a macOS multi-camera application;
- an Android USB camera application;
- local AVFoundation camera discovery;
- independent capture controllers for local cameras;
- preview and recording components;
- per-camera audio configuration;
- live audio monitoring;
- ADB-based Android transport;
- an Android-to-macOS video protocol;
- an H.264 decoder for Android streams;
- development, build, and release tooling.

## macOS application architecture

The macOS application is implemented as a SwiftUI windowed application with AppKit and AVFoundation integration.

The main responsibilities are divided between:

- application state;
- camera discovery;
- camera models;
- video-format models;
- camera controllers;
- capture-session synchronization;
- video preview views;
- audio monitoring;
- recording;
- settings;
- camera tiles and preview windows.

SwiftUI views display state and send user actions to the application model.

Capture-session operations are handled outside the views.

## Application state

`AppState` owns application-level state, including:

- camera authorization;
- microphone authorization;
- discovered cameras;
- discovered audio devices;
- selected camera identifiers;
- selected video configurations;
- selected audio devices;
- per-camera recording formats;
- per-camera mono settings;
- camera controllers;
- sidebar visibility;
- recording destination;
- global recording defaults.

Every selected camera has its own `CameraController`.

A controller is created when a camera is selected and removed after its preview has been detached safely.

## Camera source model

Every local camera is represented by `CameraDeviceInfo`.

A local camera provides:

- a stable AVFoundation device identifier;
- a display name;
- a source kind;
- a reference to the underlying `AVCaptureDevice`;
- supported video configurations.

Current source kinds include:

    Built-in Mac camera
    External camera
    Android camera

Android sources will later use the same user-facing selection model, while their internal transport and decoding implementation will be different from local AVFoundation cameras.

## Video format model

A camera format is represented by `VideoFormat`.

It contains:

- width;
- height;
- frame rate;
- AVFoundation format index;
- media subtype;
- stable identifier;
- display title.

Supported video configurations are discovered separately for every camera.

The application does not invent unsupported resolutions or frame rates.

When several AVFoundation formats represent the same displayed resolution and frame rate, Webcamera prefers a suitable pixel format for capture stability.

## Multi-camera operation

The application supports several selected and running cameras at the same time.

Each camera has independent:

- capture session;
- capture queue;
- selected video format;
- selected microphone;
- mono-audio setting;
- live-monitoring state;
- audio meters;
- running state;
- recording state;
- recording file format;
- output file;
- error state.

The user can:

- select or deselect cameras;
- display selected cameras in a grid;
- open an individual camera in a separate preview window;
- start or stop one camera;
- start or stop all selected cameras;
- record one camera;
- record all running cameras;
- stop one recording without stopping the others;
- use MOV for one camera and MP4 for another;
- choose different microphones for different cameras.

The implementation must never assume that only one camera is active.

## Main window

The main macOS window contains:

- a camera sidebar;
- a multi-camera grid;
- start and stop controls;
- record-all controls;
- microphone permission controls;
- recordings-folder access;
- settings access.

The sidebar lists all cameras currently visible to AVFoundation.

Each camera can be enabled or disabled independently.

## Camera tiles

Every selected camera is displayed in its own tile.

A tile contains:

- camera name;
- camera type;
- running or recording status;
- video preview;
- video format selector;
- microphone selector;
- live-monitoring button;
- mono-audio switch;
- left and right audio meters;
- per-camera file-format selector;
- start and stop controls;
- recording controls;
- separate preview-window control;
- current microphone information;
- last recording filename;
- source-specific error messages.

A failure in one tile must not stop other camera sessions or recordings.

## Preview windows

Every selected camera can be opened in a separate macOS window.

The preview window uses the same underlying capture session as the corresponding camera tile.

Multiple preview layers may reference the same session.

Attaching or detaching a preview layer changes the AVFoundation session graph and therefore must be synchronized with session configuration, start, and stop operations.

## Capture-session synchronization

AVFoundation may modify its internal connection graph when:

- `startRunning()` is called;
- `stopRunning()` is called;
- configuration begins or commits;
- inputs are added or removed;
- outputs are added or removed;
- an `AVCaptureVideoPreviewLayer` is attached;
- an `AVCaptureVideoPreviewLayer` is detached.

Performing these operations concurrently can cause crashes or deadlocks.

Webcamera uses a per-session synchronization gate.

All session graph operations for the same `AVCaptureSession` use the same recursive lock.

This includes both:

- `CameraController`;
- `CameraPreviewNSView`.

A camera preview is detached before its controller removes the session configuration.

Controller teardown is delayed briefly after a SwiftUI tile is removed so that AppKit and Core Animation can finish dismantling the preview layer.

## Local camera capture

Every local camera uses its own `AVCaptureSession`.

The session may contain:

- one video input;
- one optional audio input;
- one movie file output;
- one audio data output for live monitoring and metering;
- one or more video preview layers.

Capture-session work is performed on a dedicated serial queue for every camera.

The main thread is used for published state and SwiftUI updates.

## Camera configuration

The user selects a video configuration separately for every camera.

Changing the selected configuration may require:

- stopping the session;
- rebuilding inputs and outputs;
- applying the selected device format;
- restarting the session.

Video format changes are disabled while that camera is recording.

The application uses only configurations reported by AVFoundation.

## Audio-device selection

Microphones are discovered through AVFoundation.

Every selected camera may use:

- no audio;
- the microphone associated with that camera;
- another system microphone;
- an audio-interface input visible to AVFoundation.

Microphone selection is independent for every camera.

When a microphone is unavailable or permission is denied, the camera may still preview and record video without audio.

## Live audio monitoring

Webcamera supports live monitoring of the microphone selected for a camera.

Live monitoring uses:

    AVCaptureAudioDataOutput
          ↓
    CMSampleBuffer
          ↓
    AVAudioPCMBuffer
          ↓
    AVAudioConverter
          ↓
    AVAudioPlayerNode
          ↓
    AVAudioEngine
          ↓
    macOS audio output

Monitoring can be enabled or disabled independently for every camera.

Live monitoring is not performed through `AVCaptureAudioPreviewOutput`, because that output does not provide the required channel conversion for reliable mono monitoring.

## Audio meters

Each camera tile displays separate left and right audio levels.

Audio levels are calculated from the PCM buffers used by the monitoring pipeline.

The displayed level is derived from the RMS value of each channel and normalized for the interface.

When mono mode is enabled:

- the monitoring signal is converted to one channel;
- the mono signal is played through both output channels;
- both meters display the resulting mono level.

Meters are reset when monitoring, audio capture, or the camera session stops.

## Mono audio

Mono mode is configured separately for every camera.

When mono is enabled:

- live monitoring is converted to a one-channel audio buffer;
- the one-channel signal is mixed to both the left and right macOS output channels;
- recording requests a one-channel AAC audio track;
- left and right meters display the same mono level.

This is useful for microphones and audio interfaces that provide a microphone only on one side of a stereo input.

Mono mode cannot be changed while that camera is recording.

## Recording subsystem

Local camera recording uses `AVCaptureMovieFileOutput`.

Every camera controller owns its own movie output and recording state.

Recording is independent for every camera.

Each recording contains:

- video from the selected camera;
- optional audio from the selected microphone;
- the selected mono or stereo audio configuration;
- the selected container format;
- a unique output filename.

Stopping one recording does not stop:

- the camera preview;
- live monitoring;
- another camera;
- another recording.

## Recording formats

The application supports:

    MOV
    MP4

MOV recordings are written directly as QuickTime movie files.

For MP4:

1. capture is written to a temporary MOV file;
2. recording finishes;
3. `AVAssetExportSession` converts the captured file to MP4;
4. the temporary MOV file is removed after successful export.

If MP4 export fails, the temporary MOV file is retained so that the recording is not lost.

## Per-camera recording format

Every selected camera can choose its own recording format.

For example:

    Camera A → MOV
    Camera B → MP4
    Camera C → MOV

The global format in Settings acts as the default format applied to cameras that do not yet have a camera-specific selection.

The global format can also be used when starting recordings for all selected cameras.

Per-camera choices remain independent.

## Recording destination

The recording destination is selected in Settings through a standard macOS folder picker.

When no custom destination is selected, Webcamera uses the user’s Downloads directory.

Every camera writes a separate file.

Filename components are sanitized before use.

Example filenames:

    2026-06-18_12-30-00_FaceTime-HD-Camera.mov
    2026-06-18_12-30-00_Logitech-C922.mp4

Existing destination files are not silently overwritten.

## Recording state and teardown

A camera cannot be reconfigured while its movie output is recording.

When the user stops or removes a camera during recording:

- Webcamera first requests the recording to stop;
- it waits for the recording delegate callback;
- it completes MOV finalization or MP4 export;
- it then stops or dismantles the capture session.

This prevents incomplete files and unsafe session changes.

## Settings

The macOS Settings window contains:

- recording destination;
- global default file format;
- an explanation that the global format applies to all cameras unless a camera-specific format is selected;
- information about camera-format reporting.

Android support is described as a USB camera-source feature rather than as a separate recording system.

## Android application scope

The Android application has one primary responsibility:

    provide the Android phone camera to the Mac as a USB camera source

The Android application will:

- request camera permission;
- list available front and rear cameras;
- allow a camera to be selected locally when needed;
- open the selected camera;
- choose a stable supported capture configuration;
- encode video as H.264;
- expose a small local control server;
- expose a video-stream server;
- send video to the Mac through ADB port forwarding;
- display basic connection and streaming status;
- run streaming in a foreground service when required.

The initial Android application will not implement:

- recording files on the phone;
- a recording gallery;
- editing;
- cloud upload;
- multi-camera recording on the phone;
- general-purpose remote camera controls;
- audio transmission;
- remote zoom, focus, exposure, or torch controls unless added in a later version.

Recording remains a macOS responsibility.

## Android source on macOS

An Android phone will appear in the macOS application as another selectable camera source.

For every connected Android phone, the Mac will own:

- one ADB device serial;
- one forwarding configuration;
- one control connection;
- one video connection;
- one H.264 decoder;
- one preview state;
- one Mac-side recording state;
- one independent error state.

The Mac will:

- discover phones through ADB;
- create port-forwarding rules;
- connect to the Android application;
- obtain basic device and stream information;
- start and stop video streaming;
- receive H.264 packets;
- decode frames using VideoToolbox;
- display decoded frames;
- record the Android source on the Mac.

## Android USB runtime flow

    Android camera
          ↓
    Android camera capture
          ↓
    MediaCodec H.264 encoder
          ↓
    Android loopback video server
          ↓
    ADB USB port forwarding
          ↓
    macOS video transport
          ↓
    VideoToolbox H.264 decoder
          ↓
    macOS preview
          ↓
    macOS recording

## Android recording behavior

The Android phone does not write Webcamera recording files.

The Mac records the received Android video stream.

This keeps the following behavior consistent across sources:

- recording destination;
- filename generation;
- recording controls;
- simultaneous recordings;
- file-format selection;
- error reporting.

The initial Android source is video-only.

Audio for Android sources may be considered separately in a future version.

## Android compatibility target

The primary Android compatibility target is:

    Meizu MX5
    Android 5.1
    API 22
    Flyme 6.2.0.0G

The implementation may evaluate both:

- Camera2;
- the legacy Camera API.

The legacy Camera API remains an important compatibility path for Android 5.1 devices with incomplete Camera2 support.

Video encoding uses `MediaCodec` and prefers a hardware H.264 encoder.

## Android configuration policy

The first Android version should prefer reliability over exposing every possible device option.

It may initially use one stable configuration chosen from:

- a supported camera output size;
- a supported frame rate;
- a compatible H.264 encoder size;
- a stable bitrate;
- tested device behavior.

The Android application reports the configuration that was actually applied.

Advanced remote controls are outside the first Android milestone.

## Android background operation

Streaming may run from an Android foreground service.

The service may own:

- camera capture;
- H.264 encoding;
- loopback TCP servers;
- wake lock;
- persistent notification;
- connection state.

The Android activity is used for:

- permission requests;
- camera selection;
- local status;
- basic diagnostics.

The screen may dim or turn off while the foreground service continues streaming, subject to Flyme power-management behavior.

## USB transport

Android communication uses ADB port forwarding over USB.

The phone-side servers bind only to loopback.

No Wi-Fi connection is required.

The transport uses separate connections for:

- control messages;
- encoded video packets.

The control protocol remains intentionally small for the first Android version.

## Threading

### macOS local cameras

Each camera has:

- one serial capture queue;
- synchronized capture-session graph access;
- independent recording state;
- an independent audio-processing queue;
- main-thread state publication.

### macOS Android sources

Each Android source will have independent:

- ADB state;
- control transport;
- video transport;
- decoder state;
- frame queue;
- preview state;
- recording state.

### Android

The Android UI runs on the main thread.

Camera capture, encoding, socket operations, and video transmission run on background threads.

Video transmission must not block camera or encoder callbacks.

## Performance

Simultaneous high-resolution sources may consume significant:

- USB bandwidth;
- memory;
- CPU;
- GPU;
- hardware decoder resources;
- storage bandwidth;
- audio resources.

The application should remain responsive when several sources are active.

Possible safeguards include:

- bounded frame queues;
- dropping late preview frames;
- limiting preview refresh rate;
- reporting decoder or capture delays;
- preventing unsupported configurations;
- isolating failures to one source.

## Reliability

The macOS application must tolerate:

- local camera disconnection;
- camera reconnection;
- external camera driver failures;
- capture-session start failure;
- preview-layer recreation;
- recording failure;
- MP4 export failure;
- microphone removal;
- unavailable recording destination;
- Android USB disconnection;
- ADB restart;
- Android application restart;
- Android encoder restart;
- incomplete video packets;
- H.264 decoder failure.

One source failure must not interrupt unrelated sources.

## iPhone scope

The project does not include an iOS capture application.

ADB transport is Android-specific and cannot be reused for iPhone.

Supporting iPhone would require:

- a separate iOS application;
- Apple signing and installation;
- another wired or network transport;
- a separate compatibility effort.

iPhone support is outside the current project scope.

## Virtual camera scope

The current application previews and records cameras only inside Webcamera.

System-wide virtual-camera output is not part of the current implementation.

A macOS Camera Extension may be considered later as a separate feature.
