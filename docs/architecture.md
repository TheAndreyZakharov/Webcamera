# Webcamera Architecture

## Overview

Webcamera is a macOS multi-camera preview and recording application with a companion Android camera source.

The project currently supports:

- the built-in Mac camera;
- external USB cameras recognized by macOS;
- virtual cameras exposed through AVFoundation;
- Android phones connected through USB and ADB;
- simultaneous preview of several selected cameras;
- independent configuration of every camera;
- independent recording of every camera;
- recording all running cameras at once;
- per-camera video format selection;
- per-camera microphone selection;
- phone microphone audio for Android sources;
- macOS microphone audio for Android sources;
- optional recording without audio;
- optional mono recording;
- live audio monitoring for local AVFoundation cameras;
- left and right audio meters for local cameras;
- MOV and MP4 recording;
- independent recording filenames and states;
- separate preview windows;
- Android front and rear camera selection;
- Android torch control where supported;
- global defaults for recording format and microphone.

Webcamera does not currently register a system-wide macOS virtual camera.

All previews and recordings are handled inside the Webcamera macOS application.

---

## Repository components

The repository contains:

```text
Webcamera/
├── .github/
│   └── workflows/
│       └── build.yml
├── android-app/
├── docs/
│   ├── architecture.md
│   ├── development.md
│   └── usb-transport.md
├── macos-app/
│   └── Webcamera/
│       ├── Webcamera.xcodeproj
│       └── Webcamera/
├── scripts/
│   ├── build-release.sh
│   ├── check-environment.sh
│   ├── install-android.sh
│   ├── run-macos.sh
│   └── test-usb-transport.sh
├── shared/
│   └── protocol/
│       └── protocol.md
└── release/
```

The main runtime components are:

- the macOS SwiftUI application;
- the Android camera application;
- AVFoundation-based local camera capture;
- ADB-based Android discovery and transport;
- TCP control and media connections;
- VideoToolbox H.264 decoding;
- macOS-side Android recording;
- local-camera recording through AVFoundation.

---

# macOS application

## Application entry point

The macOS application starts in:

```text
macos-app/Webcamera/Webcamera/App/WebcameraApp.swift
```

`WebcameraApp` creates one shared `AppState` instance and injects it into:

- the main application window;
- individual camera preview windows;
- the Settings window.

The application provides:

- the main camera grid;
- a separate preview window for each camera;
- application commands for refreshing, starting, stopping, and recording;
- a Settings scene.

---

## Application state

Application-wide state is owned by:

```text
macos-app/Webcamera/Webcamera/App/AppState.swift
```

`AppState` is a `@MainActor` `ObservableObject`.

It manages:

- camera authorization;
- microphone authorization;
- local camera discovery;
- Android device discovery;
- audio device discovery;
- selected camera identifiers;
- selected video configurations;
- selected microphones;
- selected recording formats;
- selected mono-audio states;
- local camera controllers;
- Android camera controllers;
- Android controller subscriptions;
- sidebar visibility;
- Android discovery errors;
- recording destination;
- global recording defaults.

The principal collections are:

```swift
cameras: [CameraDeviceInfo]

audioDevices: [AudioDeviceInfo]

selectedCameraIDs: Set<String>

selectedConfigurationIDs: [String: String]

selectedAudioDeviceIDs: [String: String]

selectedRecordingFormats: [String: RecordingFileFormat]

selectedMonoAudioStates: [String: Bool]

controllers: [String: CameraController]

androidControllers: [String: AndroidCameraController]
```

Local and Android cameras use different controller implementations, but they share the same user-facing selection model.

---

## Camera source model

Camera sources are represented by:

```text
macos-app/Webcamera/Webcamera/Models/CameraDeviceInfo.swift
```

The supported source kinds are:

```swift
enum CameraSourceKind {
  case builtIn
  case external
  case android
}
```

### Built-in cameras

Built-in Mac cameras use:

```swift
AVCaptureDevice.DeviceType.builtInWideAngleCamera
```

### External cameras

USB and virtual cameras exposed by AVFoundation use:

```swift
AVCaptureDevice.DeviceType.external
```

### Android cameras

Each connected ADB device is represented as one Android camera source.

An Android source identifier is created from the ADB serial:

```text
android:<ADB_SERIAL>
```

The Android camera model contains:

