# Development Guide

## Repository

Clone the repository:

    git clone https://github.com/TheAndreyZakharov/Webcamera.git
    cd Webcamera
    code .

## Current project status

The macOS application is the currently implemented part of Webcamera.

It already supports:

- discovery of local AVFoundation cameras;
- built-in and external camera sources;
- simultaneous multi-camera preview;
- independent camera selection;
- per-camera resolution and frame-rate selection;
- independent capture sessions;
- individual camera preview windows;
- independent microphone selection;
- live microphone monitoring;
- left and right audio level meters;
- optional mono monitoring;
- optional mono recording;
- independent recording;
- record-all and stop-all actions;
- per-camera MOV or MP4 selection;
- a global default recording format;
- recording destination selection;
- safe preview-layer and capture-session synchronization;
- delayed capture-session teardown;
- MP4 export with temporary MOV recovery.

The next major development stage is the Android application.

The Android application will have a deliberately limited first scope:

- connect an Android phone to the Mac through USB and ADB;
- capture video from the selected phone camera;
- encode the video as H.264;
- stream it to the macOS application;
- make the phone appear as another camera source.

Recording remains on the Mac.

## Target devices

Primary Android device:

    Meizu MX5
    Android 5.1
    API 22
    Flyme 6.2.0.0G

Primary Mac:

    MacBook Air with Apple Silicon
    macOS

## macOS functional requirements

The macOS application supports or is expected to preserve:

- discovery of cameras visible to AVFoundation;
- simultaneous preview of several selected cameras;
- independent source selection;
- per-camera resolution and FPS selection;
- independent start and stop controls;
- independent microphone selection;
- live microphone monitoring;
- stereo audio meters;
- per-camera mono monitoring;
- per-camera mono recording;
- recording from one camera;
- simultaneous recording from several cameras;
- per-camera MOV or MP4 output;
- a global default output format;
- user-selected recording destination;
- separate recording files for every camera;
- source-specific status and error reporting;
- safe camera removal and session teardown;
- connected Android phones as additional video sources.

## Android first-version requirements

The first Android application must support:

- Android camera permission;
- discovery of front and rear cameras;
- selection of one phone camera;
- selection of a stable supported video configuration;
- camera capture;
- H.264 encoding through `MediaCodec`;
- a local control server;
- a local video server;
- ADB USB port forwarding;
- start and stop streaming;
- basic connection status;
- basic encoder and camera error reporting;
- foreground-service operation when required;
- reconnection after the Mac reconnects.

The first Android version does not need:

- phone-side video recording;
- audio streaming;
- remote zoom controls;
- remote focus controls;
- remote exposure controls;
- remote torch controls;
- multiple simultaneous phone cameras;
- editing or media management;
- Wi-Fi transport;
- a virtual-camera driver.

These features may be evaluated later without expanding the initial Android milestone.

## Supported source types

The macOS application supports:

- the built-in Mac camera;
- USB cameras recognized by macOS;
- virtual or other AVFoundation video devices;
- Android Webcamera sources over ADB and USB after the Android application is implemented.

Old iPhones are not part of the project.

## Required tools

- Git
- Visual Studio Code
- Xcode
- Swift
- Java 17
- Gradle
- Android SDK
- Android SDK Platform Tools
- ADB
- FFmpeg

## Environment verification

Run:

    ./scripts/check-environment.sh

The script should verify the tools required by the current development stage.

## macOS development

macOS project:

    macos-app/Webcamera/Webcamera.xcodeproj

The application is a normal windowed macOS application.

Xcode is used for:

- application-target configuration;
- Swift compilation;
- application bundle generation;
- asset catalogs;
- framework linking;
- local signing;
- release builds.

Swift source may also be edited in Visual Studio Code.

## macOS frameworks

The macOS application uses:

- SwiftUI;
- AppKit;
- AVFoundation;
- AVFAudio;
- AudioToolbox;
- Core Media;
- Core Video;
- VideoToolbox;
- Combine;
- Foundation.

Network and process-management APIs are used or will be used for Android transport.

