<div align="center">

<img src="assets/forreadme/app-icon.png" alt="Webcamera logo" width="300"/>

# Webcamera

[![Русский](https://img.shields.io/badge/README_Language-Русский-blue)](https://github.com/TheAndreyZakharov/Webcamera/blob/main/README_RU.md)
[![English](https://img.shields.io/badge/README_Language-English-brightgreen)](https://github.com/TheAndreyZakharov/Webcamera/blob/main/README.md)

</div>

Webcamera turns an Android smartphone into an additional USB camera for macOS while also supporting regular built-in, external, and virtual webcams.

The project consists of two applications:

- the Android application captures video and audio from the phone, encodes them, and sends them to the Mac over USB and ADB;
- the macOS application discovers local cameras and connected Android devices, displays several video sources simultaneously, and records every source to a separate file.

No internet connection or shared Wi-Fi network is required.

## How it works

The Android smartphone is connected to the Mac through USB.

The macOS application discovers the phone through Android Debug Bridge, starts the Android application, and creates local TCP port-forwarding rules.

The Android application opens the selected phone camera, encodes video as H.264, encodes phone microphone audio as AAC, and sends the media stream to the Mac.

The macOS application decodes the received video through VideoToolbox, displays it next to regular webcams, and optionally records it together with the selected audio source.

Communication flow:

    Android smartphone camera and microphone
                      ↓
             Android application
                      ↓
          H.264 video and AAC audio
                      ↓
              TCP over USB and ADB
                      ↓
              macOS application
                      ↓
        Preview, control, and recording

Regular Mac cameras operate directly through AVFoundation and do not use the Android application or ADB.

Every camera is an independent source and may have its own:

- resolution and frame rate;
- audio source;
- mono or stereo mode;
- recording format;
- preview state;
- recording state;
- separate preview window.

## Features

### Android application

- phone camera video streaming to the Mac over USB;
- phone microphone audio streaming;
- operation without Wi-Fi or internet access;
- front and rear camera selection;
- stream start and stop controls;
- torch control;
- connection status display;
- streaming status display;
- H.264 video encoding;
- AAC audio encoding;
- local TCP servers and ADB port forwarding;
- Android 5.1 compatibility;
- Meizu MX5 M575H support with Flyme 6.2.0.0G;
- custom application icon.

### macOS application

- support for macOS 14 and newer;
- built-in Mac camera discovery;
- external USB camera discovery;
- support for virtual cameras exposed through AVFoundation;
- connected Android device discovery;
- simultaneous preview of several cameras;
- independent start and stop controls for every camera;
- start-all and stop-all controls;
- per-source resolution and frame-rate selection;
- independent microphone selection for every camera;
- Android phone microphone support;
- built-in Mac microphone support;
- external microphone and audio-interface support;
- audio disabling for an individual camera;
- live monitoring of the selected microphone;
- left and right audio-level meters;
- mono monitoring and recording;
- independent recording for every camera;
- simultaneous recording from several cameras;
- per-camera MOV or MP4 selection;
- a common recording format for all selected cameras;
- a common microphone for all selected cameras;
- configurable recording destination;
- separate preview windows;
- Android phone torch control;
- custom application icon.

## Camera sources

Webcamera can use several source types simultaneously:

    Built-in Mac camera
    External USB camera
    Virtual AVFoundation camera
    Android smartphone camera over USB

Available cameras are displayed in the macOS application sidebar.

Every source can be enabled or disabled independently.

A connected Android smartphone appears in the same list as regular cameras.

## Recording

Every selected camera is recorded to a separate file.

Different cameras can use different settings at the same time.

Example:

    Built-in Mac camera → MOV + built-in microphone
    USB webcam          → MP4 + external microphone
    Android smartphone  → MOV + phone microphone

Supported formats:

    QuickTime Movie (.mov)
    MPEG-4 Video (.mp4)

MOV is recorded directly.

For MP4, the application first creates a temporary MOV recording and converts it to MP4 after recording stops.

If conversion fails, the temporary MOV file is retained so the recording is not lost.

Recordings are stored in the `Downloads` folder by default.

The destination can be changed in the application settings.

## Installation

Download the following files from the latest GitHub Release:

- `Webcamera-Android-<version>.apk`;
- `Webcamera-macOS-<version>.zip`.

### Android

1. Allow application installation from unknown sources.
2. Install the APK on the smartphone.
3. Enable Developer options.
4. Enable USB debugging.
5. Connect the smartphone to the Mac with a USB cable.
6. Approve the USB debugging request if Android displays one.
7. Open the Webcamera application.

The Android application is designed for Android 5.1 and newer compatible Android versions.

Primary testing device:

    Meizu MX5 M575H
    Android 5.1
    Flyme 6.2.0.0G

### macOS

1. Extract the archive.
2. Move `Webcamera.app` to the `Applications` folder.
3. Launch the application.
4. On the first launch, macOS may display a warning because the application is not signed or notarized. In this case, right-click the application and select `Open`.

Android Debug Bridge must be installed on the Mac to use an Android source.

Its availability can be checked with:

    adb version

Webcamera supports macOS 14 and newer.

## Initial setup

### 1. Grant camera and microphone permissions

When Webcamera is opened for the first time, it requests permission to use the camera.

This permission is required to discover, display, and record built-in and external cameras connected to the Mac.

Approve the macOS request.

After an audio source is selected, the application also requests microphone access.

Microphone permission is required for:

- audio recording;
- built-in and external microphone selection;
- live monitoring;
- audio-level display;
- mono or stereo recording.

Allow camera and microphone access so that all features work correctly.

Permissions can also be checked manually in:

    System Settings
    → Privacy & Security
    → Camera

and:

    System Settings
    → Privacy & Security
    → Microphone

### 2. macOS application main window

The main Webcamera window appears after the required permissions are granted.

<div align="center">

<img src="assets/forreadme/1.png" alt="Webcamera for macOS main window" width="600"/>

</div>

The left side of the window contains a menu with all detected sources:

- built-in Mac cameras;
- external USB cameras;
- virtual cameras;
- connected Android devices.

The sidebar can be hidden and opened again.

Every camera can be selected independently. Cards for selected cameras are displayed on the right side of the window.

A regular webcam card can be used to:

- select an available resolution and frame rate;
- select an audio source;
- disable audio recording;
- select MOV or MP4;
- enable mono recording;
- enable live microphone monitoring;
- inspect left and right audio levels;
- start or stop the camera;
- start or stop recording;
- open the video in a separate window with the `Preview` button.

When a camera is selected for the first time, Webcamera attempts to choose its associated microphone automatically when one is available.

It can be replaced with any other microphone detected by macOS:

- the built-in Mac microphone;
- a webcam microphone;
- an external USB microphone;
- an audio-interface input;
- another source exposed through AVFoundation.

The `Live Monitor` button plays the selected source through the current macOS audio output.

Headphones are recommended to prevent acoustic feedback.

The top toolbar contains common controls:

- `Start All` — start all selected cameras;
- `Stop All` — stop all active cameras;
- `Record All` — start recording all running cameras;
- `Stop Recording` — stop all active recordings;
- `Recordings` — open the recording destination;
- `Settings` — open application settings.

The `Recordings` button opens the `Downloads` folder by default.

### 3. Recording and audio settings

Open the settings window with the `Settings` button.

<div align="center">

<img src="assets/forreadme/2.png" alt="Webcamera for macOS settings" width="600"/>

</div>

The settings can be used to:

- select the recording destination;
- restore the `Downloads` destination;
- select the default recording format;
- apply the selected format to all active cameras;
- select the default microphone;
- apply the selected microphone to all active cameras.

The default recording format is applied to newly selected cameras.

The apply-to-all button replaces the individual format of every selected camera with the selected common value.

A system microphone can be selected and applied to all selected sources in the same way.

Individual camera settings can still be changed afterwards.

Camera and audio settings cannot be changed while the corresponding source is recording.

### 4. Android smartphone in the macOS application

After the smartphone is connected through USB and successfully discovered through ADB, it appears in the sidebar as a separate Android camera.

<div align="center">

<img src="assets/forreadme/3.jpeg" alt="Android camera card in Webcamera for macOS" width="600"/>

</div>

The Android camera card can be used to:

- switch between the front and rear phone cameras;
- select an available resolution and frame rate;
- select the phone microphone;
- select any available macOS microphone;
- disable audio completely;
- select MOV or MP4;
- start and stop the stream;
- start and stop recording;
- open a separate preview window;
- enable or disable the phone torch.

The phone microphone is selected by default for an Android source.

It can be replaced with the built-in Mac microphone, an external microphone, or another source detected by the system.

The torch button is available only when the selected phone camera supports it.

This is usually the rear camera.

### 5. Android application before connection

The Android application displays the current service and connection state after launch.

<div align="center">

<img src="assets/forreadme/4.jpg" alt="Webcamera Android application waiting for connection" width="300"/>

</div>

The application displays a waiting state until the Mac connects.

Select `Start Stream` to begin.

The application then prepares the camera, encoder, and local servers.

The phone must be connected to the Mac through USB, and USB debugging must be authorized.

The `Stop Stream` button can be used to stop the stream manually.

The torch can also be enabled or disabled directly from the Android application.

### 6. Android application while streaming

After the Mac connects successfully and the camera starts, the Android application displays an active streaming state.

<div align="center">

<img src="assets/forreadme/5.jpg" alt="Webcamera Android application while streaming" width="300"/>

</div>

While streaming, the phone camera image is displayed in the macOS application.

The camera can be controlled from either the phone or the Mac.

Stopping the stream on the phone ends media transmission.

Stopping the camera in the macOS application sends the corresponding command to the Android application.

Recording is performed on the Mac, so video files are not stored in the phone memory.

## Subsequent launches

After the initial setup, the normal startup process is:

1. connect the Android smartphone to the Mac through USB;
2. make sure USB debugging is enabled;
3. approve the Mac connection if Android displays the request again;
4. open Webcamera on the Mac;
5. open Webcamera on the smartphone;
6. select `Start Stream` on the phone;
7. select the Android camera in the macOS sidebar;
8. select `Start` if the stream does not begin automatically.

An Android smartphone is not required when using regular built-in or external cameras.

## USB connection

The Android device is discovered with:

    adb devices -l

Webcamera uses two local ports:

    27283 — control connection
    27284 — video and audio transport

The Android application opens servers only on the phone loopback interface.

The Mac accesses them through ADB port forwarding.

Wi-Fi, mobile data, and a shared local network are not used.

## Project structure

    Webcamera/
    ├── android-app/
    │   └── Android application, camera, encoders, and TCP servers
    ├── macos-app/
    │   └── macOS application, cameras, decoding, and recording
    ├── assets/
    │   ├── source application icons
    │   └── documentation images
    ├── docs/
    │   └── architecture, development, and USB transport documentation
    ├── shared/
    │   └── shared protocol specification
    ├── scripts/
    │   └── environment, build, launch, and release scripts
    └── .github/
        └── GitHub Actions for Android and macOS builds

## Building from source

### Android

    cd android-app
    ./gradlew --no-daemon clean assembleDebug

Generated APK:

    android-app/app/build/outputs/apk/debug/app-debug.apk

The application can also be built and installed on a connected phone with:

    ./scripts/install-android.sh

### macOS

Xcode project:

    macos-app/Webcamera/Webcamera.xcodeproj

Build from the repository root:

    xcodebuild \
      -project macos-app/Webcamera/Webcamera.xcodeproj \
      -scheme Webcamera \
      -configuration Debug \
      -destination 'platform=macOS' \
      -derivedDataPath macos-app/DerivedData \
      CODE_SIGNING_ALLOWED=NO \
      clean build

Generated application:

    macos-app/DerivedData/Build/Products/Debug/Webcamera.app

The helper script can also be used to build and launch the application:

    ./scripts/run-macos.sh

## Creating a release

Build the Android APK and macOS application archive:

    ./scripts/build-release.sh 1.0.0

Generated files:

    release/Webcamera-Android-1.0.0.apk
    release/Webcamera-macOS-1.0.0.zip

## Development and testing environment

- MacBook Air M2 — macOS Tahoe 26.5.
- Minimum macOS version — macOS 14.
- Meizu MX5 M575H smartphone — Android 5.1, Flyme 6.2.0.0G.