- a stable source identifier;
- the phone display name;
- the Android source kind;
- default selectable stream formats;
- the original ADB serial.

Android sources do not contain an `AVCaptureDevice`.

They are handled by `AndroidCameraController`.

---

## Camera discovery

### Local camera discovery

Local cameras are discovered through:

```swift
AVCaptureDevice.DiscoverySession
```

The discovery session searches for:

- built-in wide-angle cameras;
- external cameras;
- AVFoundation-compatible virtual cameras.

For every discovered local camera, Webcamera stores:

- `uniqueID`;
- localized name;
- source kind;
- `AVCaptureDevice`;
- supported `VideoFormat` values.

### Android discovery

Android devices are discovered with:

```text
adb devices -l
```

`ADBController.connectedDevices()` parses:

- the device serial;
- model;
- product;
- device name;
- connection state.

Only devices in the `device` state are accepted.

Offline and unauthorized devices are ignored.

Local cameras are preserved even when ADB discovery fails.

---

## Refresh behavior

`AppState.refreshCameras()` performs two stages:

1. immediately discovers local AVFoundation cameras;
2. asynchronously discovers Android devices through ADB.

The final camera list combines:

```text
local cameras + Android cameras
```

Camera ordering is:

1. built-in cameras;
2. external cameras;
3. Android cameras.

Existing selections are preserved when the corresponding source is still available.

Unavailable controllers are removed safely.

---

# Video formats

## VideoFormat model

Camera configurations are represented by:

```text
macos-app/Webcamera/Webcamera/Models/VideoFormat.swift
```

A `VideoFormat` contains:

- stable identifier;
- width;
- height;
- frame rate;
- underlying AVFoundation format index;
- media subtype.

The display title uses:

```text
WIDTH × HEIGHT · FPS
```

Example:

```text
1920 × 1080 · 30 FPS
```

---

## Local formats

For local cameras, supported formats are read directly from the camera driver.

Webcamera examines:

- format dimensions;
- media subtype;
- supported frame-rate ranges;
- common frame rates;
- format index.

Duplicate displayed configurations are removed.

When several device formats expose the same resolution and frame rate, the application prefers stable capture pixel formats.

The application does not invent local camera configurations that are not reported by AVFoundation.

---

## Android formats

The macOS application currently exposes the following Android stream choices:

```text
1920 × 1080 · 30 FPS
1280 × 720 · 30 FPS
960 × 540 · 30 FPS
640 × 480 · 30 FPS
```

The selected Android format is sent to `AndroidCameraController`, which sends the selected width, height, frame rate, and bitrate to the Android application.

The Android application may report or apply device-dependent behavior, but the selected format remains source-specific.

Changing the Android format triggers Android stream reconfiguration.

---

# Audio sources

## AudioDeviceInfo

Audio devices are represented by `AudioDeviceInfo`.

The available logical source types are:

```text
No Audio
Phone Microphone
macOS AVFoundation audio devices
```

### No Audio

`No Audio` disables audio recording for the selected source.

Its internal identifier is:

```text
__webcamera_no_audio__
```

### Phone Microphone

`Phone Microphone` is available only for Android camera sources.

Its internal identifier is:

```text
__webcamera_phone_audio__
```

Phone audio arrives in the Android media stream.

It is not represented by an `AVCaptureDevice`.

### macOS microphones

macOS microphones are discovered using:

```swift
AVCaptureDevice.DiscoverySession(
  deviceTypes: [.microphone],
  mediaType: .audio,
  position: .unspecified
)
```

This may include:

- the built-in Mac microphone;
- a webcam microphone;
- a USB microphone;
- an audio interface;
- another AVFoundation-compatible audio device.

---

## Audio choices for local cameras

A local camera can use:

- No Audio;
- any microphone visible through AVFoundation.

The selected microphone is added directly to that camera’s `AVCaptureSession`.

Each local camera may use a different microphone.

---

## Audio choices for Android cameras

An Android camera can use:

- Phone Microphone;
- No Audio;
- any microphone visible through AVFoundation on the Mac.

When `Phone Microphone` is selected, AAC audio packets received from Android are written into the Android recording.

When a macOS microphone is selected, `AndroidRecorder` creates an independent audio capture session and writes that audio alongside the decoded Android video.

This allows an Android camera recording to use:

- the phone microphone;
- the MacBook microphone;
- a USB microphone;
- an audio interface;
- no audio.

---