## Local signing

A paid Apple Developer Program membership is not required to build and run the application on the development Mac.

Developer ID signing and notarization are required only for polished public distribution without normal Gatekeeper warnings.

The current application does not contain a macOS Camera Extension.

## macOS project structure

Important source responsibilities include:

    AppState
        application-level camera, audio, recording, and selection state

    CameraDeviceInfo
        discovered camera and microphone models

    VideoFormat
        source-specific resolution and frame-rate configurations

    CameraController
        AVFoundation session, recording, audio monitoring, and meters

    VideoPreviewView
        AppKit preview layer and capture-session synchronization

    ContentView
        camera sidebar, grid, tiles, controls, and preview windows

    SettingsView
        recording destination and global recording defaults

    H264Decoder
        VideoToolbox decoding support for future Android sources

Capture and transport logic must not be implemented directly inside SwiftUI views.

## macOS build

From the repository root:

    swift format --in-place macos-app/Webcamera/Webcamera/App/AppState.swift macos-app/Webcamera/Webcamera/CameraControl/CameraController.swift macos-app/Webcamera/Webcamera/Models/CameraDeviceInfo.swift macos-app/Webcamera/Webcamera/Models/VideoFormat.swift macos-app/Webcamera/Webcamera/Preview/VideoPreviewView.swift macos-app/Webcamera/Webcamera/UI/ContentView.swift macos-app/Webcamera/Webcamera/UI/SettingsView.swift

Clean old derived data:

    rm -rf macos-app/DerivedData

Build:

    xcodebuild -project macos-app/Webcamera/Webcamera.xcodeproj -scheme Webcamera -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath macos-app/DerivedData CODE_SIGNING_ALLOWED=NO clean build

Generated application:

    macos-app/DerivedData/Build/Products/Debug/Webcamera.app

Run:

    open macos-app/DerivedData/Build/Products/Debug/Webcamera.app

## Build diagnostics

Store the complete build output:

    xcodebuild -project macos-app/Webcamera/Webcamera.xcodeproj -scheme Webcamera -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath macos-app/DerivedData CODE_SIGNING_ALLOWED=NO clean build 2>&1 | tee /tmp/webcamera-build.log

Show errors:

    grep -n "error:" /tmp/webcamera-build.log | head -n 100

Show warnings:

    grep -n "warning:" /tmp/webcamera-build.log | head -n 100

Show the final build lines:

    tail -n 30 /tmp/webcamera-build.log

Verify the application executable:

    file macos-app/DerivedData/Build/Products/Debug/Webcamera.app/Contents/MacOS/Webcamera

## Local camera discovery

Local cameras are discovered through `AVCaptureDevice.DiscoverySession`.

For each camera, Webcamera reads:

- unique identifier;
- localized name;
- device type;
- supported AVFoundation formats;
- supported frame-rate ranges;
- media subtype.

Only configurations reported by the camera are displayed.

The current implementation does not assume that every external camera supports manual focus, exposure, or zoom controls.

## Camera selection

The sidebar displays cameras visible to AVFoundation.

The user can:

- enable several cameras;
- disable a camera;
- refresh camera discovery;
- run one camera;
- run all selected cameras;
- stop one camera;
- stop all cameras.

Every selected camera receives an independent controller.

## Capture-session safety

All operations that mutate an `AVCaptureSession` graph must use the shared per-session gate.

This includes:

- starting a session;
- stopping a session;
- beginning and committing configuration;
- adding and removing inputs;
- adding and removing outputs;
- attaching a preview layer;
- detaching a preview layer.

Do not modify the same capture session simultaneously from:

- the capture queue;
- the main thread;
- an AppKit preview view;
- SwiftUI dismantling callbacks.

When removing a camera tile:

1. remove the camera from the selected set;
2. allow SwiftUI to dismantle the preview;
3. detach the preview layer;
4. wait for the UI transaction;
5. stop and clear the controller.

## Resolution and frame-rate selection

Video configurations are camera-specific.

Displayed values combine:

- width;
- height;
- frame rate.

Examples:

    1920 × 1080 · 30 FPS
    1280 × 720 · 60 FPS

Changing a format may rebuild and restart the capture session.

Format selection is disabled while the camera is recording.

## Microphone selection

Microphones are discovered independently from cameras.

Every camera tile can select:

- No Audio;
- a camera microphone;
- the built-in microphone;
- an external microphone;
- an audio-interface device visible through AVFoundation.

Microphone permission must be granted before an audio device can be used.

Changing a microphone may rebuild the camera capture session.

## Live audio monitoring

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

Every camera controller owns an independent audio-processing queue.

The monitoring button affects only the selected camera.

Monitoring is automatically stopped when:

- the camera stops;
- the controller is removed;
- the audio input disappears;
- the session is reconfigured unsuccessfully.

## Audio meters

Audio meters are calculated from PCM samples.

The implementation calculates the RMS value for every channel and maps it to a normalized interface value.

The left and right meters should update without blocking the capture-session queue or main thread.

When mono mode is enabled, both meters show the same resulting mono signal.

## Mono behavior

Mono is configured per camera.

When enabled:

- monitoring converts the source audio into one channel;
- `AVAudioEngine` distributes the one-channel signal to both output speakers;
- movie output requests a one-channel AAC recording;
- the UI displays matching left and right meter levels.

Changing mono mode while recording is not allowed.

The live monitoring graph is rebuilt when the channel configuration changes.

## Recording

Every local camera controller owns one `AVCaptureMovieFileOutput`.

The application supports:

- recording one camera;
- recording several cameras simultaneously;
- stopping one recording;
- stopping all recordings;
- unique filenames;
- optional audio;
- mono or stereo audio;
- per-camera MOV or MP4 output.

Every camera writes its own file.

## Recording formats

MOV is captured directly.

MP4 uses:

    AVCaptureMovieFileOutput
        ↓
    temporary MOV
        ↓
    AVAssetExportSession
        ↓
    final MP4

The temporary MOV is deleted after a successful MP4 export.

If export fails, the temporary MOV remains available and its location is reported.

## Per-camera and global formats

Every camera can select its own file format.

Settings also contains a global file-format selection.

The global value acts as:

- the default for newly selected cameras;
- the common format when the user intentionally applies one format to all cameras.

A camera-specific selection overrides the global default for that camera.

## Recording destination

The destination is selected through an `NSOpenPanel` configured for directories.

The default destination is Downloads.

The path is currently stored in `UserDefaults`.

If sandboxing is enabled later, the project should use a security-scoped bookmark.

## Recording diagnostics

Inspect a MOV recording:

    ffprobe recording.mov

Inspect an MP4 recording:

    ffprobe recording.mp4

Play a recording:

    ffplay recording.mov

Diagnostic recordings must not be committed.

## Android environment

Expected Android SDK location:

    ~/Library/Android/sdk

Recommended variables:

    ANDROID_HOME=~/Library/Android/sdk
    ADB_LIBUSB=0

Verify ADB:

    ADB_LIBUSB=0 adb version

List connected devices:

    ADB_LIBUSB=0 adb devices -l

## USB transport verification

Connect the Android phone with:

- USB data enabled;
- USB debugging enabled;
- the development Mac authorized.

Run:

    ./scripts/test-usb-transport.sh

The test should verify:

- ADB availability;
- at least one online Android device;
- shell access;
- port-forwarding support;
- stable device serial detection.

## Android project

Android project directory:

    android-app/

Primary language:

    Java

Minimum API:

    API 22

Build:

    cd android-app
    ./gradlew clean assembleDebug

Generated APK:

    android-app/app/build/outputs/apk/debug/app-debug.apk

Install:

    cd ../..
    ./scripts/install-android.sh

Read application logs:

    ADB_LIBUSB=0 adb logcat -d | grep -i Webcamera

## Android implementation strategy

The first Android implementation should remain small.

