# Development Guide

## Repository

Clone the repository:

    git clone https://github.com/TheAndreyZakharov/Webcamera.git
    cd Webcamera
    code .

## Target devices

Primary Android device:

    Meizu MX5
    Android 5.1
    API 22
    Flyme 6.2.0.0G

Primary Mac:

    MacBook Air with Apple Silicon
    macOS

## Final functional requirements

The macOS application must support:

- discovery of all cameras visible to macOS;
- discovery of connected Android Webcamera devices;
- one-camera preview;
- simultaneous multi-camera grid preview;
- independent source selection;
- resolution and FPS selection;
- supported zoom controls;
- supported focus controls;
- supported exposure and other camera controls;
- Android torch control when available;
- recording from one camera;
- simultaneous recording from several cameras;
- user-selected recording destination;
- independent recording files for every selected source;
- source-specific status and error reporting.

## Supported source types

The application supports:

- Android Webcamera sources over ADB and USB;
- the built-in Mac camera;
- USB cameras recognized by macOS;
- other AVFoundation video capture devices.

Old iPhones are not included in the current project.

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

## Android environment

Expected Android SDK location:

    ~/Library/Android/sdk

Recommended variables:

    ANDROID_HOME=~/Library/Android/sdk
    ADB_LIBUSB=0

## Environment verification

Run:

    ./scripts/check-environment.sh

## USB transport verification

Connect the Android phone with USB debugging enabled.

Run:

    ./scripts/test-usb-transport.sh

The test verifies:

- ADB availability;
- Android shell access;
- forwarding support;
- connection stability.

## Android development

Android project directory:

    android-app/

Language:

    Java

Minimum API:

    API 22

Build:

    cd android-app
    ./gradlew clean assembleDebug

Generated APK:

    android-app/app/build/outputs/apk/debug/app-debug.apk

Install:

    cd ..
    ./scripts/install-android.sh

Read application logs:

    ADB_LIBUSB=0 adb logcat -d | grep -i Webcamera

## macOS development

macOS project:

    macos-app/Webcamera/Webcamera.xcodeproj

The application is a normal windowed macOS application.

Xcode is used for:

- application-target configuration;
- application bundle generation;
- asset catalogs;
- framework linking;
- local signing;
- release builds.

Swift source may still be edited in Visual Studio Code.

## Local signing

A paid Apple Developer Program membership is not required to build and run the viewer and recorder on the development Mac.

Developer ID and notarization are needed only for polished public distribution without Gatekeeper warnings.

The initial application does not contain a Camera Extension.

## macOS frameworks

The project uses:

- SwiftUI;
- AppKit;
- AVFoundation;
- Core Media;
- Core Video;
- VideoToolbox;
- Network;
- Uniform Type Identifiers where required.

## macOS source architecture

The macOS application should contain separate components for:

    camera discovery
    camera-source models
    local AVFoundation capture
    Android ADB discovery
    Android control transport
    Android video transport
    H.264 decoding
    preview layout
    recording management
    camera controls
    destination-folder management
    application state

Sources must not be implemented directly inside SwiftUI views.

## Local camera discovery

The application discovers AVFoundation devices and observes connection changes.

For each camera it reads:

- supported formats;
- frame-rate ranges;
- supported zoom range;
- focus capabilities;
- exposure capabilities;
- white-balance capabilities;
- device position;
- unique identifier.

The interface must show only controls supported by the active source.

## Android source discovery

The Mac lists Android devices using:

    ADB_LIBUSB=0 adb devices -l

Each Android source is identified by its ADB serial.

No source serial is hardcoded.

Each active Android source gets unique local forwarding ports.

## Camera selection

The window toolbar contains a camera menu.

The interface supports:

- selecting one main source;
- enabling additional sources;
- switching between single and grid layouts;
- disabling a source without removing it from discovery.

The source list is grouped into:

    Android phones
    Built-in cameras
    USB cameras
    Other cameras

## Multi-camera state

Each source maintains independent state:

    discovered
    selected
    active
    configured
    streaming
    recording
    failed

The application-level model owns a collection of source controllers.

One source failure must not stop the others.

## Resolution selection

Resolution lists are source-specific.

For Android, values come from the Webcamera protocol.

For local cameras, values come from AVFoundation formats.

The application must not offer unsupported combinations.

A format change may require capture restart.

## Frame-rate selection

FPS choices are validated against the selected format.