## Default audio selection

For Android sources, the default audio source is:

```text
Phone Microphone
```

For local cameras, Webcamera attempts to match camera and microphone names.

For example, a webcam and its integrated microphone may share part of the same device name.

When no suitable match is found, the application may use `No Audio`.

---

# Local camera controller

Local cameras are controlled by:

```text
macos-app/Webcamera/Webcamera/CameraControl/CameraController.swift
```

Every selected local camera receives an independent `CameraController`.

Each controller owns:

- one `AVCaptureSession`;
- one serial capture queue;
- one audio processing queue;
- one video input;
- one optional audio input;
- one `AVCaptureMovieFileOutput`;
- one `AVCaptureAudioDataOutput`;
- one `AVAudioEngine`;
- one `AVAudioPlayerNode`;
- independent state and errors.

The implementation never assumes that only one local camera exists.

---

## Local capture session

A configured local camera session may contain:

```text
AVCaptureDeviceInput for video
AVCaptureDeviceInput for audio
AVCaptureMovieFileOutput
AVCaptureAudioDataOutput
AVCaptureVideoPreviewLayer instances
```

The movie output is used for recording.

The audio data output is used for:

- live monitoring;
- PCM conversion;
- audio-level calculation.

---

## Local camera configuration

Configuring a local camera may:

1. create a video input;
2. create an optional audio input;
3. remove old inputs and outputs;
4. add the new video input;
5. add the new audio input;
6. apply the selected video format;
7. add the movie output;
8. add the audio data output;
9. configure mono or stereo recording;
10. start the session.

Configuration changes are rejected while recording.

---

# Capture-session synchronization

## Why synchronization is required

AVFoundation changes the internal capture-session graph during:

- `startRunning()`;
- `stopRunning()`;
- `beginConfiguration()`;
- `commitConfiguration()`;
- input changes;
- output changes;
- preview-layer attachment;
- preview-layer detachment.

Running these operations concurrently can cause:

- crashes;
- deadlocks;
- invalid connection state;
- session graph corruption.

---

## CaptureSessionGate

Synchronization is implemented in:

```text
macos-app/Webcamera/Webcamera/Preview/VideoPreviewView.swift
```

`CaptureSessionGate` owns a recursive lock for every `AVCaptureSession`.

All operations that modify the same session graph use the same per-session lock.

The gate is used by:

- `CameraController`;
- `CameraPreviewNSView`.

This guarantees that preview-layer changes do not race with session configuration, startup, shutdown, or teardown.

---

## Delayed controller teardown

When a local camera is deselected, the controller is not removed immediately.

`AppState` schedules controller removal after a short delay.

This gives SwiftUI and AppKit time to:

1. remove the tile;
2. dismantle `VideoPreviewView`;
3. detach `AVCaptureVideoPreviewLayer`;
4. finish Core Animation updates;
5. clear the controller safely.

If the camera is selected again before teardown, the pending removal is cancelled.

---

# Local camera preview

Local previews use:

```swift
AVCaptureVideoPreviewLayer
```

`VideoPreviewView` is an `NSViewRepresentable` wrapper around `CameraPreviewNSView`.

The preview layer uses:

```swift
.resizeAspect
```

A single local capture session can be displayed in:

- the main camera tile;
- a separate preview window.

Each preview layer references the same underlying camera session.

---

# Local audio monitoring

Live monitoring is available for local AVFoundation cameras.

The pipeline is:

```text
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
```

Monitoring is independent for every local camera.

Headphones are recommended to prevent acoustic feedback.

Android phone audio is currently used for recording, but is not routed through the local-camera live-monitor pipeline.

---

## Audio meters

Local camera tiles display separate left and right audio meters.

The controller:

1. receives PCM audio;
2. reads channel samples;
3. calculates RMS;
4. converts RMS to decibels;
5. normalizes the result to `0...1`;
6. publishes left and right levels.

When mono mode is enabled, both meters show the same level.

Meters are reset when:

- monitoring stops;
- the camera stops;
- the audio input disappears;
- the controller is removed.

---

## Mono audio

Mono recording is selected per camera.

For local cameras, mono mode affects:

- live monitoring;
- audio conversion;
- output channel count;
- AAC recording settings;
- audio meters.

For Android recordings using a macOS microphone, mono mode selects one output channel in the encoded recording.