Suggested components:

    MainActivity
        permissions, camera selection, status, and service controls

    CameraStreamingService
        foreground service and runtime ownership

    CameraController
        legacy Camera or Camera2 capture

    H264Encoder
        MediaCodec configuration and encoded output

    ControlServer
        small newline-delimited JSON protocol

    VideoServer
        framed H.264 packet transport

    StreamConfiguration
        selected camera, size, FPS, and bitrate

    ConnectionState
        client connection and streaming state

Avoid adding unrelated Android features before stable USB video streaming works.

## Android camera API

The target device runs Android 5.1.

Both camera APIs may be evaluated:

- Camera2;
- legacy Camera API.

Use Camera2 only if the target device exposes a stable implementation.

The legacy Camera API is acceptable and may be preferable for the Meizu MX5.

The first implementation needs only one selected camera at a time.

## Android video encoding

Use `MediaCodec` with H.264/AVC.

Prefer a hardware encoder.

The encoder configuration must be compatible with:

- the selected camera output size;
- the selected frame rate;
- the input color format or surface input;
- the target device;
- stable USB transmission.

The first stable configuration may be fixed or chosen from a small tested set.

## Android development stages

1. Create or verify the Gradle project.
2. Set minimum API 22.
3. Build and install a minimal application.
4. Request camera permission.
5. Enumerate front and rear cameras.
6. Display a local test preview.
7. Choose a stable resolution and frame rate.
8. Configure an H.264 `MediaCodec` encoder.
9. Write a short diagnostic H.264 stream.
10. Verify the stream with FFmpeg.
11. Implement the control server.
12. Implement the video server.
13. Add ADB forwarding scripts.
14. Receive and parse the stream on macOS.
15. Decode H.264 through VideoToolbox.
16. display the Android source in Webcamera.
17. Add Mac-side recording for the Android source.
18. Add foreground-service operation.
19. Test screen-off and Flyme power-management behavior.
20. Add reconnection and error recovery.

## Android ports

Android-side defaults:

    Control port: 27283
    Video port:   27284

The Android servers bind to loopback:

    127.0.0.1:27283
    127.0.0.1:27284

The Mac may allocate different local ports for every connected phone.

## Android first-version control messages

The first protocol needs only enough control for a reliable webcam source:

    hello
    getCapabilities
    capabilities
    configure
    configured
    start
    stop
    status
    ping
    pong
    error

Advanced runtime camera controls are not required for the first Android version.

## macOS Android source stages

1. Detect devices with `adb devices -l`.
2. Identify every source by ADB serial.
3. Allocate unique local forwarding ports.
4. Create forwarding rules.
5. Connect to the Android control server.
6. Read device and stream capabilities.
7. Start the selected Android stream.
8. Connect to the video server.
9. parse framed H.264 packets.
10. Decode frames through VideoToolbox.
11. Display the source in the camera grid.
12. Handle disconnect and reconnect.
13. Add Mac-side recording.
14. Keep Android failure isolated from local cameras.

## Multiple Android devices

The architecture may support several Android phones later.

Every device must use its own:

- ADB serial;
- local control port;
- local video port;
- control connection;
- video connection;
- decoder;
- source state.

Never execute device-specific ADB commands without:

    adb -s DEVICE_SERIAL

## Release script

Build release artifacts:

    ./scripts/build-release.sh 1.0.0

Expected artifacts after both applications are implemented:

    release/Webcamera-Android-1.0.0.apk
    release/Webcamera-macOS-1.0.0.zip

## Continuous integration

Workflow:

    .github/workflows/build.yml

The intended workflow builds:

- the Android APK on Linux;
- the macOS application on a macOS runner.

## Git workflow

Before development:

    git pull

Review changes:

    git status
    git diff
    git diff --check

Stage a logical change:

    git add .

Commit:

    git commit -m "Describe the change"

Push:

    git push

Do not commit:

- Gradle build output;
- Xcode Derived Data;
- release archives;
- APK files;
- recordings;
- temporary MOV files;
- raw H.264 streams;
- signing credentials;
- local recording-folder data;
- local Android SDK configuration.
