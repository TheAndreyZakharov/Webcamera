# Webcamera Development Guide

## Repository

Clone the repository:

```bash
git clone https://github.com/TheAndreyZakharov/Webcamera.git
cd Webcamera
```

Open it in Visual Studio Code:

```bash
code .
```

The macOS Xcode project is located at:

```text
macos-app/Webcamera/Webcamera.xcodeproj
```

The Android Gradle project is located at:

```text
android-app/
```

---

# Current implementation status

The project currently contains working implementations for both macOS and Android integration.

## macOS local camera support

The macOS application supports:

- built-in Mac cameras;
- external USB cameras;
- virtual AVFoundation cameras;
- simultaneous preview of selected cameras;
- independent local camera controllers;
- per-camera resolution and frame-rate selection;
- per-camera microphone selection;
- live audio monitoring;
- left and right audio meters;
- mono recording;
- MOV recording;
- MP4 conversion;
- separate preview windows;
- record-all and stop-all actions.

## Android camera support

The macOS application also supports:

- ADB device discovery;
- starting the Android activity and service;
- ADB port forwarding;
- Android control connection;
- Android media connection;
- front and rear phone-camera selection;
- Android stream resolution selection;
- H.264 video decoding through VideoToolbox;
- Android torch control;
- phone microphone AAC reception;
- Android recording on macOS;
- recording Android video with the phone microphone;
- recording Android video with a macOS microphone;
- recording Android video without audio;
- MOV and MP4 output;
- independent Android recording state.

---

# Primary target systems

## macOS development machine

The macOS application is developed for:

```text
macOS
Apple Silicon
Xcode
Swift
```

The current build examples use:

```text
arm64
```

## Android target

The primary compatibility target is:

```text
Meizu MX5
Android 5.1
API 22
Flyme 6.2.0.0G
```

The Android implementation must remain compatible with API 22.

---

# Required tools

Required macOS development tools:

- Git;
- Xcode;
- Xcode Command Line Tools;
- Swift;
- Bash;
- ADB;
- Android SDK Platform Tools.

Required Android development tools:

- Java 17;
- Android SDK;
- Gradle wrapper;
- ADB.

Recommended diagnostic tools:

- FFmpeg;
- FFprobe;
- FFplay;
- Visual Studio Code.

A globally installed `gradle` executable is optional because the Android project should use:

```text
android-app/gradlew
```

---

# Environment check

Run:

```bash
./scripts/check-environment.sh
```

The environment script checks:

- operating system;
- processor architecture;
- Git;
- Xcode;
- Swift;
- Java;
- Android SDK;
- ADB;
- FFmpeg;
- project files.

The script reports optional tools without failing unnecessarily.

---

# Important paths

```text
macos-app/Webcamera/Webcamera.xcodeproj
macos-app/Webcamera/Webcamera/
android-app/
shared/protocol/protocol.md
docs/
scripts/
release/
```

Important macOS source files:

```text
macos-app/Webcamera/Webcamera/App/AppState.swift
macos-app/Webcamera/Webcamera/App/WebcameraApp.swift

macos-app/Webcamera/Webcamera/CameraControl/CameraController.swift
macos-app/Webcamera/Webcamera/CameraControl/AndroidCameraController.swift

macos-app/Webcamera/Webcamera/Decoder/H264Decoder.swift

macos-app/Webcamera/Webcamera/Models/CameraDeviceInfo.swift
macos-app/Webcamera/Webcamera/Models/VideoFormat.swift

macos-app/Webcamera/Webcamera/Preview/VideoPreviewView.swift

macos-app/Webcamera/Webcamera/Recording/AndroidRecorder.swift

macos-app/Webcamera/Webcamera/Transport/ADBController.swift
macos-app/Webcamera/Webcamera/Transport/ControlConnection.swift
macos-app/Webcamera/Webcamera/Transport/VideoConnection.swift

macos-app/Webcamera/Webcamera/UI/ContentView.swift
macos-app/Webcamera/Webcamera/UI/SettingsView.swift
```

---

# Source responsibilities

## AppState

`AppState` owns application-wide state.

It is responsible for:

- permissions;
- camera discovery;
- Android discovery;
- camera selection;
- controller creation;
- controller removal;
- video-format selection;
- audio-device selection;
- recording-format selection;
- mono settings;
- global recording actions;
- global settings application.

Do not place camera capture or transport implementation directly in `AppState`.

---

## CameraController

`CameraController` handles local AVFoundation cameras.

It owns:

- one capture session;
- camera and microphone inputs;
- movie recording;
- live audio monitoring;
- audio meters;
- mono conversion;
- local camera errors.

---

## AndroidCameraController

`AndroidCameraController` handles one Android phone source.

It owns:

- ADB preparation;
- control transport;
- media transport;
- phone camera capabilities;
- selected phone camera;
- selected Android stream format;
- torch state;
- decoded frames;
- phone audio availability;
- Android recording state.

---

## AndroidRecorder

`AndroidRecorder` writes Android recordings on the Mac.

It accepts:

- decoded Android video frames;
- compressed phone AAC packets;
- or audio from a selected macOS microphone.

It writes one MOV or MP4 file per Android source.

---

## H264Decoder

`H264Decoder`:

- parses Annex B SPS and PPS;
- creates a VideoToolbox format description;
- converts Annex B frames to AVCC;
- creates sample buffers;
- decodes H.264 asynchronously;
- returns `CVPixelBuffer` frames.

---

## ControlConnection

`ControlConnection` provides newline-delimited JSON transport.

It must remain independent from the binary media transport.

---

## VideoConnection

`VideoConnection` parses the binary Android media protocol.

The class name is historical: the connection carries video and audio packets.

It supports:

```text
videoConfiguration
videoFrame
audioConfiguration
audioFrame
endOfStream
```

---

## ContentView

`ContentView` displays:

- the camera sidebar;
- global controls;
- local camera tiles;
- Android camera tiles;
- preview windows.

Capture and transport logic must not be implemented inside SwiftUI views.

---

# macOS permissions

The application requires camera permission for local AVFoundation cameras.

It requires microphone permission when using a macOS microphone.

Phone microphone audio received from Android does not require macOS microphone permission.

Required application usage descriptions should exist in the macOS target configuration:

```text
NSCameraUsageDescription
NSMicrophoneUsageDescription
```

When access is denied, the application can open the corresponding Privacy & Security settings page.

---

# Building the macOS application

From the repository root:

```bash
./scripts/run-macos.sh
```

This script:

1. checks the Xcode project;
2. removes the previous script-derived build directory;
3. builds the Debug configuration;
4. verifies the application bundle;
5. launches the application.

---

## Manual macOS build

From the repository root:

```bash
rm -rf /tmp/WebcameraDerivedData
```

Build:

```bash
xcodebuild \
  -project macos-app/Webcamera/Webcamera.xcodeproj \
  -scheme Webcamera \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/WebcameraDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

Application bundle:

```text
/tmp/WebcameraDerivedData/Build/Products/Debug/Webcamera.app
```

Launch:

```bash
open /tmp/WebcameraDerivedData/Build/Products/Debug/Webcamera.app
```

---

# Build diagnostics

Capture the full build log:

```bash
rm -rf /tmp/WebcameraDerivedData

xcodebuild \
  -project macos-app/Webcamera/Webcamera.xcodeproj \
  -scheme Webcamera \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/WebcameraDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  clean build \
  2>&1 | tee /tmp/webcamera-macos-build.log
```

Show compiler errors:

```bash
grep -nE \
  "error:|BUILD FAILED|SwiftCompile.*failed" \
  /tmp/webcamera-macos-build.log |
  head -n 150
```

Show warnings:

```bash
grep -n "warning:" \
  /tmp/webcamera-macos-build.log |
  head -n 150
```

Show final output:

```bash
tail -n 40 /tmp/webcamera-macos-build.log
```

Verify the executable:

```bash
file \
  /tmp/WebcameraDerivedData/Build/Products/Debug/Webcamera.app/Contents/MacOS/Webcamera
```

---

# Swift formatting

Format all macOS Swift sources:

```bash
find macos-app/Webcamera/Webcamera \
  -name '*.swift' \
  -print0 |
  xargs -0 swift format --in-place
```

Check formatting without changing files:

```bash
find macos-app/Webcamera/Webcamera \
  -name '*.swift' \
  -print0 |
  xargs -0 swift format lint