Phone microphone AAC is accepted in the format supplied by the Android application. The mono switch is disabled when the phone microphone is selected.

Mono mode cannot be changed while the corresponding camera is recording.

---

# Local camera recording

Local camera recording uses:

```swift
AVCaptureMovieFileOutput
```

Each local camera controller owns its own recording output and state.

A local recording contains:

- video from that camera;
- optional selected microphone audio;
- mono or stereo AAC;
- the selected file format;
- a unique filename.

Stopping one recording does not stop:

- the camera preview;
- another local camera;
- an Android source;
- another recording.

---

## MOV recording

MOV recordings are written directly to the selected recording directory.

---

## MP4 recording

Local MP4 recording uses this process:

```text
AVCaptureMovieFileOutput
        ↓
temporary MOV
        ↓
AVAssetExportSession
        ↓
final MP4
```

The temporary MOV is removed after successful export.

If export fails, the MOV is retained so the recorded media is not lost.

---

# Android camera controller

Android sources are controlled by:

```text
macos-app/Webcamera/Webcamera/CameraControl/AndroidCameraController.swift
```

Every selected Android source receives its own `AndroidCameraController`.

The controller owns:

- the ADB device record;
- one control connection;
- one media connection;
- one H.264 decoder;
- one Android recorder;
- camera capability state;
- selected phone camera;
- selected Android video format;
- torch state;
- connection state;
- stream state;
- recording state;
- phone-audio state;
- decoded pixel buffers;
- source-specific errors.

---

## Android connection sequence

A normal connection follows this sequence:

1. start the Android activity;
2. attempt to start the Android service;
3. wait for Android startup;
4. create ADB forwarding for the control port;
5. create ADB forwarding for the media port;
6. connect to `127.0.0.1:27283`;
7. connect to `127.0.0.1:27284`;
8. request capabilities;
9. receive camera information;
10. select a phone camera;
11. send stream configuration;
12. send `start`;
13. receive H.264 and AAC packets;
14. decode video;
15. display frames;
16. optionally record on the Mac.

---

## Android control connection

The control connection uses newline-delimited JSON over TCP.

It is implemented in:

```text
macos-app/Webcamera/Webcamera/Transport/ControlConnection.swift
```

It handles:

- connection state;
- outgoing JSON messages;
- newline framing;
- partial reads;
- multiple messages per read;
- JSON parsing;
- connection errors.

Every outgoing control message includes:

```text
version
type
sequence
timestamp
```

---

## Android media connection

The binary media connection is implemented in:

```text
macos-app/Webcamera/Webcamera/Transport/VideoConnection.swift
```

Despite its historical class name, this connection carries both video and phone audio packets.

Supported packet types are:

```text
1  videoConfiguration
2  videoFrame
3  audioConfiguration
4  audioFrame
5  endOfStream
```

The receiver supports:

- partial TCP headers;
- partial payloads;
- several packets in one read;
- packet-size validation;
- stream timestamps;
- sequence values;
- key-frame flags;
- codec-configuration flags.

The maximum accepted payload size is:

```text
32 MiB
```

---

# Android video decoding

Android video is encoded as H.264.

macOS decoding is implemented in:

```text
macos-app/Webcamera/Webcamera/Decoder/H264Decoder.swift
```

The decoder:

1. receives H.264 Annex B codec configuration;
2. extracts SPS and PPS;
3. creates a `CMVideoFormatDescription`;
4. creates a `VTDecompressionSession`;
5. converts frame payloads from Annex B to AVCC;
6. creates `CMSampleBuffer` instances;
7. submits frames to VideoToolbox;
8. publishes decoded `CVPixelBuffer` frames.

The decoder uses a dedicated serial queue.

Decoded frames are published to the main thread.

---

## Android preview

Android frames are displayed through:

```text
AndroidVideoPreviewView
AndroidPixelBufferNSView
```

The preview converts `CVPixelBuffer` to `CIImage`, creates a `CGImage`, and assigns it to the backing layer.

The layer uses aspect-fit display behavior.

Android previews can appear in:

- the main camera grid;
- a separate preview window.

---

# Android camera selection

Capabilities returned by Android contain available phone cameras.

The UI exposes them as camera options.

Typical camera choices are:

```text
Rear Camera
Front Camera
```

Changing the phone camera:

1. stops the current Android stream when needed;
2. updates the selected Android camera ID;
3. sends a new configuration;
4. restarts streaming if the source was running.

