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

## Supported source types

The macOS application is designed to display:

- the Android Webcamera source over USB;
- the built-in Mac camera;
- USB cameras recognized by macOS;
- other video capture devices exposed through AVFoundation.

The user selects the active source from the camera menu in the main window.

## iPhone support

Old iPhones are not included in the current project.

The Android USB implementation depends on ADB.

An iPhone implementation would require:

- a separate iOS application;
- a different transport;
- separate installation and signing;
- separate compatibility testing.

This work is not part of the initial Webcamera release.

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

Recommended environment variables:

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

The macOS application uses an Xcode project:

    macos-app/Webcamera/Webcamera.xcodeproj

The application is a normal windowed macOS app.

Xcode is required for:

- project configuration;
- the application bundle;
- asset catalogs;
- local development signing;
- framework linking;
- release builds.

Source files may still be edited in Visual Studio Code.

## Local signing

A paid Apple Developer Program membership is not required to build and run the normal viewer application on the development Mac.

Xcode can use local development signing.

Developer ID signing and notarization are needed only for polished public distribution without Gatekeeper warnings.

The initial viewer does not include a Camera Extension.

## macOS frameworks

The viewer uses:

- SwiftUI for application UI;
- AppKit where native integration is required;
- AVFoundation for local cameras;
- Core Media for media timestamps and formats;
- Core Video for pixel buffers;
- VideoToolbox for Android H.264 decoding;
- Network framework or sockets for Android transport.

## Local camera discovery

The macOS application discovers video capture devices through AVFoundation.

For each camera, it reads its supported formats and frame-rate ranges.

The application must never offer a resolution or FPS combination that the selected device does not report.

Changing a device format requires safe capture-session reconfiguration.

## Android source development

The Android source is developed in stages:

1. detect phone cameras;
2. list camera output sizes;
3. list frame-rate ranges;
4. list available H.264 encoders;
5. calculate compatible configurations;
6. start local camera preview;
7. encode a sample H.264 stream;
8. verify the sample with FFmpeg;
9. create control and video servers;
10. transport video over ADB;
11. decode video on macOS;
12. add background streaming.

## FFmpeg diagnostics

Inspect a raw H.264 file:

    ffprobe sample.h264

Play a raw H.264 file:

    ffplay sample.h264

Diagnostic video files must not be committed to Git.

## macOS camera menu

The main toolbar contains a camera-selection menu.

The menu groups sources by type:

    Android devices
    Built-in cameras
    USB cameras
    Other cameras

Selecting a source updates:

- available resolutions;
- available frame rates;
- source-specific controls;
- preview state;
- status information.

## Resolution selection

Resolution lists are source-specific.

For Android, the list comes from the control protocol.

For local cameras, the list comes from AVFoundation device formats.

The currently selected resolution must be persisted separately for each source when possible.

## Frame-rate selection

Frame-rate choices are validated against the selected format.

The application must account for ranges rather than assuming only fixed values.

Common options may include:

    15 FPS
    24 FPS
    25 FPS
    30 FPS
    50 FPS
    60 FPS

Only supported values are shown.

## Android ports

    Control port: 27283
    Video port:   27284

## Release script

Build release artifacts:

    ./scripts/build-release.sh 1.0.0

Before the macOS Xcode project exists, the script builds only the Android APK.

After the project is created, it also produces:

    release/Webcamera-Android-1.0.0.apk
    release/Webcamera-macOS-1.0.0.zip

## Continuous integration

GitHub Actions configuration:

    .github/workflows/build.yml

The workflow:

- builds the Android APK on Linux;
- builds the macOS app on a macOS runner after the Xcode project is present;
- uploads both build artifacts.

## VS Code

Recommended extensions:

- Swift;
- Extension Pack for Java;
- Gradle Extension Pack.

The repository contains common tasks in:

    .vscode/tasks.json

## Git workflow

Before development:

    git pull

After a logical change:

    git status
    git add .
    git commit -m "Describe the change"
    git push

Do not commit:

- Gradle build directories;
- Xcode Derived Data;
- APK files;
- application archives;
- raw video streams;
- diagnostic recordings;
- local signing information.

## Planned implementation order

1. Complete Android Gradle configuration.
2. Build a minimal Android application.
3. Enumerate Android camera capabilities.
4. Test Android H.264 encoding.
5. Create the macOS Xcode application.
6. Discover local Mac and USB cameras.
7. Display local-camera video.
8. Implement ADB device management.
9. Implement Android control transport.
10. Implement Android video transport.
11. Decode Android video with VideoToolbox.
12. Add source switching.
13. Add format and FPS controls.
14. Add Android background streaming.
15. Add release packaging.