```

Review formatting changes before committing:

```bash
git diff --check
git diff
```

---

# Local camera development

## Discovery

Local cameras are discovered using:

```swift
AVCaptureDevice.DiscoverySession
```

Do not hardcode local device identifiers.

Only show formats actually reported by AVFoundation.

---

## Controller ownership

Every selected local camera receives its own `CameraController`.

Do not share one `AVCaptureSession` between different camera devices.

Do not store capture-session implementation in SwiftUI views.

---

## Session graph safety

Any operation that can mutate an `AVCaptureSession` graph must use `CaptureSessionGate`.

This includes:

- `startRunning()`;
- `stopRunning()`;
- `beginConfiguration()`;
- `commitConfiguration()`;
- adding inputs;
- removing inputs;
- adding outputs;
- removing outputs;
- attaching a preview layer;
- detaching a preview layer.

Never modify the same session graph concurrently from the main thread and a capture queue.

---

## Camera removal

When a local camera is deselected:

1. remove it from `selectedCameraIDs`;
2. allow SwiftUI to remove its tile;
3. allow `VideoPreviewView` to detach;
4. wait for the teardown delay;
5. clear the controller;
6. remove its stored selections.

Do not remove the controller immediately before preview detachment.

---

# Local audio development

## Audio selection

Local camera microphone choices come from AVFoundation.

Changing the selected microphone rebuilds the local capture session.

Do not attempt to assign `Phone Microphone` to a local camera.

---

## Live monitoring

Local monitoring uses:

```text
AVCaptureAudioDataOutput
AVAudioPCMBuffer
AVAudioConverter
AVAudioPlayerNode
AVAudioEngine
```

Monitoring must not run on the main thread.

Use headphones during testing.

---

## Audio meters

Meters are derived from PCM RMS levels.

Do not calculate meters from encoded recording output.

Meter state is UI-only and must not block recording.

---

# Android development

## ADB environment

Recommended SDK path:

```text
~/Library/Android/sdk
```

Recommended shell variables:

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
export ADB_LIBUSB=0
```

Verify ADB:

```bash
ADB_LIBUSB=0 adb version
```

List devices:

```bash
ADB_LIBUSB=0 adb devices -l
```

A usable device must appear with state:

```text
device
```

Not:

```text
offline
unauthorized
```

---

## Android build

Build the debug APK:

```bash
cd android-app
chmod +x gradlew
./gradlew clean assembleDebug
```

Generated APK:

```text
android-app/app/build/outputs/apk/debug/app-debug.apk
```

---

## Install Android application

From the repository root:

```bash
./scripts/install-android.sh
```

For multiple connected devices, provide the serial:

```bash
./scripts/install-android.sh DEVICE_SERIAL
```

---

## Android logs

Clear existing logs:

```bash
ADB_LIBUSB=0 adb logcat -c
```

Read Webcamera logs:

```bash
ADB_LIBUSB=0 adb logcat |
  grep -i webcamera
```

For a specific device:

```bash
ADB_LIBUSB=0 adb -s DEVICE_SERIAL logcat |
  grep -i webcamera
```

---

## Start Android application manually

The current debug component is:

```text
com.theandreyzakharov.webcamera.debug/com.theandreyzakharov.webcamera.ui.MainActivity
```

Run:

```bash
ADB_LIBUSB=0 adb -s DEVICE_SERIAL shell am start \
  -n \
  com.theandreyzakharov.webcamera.debug/com.theandreyzakharov.webcamera.ui.MainActivity
```

The service component is:

```text
com.theandreyzakharov.webcamera.debug/com.theandreyzakharov.webcamera.service.CameraService
```

Start it manually:

```bash
ADB_LIBUSB=0 adb -s DEVICE_SERIAL shell am startservice \
  -n \
  com.theandreyzakharov.webcamera.debug/com.theandreyzakharov.webcamera.service.CameraService \
  -a \
  com.theandreyzakharov.webcamera.START_SERVICE
```

---

# USB transport development

Run the transport test:

```bash
./scripts/test-usb-transport.sh
```

For a specific device:

```bash
./scripts/test-usb-transport.sh DEVICE_SERIAL
```

The test verifies:

- ADB availability;
- device state;
- shell access;
- activity package visibility;
- control forwarding;
- media forwarding;
- forwarding-list output;
- connection stability.

The script must not remove unrelated ADB forwarding rules.

---

# Android control protocol

Control messages are newline-delimited JSON.

Every outgoing macOS message contains:

```text
version
type
sequence
timestamp
```

Common messages include:

```text
getCapabilities
configure
start
stop
getStatus
requestKeyFrame
setFlashMode
```

Common Android responses include:

```text
hello
capabilities
configured
status
flashStatus
error
```

---

# Android media protocol

The media connection uses a fixed 36-byte header.

Packet types are:

```text
1  videoConfiguration
2  videoFrame
3  audioConfiguration
4  audioFrame
5  endOfStream
```

Media payloads larger than 32 MiB are rejected.

All multi-byte integers use big-endian network byte order.

---

# Android recording development

Android recording is performed on macOS.

## Video