The rear camera is preferred as the default when available.

---

# Android torch control

Android camera capability data includes:

- flash availability;
- torch availability;
- camera facing.

The macOS UI displays a torch button when the selected camera supports it.

Torch changes use the control message:

```text
setFlashMode
```

Values include:

```text
torch
off
```

Android responds with a `flashStatus` control message.

The macOS controller updates:

- whether torch is enabled;
- whether the command was accepted;
- any error message returned by the phone.

Torch state is reset when:

- the camera changes;
- streaming stops;
- the source disconnects.

---

# Phone microphone audio

Android may send AAC audio in the same media connection as H.264 video.

The media stream sends:

```text
audioConfiguration
audioFrame
```

When audio configuration is received:

- phone audio is marked available;
- the AAC configuration is passed to `AndroidRecorder`;
- the Android tile can enable recording with the phone microphone.

Phone audio recording requires the codec configuration to arrive before recording starts.

If the phone microphone is selected but the audio configuration has not arrived, recording is disabled or rejected with an explicit error.

---

# Android recording

Android recordings are created on macOS by:

```text
macos-app/Webcamera/Webcamera/Recording/AndroidRecorder.swift
```

The phone itself does not create the final Webcamera recording file.

`AndroidRecorder` combines:

- decoded Android video frames;
- phone AAC audio or macOS microphone audio;
- timestamps normalized to the start of recording;
- the selected MOV or MP4 container.

The recorder uses:

```swift
AVAssetWriter
```

---

## Android video recording

Decoded `CVPixelBuffer` frames are appended through:

```swift
AVAssetWriterInputPixelBufferAdaptor
```

The video track uses H.264 output settings.

Each frame timestamp is normalized relative to the first recorded video frame.

---

## Android phone-audio recording

When `Phone Microphone` is selected:

1. Android sends AAC codec configuration;
2. macOS creates a `CMAudioFormatDescription`;
3. compressed AAC packets are wrapped in `CMSampleBuffer`;
4. packets are retimed relative to the first recorded phone-audio packet;
5. packets are appended directly to the asset writer.

The current phone stream uses AAC Low Complexity audio.

---

## Android recording with a macOS microphone

When a macOS microphone is selected:

1. `AndroidRecorder` creates a separate `AVCaptureSession`;
2. the selected microphone is added as an input;
3. an `AVCaptureAudioDataOutput` receives audio;
4. audio sample buffers are retimed;
5. the writer encodes AAC audio;
6. the audio track is written with the Android video.

Mono or stereo output is controlled by the per-camera mono setting.

---

## Android MOV and MP4 output

Android recording uses `AVAssetWriter` with the selected file type:

```text
.mov
.mp4
```

Unlike local AVFoundation camera recording, Android MP4 can be written directly by `AVAssetWriter`.

Every Android source has independent:

- recording state;
- destination file;
- last recording URL;
- errors.

---

# User interface

## Main window

The main window contains:

- camera sidebar;
- toolbar;
- adaptive multi-camera grid;
- permission controls;
- global start and stop controls;
- global recording controls;
- recordings-folder button;
- Settings button.

---

## Sidebar

The sidebar lists all current sources:

- built-in cameras;
- external and virtual cameras;
- Android devices.

Every source can be selected independently.

The selected count is displayed at the bottom.

---

## Local camera tile

A local-camera tile contains:

- source name;
- source icon;
- status badge;
- video preview;
- video format selector;
- microphone selector;
- recording format selector;
- mono switch;
- live-monitor switch;
- left and right audio meters;
- start and stop controls;
- recording controls;
- preview-window button;
- active microphone description;
- last recording filename;
- error display.

---

## Android camera tile

An Android-camera tile contains:

- phone source name;
- Android source icon;
- connection or recording status;
- decoded video preview;
- phone-camera selector;
- Android video format selector;
- audio source selector;
- recording format selector;
- mono switch when applicable;
- start and stop controls;
- recording controls;
- torch control;
- preview-window button;
- phone-audio availability information;
- selected microphone information;
- last recording filename;
- Android connection and stream status;
- source-specific errors.

---

## Global actions

The application supports:

```text
Start All
Stop All
Record All
Stop All Recordings
```

`Record All` starts a separate recording for every running and recordable selected source.

Each source uses its own:

- microphone;
- format;
- mono setting;
- file;
- recorder;
- recording state.

---

# Settings

The Settings window manages:

- recording destination;
- default recording format;
- application of the default format to all selected cameras;
- default microphone;
- application of one microphone to all selected cameras;
- audio behavior information;
- camera-format information.

The recording destination is stored in `UserDefaults`.

When no custom path is set, the default destination is:

```text
~/Downloads
```

The global recording format acts as the default for newly selected sources.

It can also be explicitly applied to all selected sources.

The common microphone setting can be applied to all compatible selected sources.

`Phone Microphone` remains an Android-specific option and is not assigned to local AVFoundation cameras.

---

# Recording filenames

Recording filenames contain:

- date;
- time;
- sanitized camera name;
- file extension.

Example:

```text
2026-06-18_12-30-00_FaceTime-HD-Camera.mov
2026-06-18_12-30-05_Logitech-C922.mp4
2026-06-18_12-31-10_Meizu-MX5-Camera.mov
```

Unsafe filename characters are replaced.

Every source writes a separate file.

---

# ADB integration

ADB support is implemented in:

```text
macos-app/Webcamera/Webcamera/Transport/ADBController.swift
```

`ADBController` can:

- locate the ADB executable;
- list connected devices;
- verify a device is connected;
- create forwarding rules;
- remove forwarding rules;
- start the Android application;
- start the Android service.

ADB executable search paths include:

```text
/opt/homebrew/bin/adb
/usr/local/bin/adb
~/Library/Android/sdk/platform-tools/adb
~/Android/Sdk/platform-tools/adb
```

The environment sets:

```text
ADB_LIBUSB=0
```

---

# USB transport

Default Android-side ports are:

```text
Control: 27283
Media:   27284
```

The Android application binds to loopback.

The Mac accesses the servers through ADB forwarding:

```text
Mac localhost:27283 → Android localhost:27283
Mac localhost:27284 → Android localhost:27284
```

The current controller uses these fixed local ports.

Therefore, the current implementation is designed primarily for one active Android phone at a time.

Supporting simultaneous Android phones requires allocating separate local Mac ports per device.

---

# Threading model

## Main actor

`AppState` and Android controller UI state run on the main actor.

SwiftUI state publication happens on the main thread.

## Local camera queues

Every local camera has:

- one serial capture-session queue;
- one serial audio-processing queue;
- per-session recursive locking;
- main-thread state publication.

## Android transport queues

The control connection owns a serial network queue.

The media connection owns a separate serial network queue.

The H.264 decoder owns a dedicated decode queue.

The Android recorder owns:

- one serial writer queue;
- one audio output queue.

This isolates:

- control messages;
- media packet parsing;
- video decoding;
- recording;
- microphone capture;
- UI updates.

---

# Failure isolation

A failure in one source must not stop unrelated sources.

The application handles source-specific errors for:

- local camera configuration;
- microphone configuration;
- local recording;
- MP4 export;
- Android discovery;
- ADB startup;
- ADB forwarding;
- control connection;
- media connection;
- invalid media packets;
- H.264 decoding;
- unavailable phone audio;
- Android recording;
- torch commands.

Local camera failures do not stop Android cameras.

Android failures do not stop local cameras.

One recording failure does not stop other recordings.

---

# Current scope

The current project includes:

- local macOS camera preview;
- local macOS camera recording;
- local microphone selection;
- local live audio monitoring;
- Android USB camera streaming;
- Android H.264 decoding;
- Android phone camera switching;
- Android torch control;
- Android phone microphone transport;
- Android recording on macOS;
- macOS microphone selection for Android recording;
- MOV and MP4 output.

The project does not currently include:

- a macOS system-wide virtual camera;
- an iOS companion application;
- iPhone USB capture;
- Wi-Fi camera transport;
- cloud recording;
- editing or media management;
- synchronized multi-source timeline recording;
- remote Android focus or exposure controls.

---

# Future improvements

Potential future work includes:

- dynamic Android format capability reporting;
- multiple simultaneous Android phones;
- configurable local ADB ports;
- Android audio monitoring on macOS;
- Android audio meters;
- Android bitrate controls;
- reconnect and automatic stream restoration;
- improved Android timestamp synchronization;
- security-scoped recording-folder bookmarks;
- signed and notarized macOS releases;
- release APK signing;
- a macOS Camera Extension;
- automated integration tests.