Possible displayed values may include:

    15 FPS
    24 FPS
    25 FPS
    30 FPS
    50 FPS
    60 FPS

Only values supported by the source and selected format are shown.

## Zoom controls

Android zoom capabilities come from the protocol.

AVFoundation zoom uses the selected device video zoom factor range.

The interface displays:

- current zoom;
- minimum zoom;
- maximum zoom;
- reset action.

Zoom is disabled when unsupported.

## Focus controls

Possible focus controls include:

- continuous autofocus;
- one-time autofocus;
- locked focus;
- manual focus position;
- focus point.

Support varies by source.

The Mac must not assume that every USB camera provides focus control.

## Torch controls

Android reports whether its selected camera supports flash or torch.

The Mac displays a torch switch only when supported.

The command is sent through the control connection.

Possible states:

    off
    torch
    auto

The interface must display failures returned by Android.

Torch operation must be tested with the Meizu rear camera.

## Recording

Recording is performed on the Mac.

The user chooses a destination folder through an `NSOpenPanel` configured for directory selection.

The application stores the selected folder for future sessions where permitted.

Each source writes to a separate file.

The initial output format is:

    MP4 with H.264 video

The recording subsystem must support:

- start recording for one source;
- stop recording for one source;
- start recording for all active sources;
- stop all recordings;
- simultaneous independent writers;
- unique filenames;
- recording duration;
- written-frame statistics;
- disk-write errors;
- insufficient-space errors.

## Recording filenames

Recommended format:

    Webcamera_<source-name>_<date>_<time>.mp4

Filename components must be sanitized.

Existing files must not be overwritten silently.

## Recording implementation

The initial common path uses:

    CVPixelBuffer
        ↓
    AVAssetWriterInputPixelBufferAdaptor
        ↓
    AVAssetWriter
        ↓
    MP4 file

This works for both:

- local AVFoundation frames;
- decoded Android frames.

Direct Android H.264 remuxing can be considered later as an optimization.

## Multi-camera recording

Every active recording uses its own:

- AVAssetWriter;
- writer input;
- pixel-buffer adaptor;
- timing origin;
- serial writing queue;
- output file.

Frames from one source must never enter another source writer.

The interface shows a separate recording indicator for every camera tile.

## Destination-folder access

For local development, the selected path can be used directly.

If application sandboxing is enabled later, the selected folder must be persisted using a security-scoped bookmark.

The application must stop recording cleanly if access to the destination is lost.

## FFmpeg diagnostics

Inspect a recording:

    ffprobe recording.mp4

Play a recording:

    ffplay recording.mp4

Diagnostic video files must not be committed.

## Android development stages

1. Configure Gradle and API 22.
2. Build a minimal application.
3. Enumerate phone cameras.
4. Enumerate resolutions and FPS ranges.
5. Detect zoom, focus, flash, and torch support.
6. Enumerate H.264 encoders.
7. Start a local preview.
8. Encode a test H.264 stream.
9. Verify output with FFmpeg.
10. Implement control and video servers.
11. Implement runtime controls.
12. Implement foreground-service streaming.
13. Test screen-off behavior.
14. Test torch and thermal behavior.

## macOS development stages

1. Create the Xcode application.
2. Add the application icon.
3. Discover local AVFoundation cameras.
4. Display one local camera.
5. Add source and format selection.
6. Add zoom, focus, and supported controls.
7. Add the common source model.
8. Add multi-camera source selection.
9. Add the grid preview.
10. Add the recording subsystem.
11. Add simultaneous recording.
12. Add destination-folder selection.
13. Add ADB discovery.
14. Add Android control transport.
15. Add Android H.264 transport and decoding.
16. Add Android controls to the common interface.
17. Add reconnection and error recovery.
18. Add release packaging.

## Android ports

    Control port: 27283
    Video port:   27284

## Release script

Build release artifacts:

    ./scripts/build-release.sh 1.0.0

Generated files after both applications exist:

    release/Webcamera-Android-1.0.0.apk
    release/Webcamera-macOS-1.0.0.zip

## Continuous integration

Workflow:

    .github/workflows/build.yml

It builds:

- Android APK on Linux;
- macOS application on a macOS runner.

## Git workflow

Before development:

    git pull

After a logical change:

    git status
    git add .
    git commit -m "Describe the change"
    git push

Do not commit:

- Gradle build output;
- Xcode Derived Data;
- release archives;
- APK files;
- recordings;
- raw H.264 streams;
- signing credentials;
- local folder bookmarks.