Decoded `CVPixelBuffer` frames are written through:

```swift
AVAssetWriterInputPixelBufferAdaptor
```

## Phone audio

Phone AAC packets are wrapped in compressed audio sample buffers.

Phone recording cannot begin until valid audio configuration has arrived.

## macOS microphone

A separate audio capture session records the selected Mac microphone.

The microphone session exists only for the Android recording that uses it.

## No Audio

When `No Audio` is selected, only the video writer input is created.

---

# Recording diagnostics

Inspect a recording:

```bash
ffprobe -hide_banner recording.mov
```

Inspect streams:

```bash
ffprobe \
  -hide_banner \
  -show_streams \
  recording.mp4
```

Play:

```bash
ffplay recording.mov
```

Check whether audio exists:

```bash
ffprobe \
  -v error \
  -select_streams a \
  -show_entries stream=codec_name,channels,sample_rate \
  -of default=noprint_wrappers=1 \
  recording.mov
```

Check video properties:

```bash
ffprobe \
  -v error \
  -select_streams v \
  -show_entries stream=codec_name,width,height,r_frame_rate \
  -of default=noprint_wrappers=1 \
  recording.mov
```

Do not commit test recordings.

---

# Settings development

Settings are stored with `UserDefaults`.

Current stored values include:

```text
recordingFolderPath
recordingFileFormat
```

Additional common audio defaults may also use `UserDefaults`.

When changing settings behavior:

- keep camera-specific selections independent;
- do not replace per-camera choices automatically unless requested;
- disable bulk changes while affected cameras are recording;
- keep `Phone Microphone` Android-only.

If macOS App Sandbox is enabled later, replace the plain folder path with a security-scoped bookmark.

---

# Release build

Run:

```bash
./scripts/build-release.sh 1.0.0
```

The script creates:

```text
release/Webcamera-Android-1.0.0.apk
release/Webcamera-macOS-1.0.0.zip
release/SHA256SUMS.txt
```

The Android artifact is currently a debug-signed APK unless a release signing configuration is added.

The macOS application is currently built without Developer ID signing and receives an ad-hoc signature for local distribution.

For public macOS distribution, add:

- Developer ID Application signing;
- hardened runtime;
- notarization;
- stapling.

For public Android distribution, add:

- a release keystore;
- Gradle release signing;
- secure CI secrets;
- version-code management.

---

# Continuous integration

Workflow:

```text
.github/workflows/build.yml
```

CI builds:

- the Android debug APK;
- the unsigned macOS Release application;
- compressed artifacts for both platforms.

CI should fail when a required project is missing.

It should not silently skip a platform that is part of the current repository.

---

# Git workflow

Update before editing:

```bash
git pull --ff-only
```

Review the repository:

```bash
git status
```

Review changes:

```bash
git diff
git diff --check
```

Stage a logical change:

```bash
git add \
  docs \
  scripts \
  shared/protocol \
  .github/workflows/build.yml
```

Commit:

```bash
git commit -m "Update documentation and build scripts"
```

Push:

```bash
git push
```

---

# Files that must not be committed

Do not commit:

- Xcode Derived Data;
- Gradle build directories;
- generated APK files;
- generated application archives;
- release artifacts;
- recordings;
- temporary MOV files;
- raw H.264 or AAC captures;
- signing certificates;
- Android keystores;
- notarization credentials;
- local SDK paths;
- local recording-folder preferences;
- temporary logs.

Recommended ignored paths include:

```text
macos-app/DerivedData/
macos-app/ReleaseDerivedData/
android-app/.gradle/
android-app/**/build/
release/
*.apk
*.mov
*.mp4
*.h264
*.aac
*.log
local.properties
```

---

# Regression checklist

Before committing camera-related changes, verify:

## Local cameras

- built-in camera appears;
- external camera appears;
- local camera tile appears;
- local preview starts;
- local preview stops;
- video format changes;
- microphone changes;
- live monitor works;
- audio meters move;
- MOV recording works;
- MP4 recording works.

## Android source

- phone appears in the sidebar;
- Android tile appears;
- connection succeeds;
- rear camera works;
- front camera works;
- format selection works;
- torch works where supported;
- phone audio becomes available;
- Phone Microphone recording works;
- macOS microphone recording works;
- No Audio recording works;
- MOV recording works;
- MP4 recording works.

## Multi-source behavior

- local and Android cameras appear together;
- both can run simultaneously;
- both can record simultaneously;
- stopping one source does not stop the other;
- removing one source does not crash the application;
- separate preview windows work;
- Record All creates separate files.
