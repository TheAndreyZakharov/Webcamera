import AVFoundation
import SwiftUI

struct ContentView: View {
  @EnvironmentObject
  private var appState: AppState

  @Environment(\.openWindow)
  private var openWindow

  private let gridColumns = [
    GridItem(
      .adaptive(
        minimum: 380,
        maximum: 720
      ),
      spacing: 14
    )
  ]

  var body: some View {
    Group {
      switch appState.authorizationStatus {
      case .authorized:
        authorizedContent

      case .notDetermined:
        permissionRequest

      case .denied, .restricted:
        permissionDenied

      @unknown default:
        permissionDenied
      }
    }
    .frame(
      minWidth: 980,
      minHeight: 640
    )
    .onAppear {
      appState.refreshAuthorizationStatus()

      if appState.authorizationStatus
        == .authorized
      {
        appState.refreshCameras()
      }
    }
  }

  private var authorizedContent: some View {
    HStack(
      alignment: .top,
      spacing: 0
    ) {
      if appState.isSidebarVisible {
        cameraSidebar
          .frame(
            minWidth: 230,
            idealWidth: 260,
            maxWidth: 320,
            maxHeight: .infinity,
            alignment: .top
          )

        Divider()
      }

      VStack(
        alignment: .leading,
        spacing: 0
      ) {
        toolbar

        Divider()

        cameraGrid
          .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
          )
      }
      .frame(
        maxWidth: .infinity,
        maxHeight: .infinity,
        alignment: .top
      )
    }
    .frame(
      maxWidth: .infinity,
      maxHeight: .infinity,
      alignment: .top
    )
  }

  private var cameraSidebar: some View {
    VStack(alignment: .leading) {
      HStack {
        Text("Cameras")
          .font(.headline)

        Spacer()

        Button {
          appState.refreshCameras()
        } label: {
          Image(
            systemName:
              "arrow.clockwise"
          )
        }
        .help("Refresh Cameras")

        Button {
          appState.toggleSidebar()
        } label: {
          Image(
            systemName:
              "sidebar.left"
          )
        }
        .help("Hide Camera Sidebar")
      }
      .padding(.horizontal, 12)
      .padding(.top, 12)

      if appState.cameras.isEmpty {
        ContentUnavailableView(
          "No Cameras",
          systemImage:
            "video.slash",
          description: Text(
            "Connect a camera and refresh the list."
          )
        )
      } else {
        List {
          ForEach(
            appState.cameras
          ) { camera in
            Toggle(
              isOn: Binding(
                get: {
                  appState
                    .selectedCameraIDs
                    .contains(
                      camera.id
                    )
                },
                set: { selected in
                  appState
                    .setCameraSelected(
                      camera.id,
                      selected:
                        selected
                    )
                }
              )
            ) {
              Label {
                VStack(
                  alignment: .leading,
                  spacing: 2
                ) {
                  Text(camera.name)
                    .lineLimit(2)

                  Text(
                    camera.subtitle
                  )
                  .font(.caption)
                  .foregroundStyle(
                    .secondary
                  )
                }
              } icon: {
                Image(
                  systemName:
                    camera.kind
                    .systemImage
                )
              }
            }
            .toggleStyle(.checkbox)
          }
        }
        .listStyle(.sidebar)
      }

      Divider()

      Text(
        "\(appState.selectedCameraIDs.count) selected"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(12)
    }
  }

  private var toolbar: some View {
    HStack(spacing: 10) {
      if !appState.isSidebarVisible {
        Button {
          appState.toggleSidebar()
        } label: {
          Label(
            "Cameras",
            systemImage:
              "sidebar.left"
          )
        }

        Divider()
          .frame(height: 22)
      }

      Button {
        appState.startAllCameras()
      } label: {
        Label(
          "Start All",
          systemImage: "play.fill"
        )
      }
      .disabled(
        appState.selectedCameraIDs
          .isEmpty
      )

      Button {
        appState.stopAllCameras()
      } label: {
        Label(
          "Stop All",
          systemImage: "stop.fill"
        )
      }
      .disabled(
        !appState.isAnyCameraRunning
      )

      Divider()
        .frame(height: 22)

      if appState.isAnyCameraRecording {
        Button {
          appState.stopRecordingAll()
        } label: {
          Label(
            "Stop Recording",
            systemImage:
              "stop.circle.fill"
          )
        }
        .buttonStyle(
          .borderedProminent
        )
        .tint(.red)
      } else {
        Button {
          appState.startRecordingAll()
        } label: {
          Label(
            "Record All",
            systemImage:
              "record.circle"
          )
        }
        .disabled(
          !appState.isAnyCameraRunning
        )
      }

      Spacer()

      if appState.audioAuthorizationStatus
        == .notDetermined
      {
        Button {
          appState
            .requestMicrophoneAccess()
        } label: {
          Label(
            "Enable Audio",
            systemImage: "mic"
          )
        }
      }

      if appState.audioAuthorizationStatus
        == .denied
        || appState.audioAuthorizationStatus
          == .restricted
      {
        Button {
          appState
            .openMicrophonePrivacySettings()
        } label: {
          Label(
            "Microphone Access",
            systemImage:
              "mic.slash"
          )
        }
      }

      Button {
        appState.openRecordingsFolder()
      } label: {
        Label(
          "Recordings",
          systemImage: "folder"
        )
      }

      SettingsLink {
        Label(
          "Settings",
          systemImage: "gearshape"
        )
      }
    }
    .padding(12)
    .frame(
      maxWidth: .infinity,
      alignment: .topLeading
    )
  }

  private var cameraGrid: some View {
    Group {
      if appState.selectedCameras.isEmpty {
        ContentUnavailableView(
          "No Camera Selected",
          systemImage:
            "rectangle.grid.2x2",
          description: Text(
            "Select one or more cameras in the sidebar."
          )
        )
        .frame(
          maxWidth: .infinity,
          maxHeight: .infinity
        )
      } else {
        ScrollView {
          LazyVGrid(
            columns: gridColumns,
            spacing: 14
          ) {
            ForEach(
              appState.selectedCameras
            ) { camera in
              if camera.isAndroid,
                let controller =
                  appState.androidController(
                    for: camera.id
                  )
              {
                AndroidCameraTileView(
                  camera: camera,
                  controller:
                    controller,
                  configurations:
                    appState.configurations(
                      for: camera.id
                    ),
                  audioDevices:
                    appState.audioDevices(
                      for: camera.id
                    ),
                  selectedConfigurationID:
                    appState
                    .selectedConfigurationID(
                      for: camera.id
                    ),
                  selectedAudioDeviceID:
                    appState
                    .selectedAudioDeviceID(
                      for: camera.id
                    ),
                  selectedRecordingFormat:
                    appState.recordingFormat(
                      for: camera.id
                    ),
                  monoAudioEnabled:
                    appState
                    .isMonoAudioEnabled(
                      for: camera.id
                    ),
                  audioAuthorizationStatus:
                    appState
                    .audioAuthorizationStatus,
                  onConfigurationChanged: {
                    configurationID in

                    appState
                      .selectConfiguration(
                        cameraID:
                          camera.id,
                        configurationID:
                          configurationID
                      )
                  },
                  onAudioDeviceChanged: {
                    audioDeviceID in

                    appState
                      .selectAudioDevice(
                        cameraID:
                          camera.id,
                        audioDeviceID:
                          audioDeviceID
                      )
                  },
                  onRecordingFormatChanged: {
                    format in

                    appState
                      .selectRecordingFormat(
                        cameraID:
                          camera.id,
                        format:
                          format
                      )
                  },
                  onMonoAudioChanged: {
                    enabled in

                    appState
                      .setMonoAudioEnabled(
                        cameraID:
                          camera.id,
                        enabled:
                          enabled
                      )
                  },
                  onRequestMicrophoneAccess: {
                    appState
                      .requestMicrophoneAccess()
                  },
                  onStart: {
                    appState.startCamera(
                      camera.id
                    )
                  },
                  onStop: {
                    appState.stopCamera(
                      camera.id
                    )
                  },
                  onStartRecording: {
                    appState.startRecording(
                      cameraID:
                        camera.id
                    )
                  },
                  onStopRecording: {
                    appState.stopRecording(
                      cameraID:
                        camera.id
                    )
                  },
                  onCameraChanged: {
                    androidCameraID in

                    appState
                      .selectAndroidCamera(
                        cameraID:
                          camera.id,
                        androidCameraID:
                          androidCameraID
                      )
                  },
                  onToggleTorch: {
                    appState
                      .toggleAndroidTorch(
                        cameraID:
                          camera.id
                      )
                  },
                  onOpenPreview: {
                    openWindow(
                      id:
                        "camera-preview",
                      value:
                        camera.id
                    )
                  }
                )
              } else if let controller =
                appState.controller(
                  for: camera.id
                )
              {
                CameraTileView(
                  camera: camera,
                  controller:
                    controller,
                  configurations:
                    appState.configurations(
                      for: camera.id
                    ),
                  audioDevices:
                    appState.audioDevices(
                      for: camera.id
                    ),
                  selectedConfigurationID:
                    appState
                    .selectedConfigurationID(
                      for: camera.id
                    ),
                  selectedAudioDeviceID:
                    appState
                    .selectedAudioDeviceID(
                      for: camera.id
                    ),
                  selectedRecordingFormat:
                    appState.recordingFormat(
                      for: camera.id
                    ),
                  monoAudioEnabled:
                    appState
                    .isMonoAudioEnabled(
                      for: camera.id
                    ),
                  audioAuthorizationStatus:
                    appState
                    .audioAuthorizationStatus,
                  onConfigurationChanged: {
                    configurationID in

                    appState
                      .selectConfiguration(
                        cameraID:
                          camera.id,
                        configurationID:
                          configurationID
                      )
                  },
                  onAudioDeviceChanged: {
                    audioDeviceID in

                    appState
                      .selectAudioDevice(
                        cameraID:
                          camera.id,
                        audioDeviceID:
                          audioDeviceID
                      )
                  },
                  onRecordingFormatChanged: {
                    format in

                    appState
                      .selectRecordingFormat(
                        cameraID:
                          camera.id,
                        format:
                          format
                      )
                  },
                  onMonoAudioChanged: {
                    enabled in

                    appState
                      .setMonoAudioEnabled(
                        cameraID:
                          camera.id,
                        enabled:
                          enabled
                      )
                  },
                  onMonitoringChanged: {
                    enabled in

                    appState
                      .setAudioMonitoringEnabled(
                        cameraID:
                          camera.id,
                        enabled:
                          enabled
                      )
                  },
                  onRequestMicrophoneAccess: {
                    appState
                      .requestMicrophoneAccess()
                  },
                  onStart: {
                    appState.startCamera(
                      camera.id
                    )
                  },
                  onStop: {
                    appState.stopCamera(
                      camera.id
                    )
                  },
                  onStartRecording: {
                    appState
                      .startRecording(
                        cameraID:
                          camera.id
                      )
                  },
                  onStopRecording: {
                    appState
                      .stopRecording(
                        cameraID:
                          camera.id
                      )
                  },
                  onOpenPreview: {
                    openWindow(
                      id:
                        "camera-preview",
                      value:
                        camera.id
                    )
                  }
                )
              }
            }
          }
          .padding(14)
        }
        .background(
          Color(
            nsColor:
              .windowBackgroundColor
          )
        )
      }
    }
  }

  private var permissionRequest: some View {
    VStack(spacing: 18) {
      Image(
        systemName: "video.fill"
      )
      .font(
        .system(size: 58)
      )

      Text(
        "Camera Access Required"
      )
      .font(.title)
      .fontWeight(.semibold)

      Text(
        "Webcamera needs permission to display and record connected cameras."
      )
      .foregroundStyle(.secondary)
      .multilineTextAlignment(
        .center
      )

      Button(
        "Request Camera Access"
      ) {
        appState.requestCameraAccess()
      }
      .buttonStyle(
        .borderedProminent
      )
    }
    .padding(40)
  }

  private var permissionDenied: some View {
    VStack(spacing: 18) {
      Image(
        systemName:
          "video.slash.fill"
      )
      .font(
        .system(size: 58)
      )

      Text(
        "Camera Access Denied"
      )
      .font(.title)
      .fontWeight(.semibold)

      Text(
        "Enable Webcamera in System Settings → Privacy & Security → Camera."
      )
      .foregroundStyle(.secondary)
      .multilineTextAlignment(
        .center
      )

      Button(
        "Open Camera Settings"
      ) {
        appState
          .openCameraPrivacySettings()
      }
    }
    .padding(40)
  }
}

private struct AndroidCameraTileView:
  View
{
  let camera:
    CameraDeviceInfo

  @ObservedObject
  var controller:
    AndroidCameraController

  let configurations:
    [VideoFormat]

  let audioDevices:
    [AudioDeviceInfo]

  let selectedConfigurationID:
    String?

  let selectedAudioDeviceID:
    String

  let selectedRecordingFormat:
    RecordingFileFormat

  let monoAudioEnabled:
    Bool

  let audioAuthorizationStatus:
    AVAuthorizationStatus

  let onConfigurationChanged:
    (String?) -> Void

  let onAudioDeviceChanged:
    (String) -> Void

  let onRecordingFormatChanged:
    (RecordingFileFormat) -> Void

  let onMonoAudioChanged:
    (Bool) -> Void

  let onRequestMicrophoneAccess:
    () -> Void

  let onStart:
    () -> Void

  let onStop:
    () -> Void

  let onStartRecording:
    () -> Void

  let onStopRecording:
    () -> Void

  let onCameraChanged:
    (String) -> Void

  let onToggleTorch:
    () -> Void

  let onOpenPreview:
    () -> Void

  var body: some View {
    VStack(spacing: 0) {
      header

      Divider()

      preview

      Divider()

      controls
    }
    .background(
      .regularMaterial
    )
    .clipShape(
      RoundedRectangle(
        cornerRadius: 12
      )
    )
    .overlay {
      RoundedRectangle(
        cornerRadius: 12
      )
      .stroke(
        Color.secondary
          .opacity(0.25),
        lineWidth: 1
      )
    }
  }

  private var header:
    some View
  {
    HStack {
      Label(
        camera.name,
        systemImage:
          camera.kind
          .systemImage
      )
      .fontWeight(.semibold)
      .lineLimit(1)

      Spacer()

      Button(
        action:
          onOpenPreview
      ) {
        Image(
          systemName:
            "arrow.up.left.and.arrow.down.right"
        )
      }
      .buttonStyle(.plain)

      statusBadge
    }
    .padding(12)
  }

  private var preview:
    some View
  {
    ZStack {
      Color.black

      AndroidVideoPreviewView(
        pixelBuffer:
          controller
          .latestPixelBuffer
      )

      if controller
        .latestPixelBuffer == nil
      {
        VStack(spacing: 10) {
          Image(
            systemName:
              controller.isConnected
              ? "video"
              : "cable.connector"
          )
          .font(.largeTitle)

          Text(
            controller.statusMessage
          )
          .font(.headline)
          .multilineTextAlignment(
            .center
          )
        }
        .foregroundStyle(.white)
        .padding()
      }

      if controller.isRecording {
        VStack {
          HStack {
            Label(
              "REC",
              systemImage:
                "record.circle.fill"
            )
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.red)
            .padding(
              .horizontal,
              9
            )
            .padding(
              .vertical,
              5
            )
            .background(
              .black.opacity(0.75),
              in: Capsule()
            )

            Spacer()
          }

          Spacer()
        }
        .padding(10)
      }

      if let error =
        controller.errorMessage
      {
        VStack {
          Spacer()

          Text(error)
            .font(.caption)
            .foregroundStyle(
              .white
            )
            .multilineTextAlignment(
              .center
            )
            .padding(10)
            .frame(
              maxWidth:
                .infinity
            )
            .background(
              .red.opacity(0.85)
            )
        }
      }
    }
    .aspectRatio(
      16 / 9,
      contentMode: .fit
    )
  }

  private var controls:
    some View
  {
    VStack(spacing: 12) {
      cameraSelectionRow
      videoFormatRow
      audioDeviceRow
      recordingFormatRow

      if selectedAudioDeviceID
        != AudioDeviceInfo.noAudioID
      {
        Toggle(
          "Mono recording",
          isOn: Binding(
            get: {
              monoAudioEnabled
            },
            set: {
              onMonoAudioChanged(
                $0
              )
            }
          )
        )
        .toggleStyle(.checkbox)
        .disabled(
          controller.isRecording
            || selectedAudioDeviceID
              == AudioDeviceInfo
              .phoneAudioID
        )
        .frame(
          maxWidth: .infinity,
          alignment: .leading
        )
      }

      cameraControls
      audioDescription
      recordingDescription

      Text(
        controller.statusMessage
      )
      .font(.caption)
      .foregroundStyle(
        .secondary
      )
      .frame(
        maxWidth: .infinity,
        alignment: .leading
      )
    }
    .padding(12)
  }

  private var cameraSelectionRow:
    some View
  {
    HStack {
      Label(
        "Phone Camera",
        systemImage:
          "camera.rotate"
      )
      .foregroundStyle(
        .secondary
      )

      Spacer()

      if controller
        .cameraOptions
        .isEmpty
      {
        Text(
          controller.isConnected
          ? "Loading cameras…"
          : "Connect to load"
        )
        .foregroundStyle(
          .secondary
        )
      } else {
        Picker(
          "",
          selection:
            Binding(
              get: {
                controller
                  .selectedCameraID
                  ?? controller
                    .cameraOptions
                    .first?
                    .id
                  ?? ""
              },
              set: {
                onCameraChanged(
                  $0
                )
              }
            )
        ) {
          ForEach(
            controller.cameraOptions
          ) { option in
            Label(
              option.displayName,
              systemImage:
                option.facing
                == "front"
                ? "person.crop.rectangle"
                : "camera.fill"
            )
            .tag(option.id)
          }
        }
        .labelsHidden()
        .frame(
          maxWidth: 270
        )
        .disabled(
          controller.isRecording
        )
      }
    }
  }

  private var videoFormatRow:
    some View
  {
    HStack {
      Text("Video")
        .foregroundStyle(
          .secondary
        )

      Spacer()

      Picker(
        "",
        selection:
          Binding(
            get: {
              selectedConfigurationID
            },
            set: {
              onConfigurationChanged(
                $0
              )
            }
          )
      ) {
        ForEach(
          configurations
        ) { configuration in
          Text(
            configuration.title
          )
          .tag(
            Optional(
              configuration.id
            )
          )
        }
      }
      .labelsHidden()
      .frame(
        maxWidth: 270
      )
      .disabled(
        controller.isRecording
      )
    }
  }

  private var audioDeviceRow:
    some View
  {
    HStack {
      Label(
        "Audio",
        systemImage:
          selectedAudioDeviceID
          == AudioDeviceInfo.noAudioID
          ? "mic.slash"
          : "mic"
      )
      .foregroundStyle(
        .secondary
      )

      Spacer()

      if audioAuthorizationStatus
          == .notDetermined,
        selectedAudioDeviceID
          != AudioDeviceInfo
          .phoneAudioID
      {
        Button(
          "Enable Microphone"
        ) {
          onRequestMicrophoneAccess()
        }
      } else {
        Picker(
          "",
          selection:
            Binding(
              get: {
                selectedAudioDeviceID
              },
              set: {
                onAudioDeviceChanged(
                  $0
                )
              }
            )
        ) {
          ForEach(
            audioDevices
          ) { audioDevice in
            Label(
              audioDevice.name,
              systemImage:
                audioDevice.isNoAudio
                ? "mic.slash"
                : audioDevice.isPhoneAudio
                  ? "iphone"
                  : "mic"
            )
            .tag(
              audioDevice.id
            )
          }
        }
        .labelsHidden()
        .frame(
          maxWidth: 270
        )
        .disabled(
          controller.isRecording
        )
      }
    }
  }

  private var recordingFormatRow:
    some View
  {
    HStack {
      Text("Recording")
        .foregroundStyle(
          .secondary
        )

      Spacer()

      Picker(
        "",
        selection:
          Binding(
            get: {
              selectedRecordingFormat
            },
            set: {
              onRecordingFormatChanged(
                $0
              )
            }
          )
      ) {
        ForEach(
          RecordingFileFormat.allCases
        ) { format in
          Text(format.title)
            .tag(format)
        }
      }
      .labelsHidden()
      .frame(
        maxWidth: 270
      )
      .disabled(
        controller.isRecording
      )
    }
  }

  private var cameraControls:
    some View
  {
    HStack {
      if controller.isRunning {
        Button(
          action:
            onStop
        ) {
          Label(
            "Stop",
            systemImage:
              "stop.fill"
          )
        }
      } else {
        Button(
          action:
            onStart
        ) {
          Label(
            "Start",
            systemImage:
              "play.fill"
          )
        }
      }

      Button(
        action:
          onOpenPreview
      ) {
        Label(
          "Preview",
          systemImage:
            "rectangle.on.rectangle"
        )
      }

      Button(
        action:
          onToggleTorch
      ) {
        Label(
          controller
            .torchEnabled
            ? "Torch Off"
            : "Torch On",
          systemImage:
            controller
              .torchEnabled
            ? "flashlight.on.fill"
            : "flashlight.off.fill"
        )
      }
      .disabled(
        !controller
          .torchAvailable
          || !controller
            .isConnected
      )

      Spacer()

      if controller.isRecording {
        Button(
          action:
            onStopRecording
        ) {
          Label(
            "Stop Recording",
            systemImage:
              "stop.circle.fill"
          )
        }
        .tint(.red)
      } else {
        Button(
          action:
            onStartRecording
        ) {
          Label(
            "Record \(selectedRecordingFormat.shortTitle)",
            systemImage:
              "record.circle"
          )
        }
        .disabled(
          !controller.isRunning
            || (
              selectedAudioDeviceID
                == AudioDeviceInfo
                .phoneAudioID
              && !controller
                .phoneAudioAvailable
            )
        )
      }
    }
  }

  @ViewBuilder
  private var audioDescription:
    some View
  {
    if selectedAudioDeviceID
      == AudioDeviceInfo
      .phoneAudioID
    {
      Text(
        controller.phoneAudioAvailable
        ? "Recording audio from the phone microphone."
        : "Waiting for phone microphone packets."
      )
      .font(.caption)
      .foregroundStyle(
        .secondary
      )
      .frame(
        maxWidth: .infinity,
        alignment: .leading
      )
    } else if selectedAudioDeviceID
      == AudioDeviceInfo.noAudioID
    {
      Text(
        "Recording without audio."
      )
      .font(.caption)
      .foregroundStyle(
        .secondary
      )
      .frame(
        maxWidth: .infinity,
        alignment: .leading
      )
    } else if let selectedDevice =
      audioDevices.first(
        where: {
          $0.id
            == selectedAudioDeviceID
        }
      )
    {
      Text(
        monoAudioEnabled
        ? "Recording mono audio from: \(selectedDevice.name)"
        : "Recording audio from: \(selectedDevice.name)"
      )
      .font(.caption)
      .foregroundStyle(
        .secondary
      )
      .lineLimit(1)
      .frame(
        maxWidth: .infinity,
        alignment: .leading
      )
    }
  }

  @ViewBuilder
  private var recordingDescription:
    some View
  {
    if let recordingURL =
      controller.lastRecordingURL,
      !controller.isRecording
    {
      Text(
        "Last recording: \(recordingURL.lastPathComponent)"
      )
      .font(.caption)
      .foregroundStyle(
        .secondary
      )
      .lineLimit(1)
      .truncationMode(
        .middle
      )
      .frame(
        maxWidth: .infinity,
        alignment: .leading
      )
    }
  }

  private var statusBadge:
    some View
  {
    HStack(spacing: 5) {
      Circle()
        .fill(
          statusColor
        )
        .frame(
          width: 8,
          height: 8
        )

      Text(
        statusTitle
      )
      .font(.caption)
    }
    .padding(
      .horizontal,
      8
    )
    .padding(
      .vertical,
      4
    )
    .background(
      Color.secondary
        .opacity(0.12),
      in: Capsule()
    )
  }

  private var statusTitle:
    String
  {
    if controller.isRecording {
      return "Recording"
    }

    if controller.isRunning {
      return "Running"
    }

    if controller.isConnected {
      return "Connected"
    }

    if controller.errorMessage
      != nil
    {
      return "Error"
    }

    return "Disconnected"
  }

  private var statusColor:
    Color
  {
    if controller.isRecording {
      return .red
    }

    if controller.isRunning {
      return .green
    }

    if controller.errorMessage
      != nil
    {
      return .red
    }

    if controller.isConnected {
      return .orange
    }

    return .secondary
  }
}

private struct CameraTileView: View {
  let camera: CameraDeviceInfo

  @ObservedObject
  var controller: CameraController

  let configurations: [VideoFormat]
  let audioDevices: [AudioDeviceInfo]

  let selectedConfigurationID: String?
  let selectedAudioDeviceID: String
  let selectedRecordingFormat: RecordingFileFormat
  let monoAudioEnabled: Bool

  let audioAuthorizationStatus: AVAuthorizationStatus

  let onConfigurationChanged: (String?) -> Void
  let onAudioDeviceChanged: (String) -> Void
  let onRecordingFormatChanged: (RecordingFileFormat) -> Void
  let onMonoAudioChanged: (Bool) -> Void
  let onMonitoringChanged: (Bool) -> Void
  let onRequestMicrophoneAccess: () -> Void
  let onStart: () -> Void
  let onStop: () -> Void
  let onStartRecording: () -> Void
  let onStopRecording: () -> Void
  let onOpenPreview: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      header

      Divider()

      preview

      Divider()

      controls
    }
    .background(
      .regularMaterial
    )
    .clipShape(
      RoundedRectangle(
        cornerRadius: 12
      )
    )
    .overlay {
      RoundedRectangle(
        cornerRadius: 12
      )
      .stroke(
        Color.secondary
          .opacity(0.25),
        lineWidth: 1
      )
    }
  }

  private var header: some View {
    HStack {
      Label(
        camera.name,
        systemImage:
          camera.kind.systemImage
      )
      .fontWeight(.semibold)
      .lineLimit(1)

      Spacer()

      Button(
        action: onOpenPreview
      ) {
        Image(
          systemName:
            "arrow.up.left.and.arrow.down.right"
        )
      }
      .buttonStyle(.plain)

      statusBadge
    }
    .padding(12)
  }

  private var preview: some View {
    ZStack {
      Color.black

      VideoPreviewView(
        session: controller.session
      )

      if !controller.isRunning {
        VStack(spacing: 10) {
          Image(
            systemName:
              "video.slash"
          )
          .font(.largeTitle)

          Text("Camera stopped")
            .font(.headline)
        }
        .foregroundStyle(.white)
      }

      if let error =
        controller.errorMessage
      {
        VStack {
          Spacer()

          Text(error)
            .font(.caption)
            .foregroundStyle(.white)
            .multilineTextAlignment(
              .center
            )
            .padding(10)
            .frame(
              maxWidth: .infinity
            )
            .background(
              .red.opacity(0.85)
            )
        }
      }

      if controller.isRecording {
        VStack {
          HStack {
            Label(
              "REC",
              systemImage:
                "record.circle.fill"
            )
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.red)
            .padding(
              .horizontal,
              9
            )
            .padding(
              .vertical,
              5
            )
            .background(
              .black.opacity(0.75),
              in: Capsule()
            )

            Spacer()
          }

          Spacer()
        }
        .padding(10)
      }
    }
    .aspectRatio(
      16 / 9,
      contentMode: .fit
    )
  }

  private var controls: some View {
    VStack(spacing: 12) {
      videoFormatRow
      audioDeviceRow
      recordingFormatRow

      if selectedAudioDeviceID
        != AudioDeviceInfo.noAudioID
      {
        audioControls
      }

      cameraControls
      audioDescription
      recordingDescription
    }
    .padding(12)
  }

  private var videoFormatRow: some View {
    HStack {
      Text("Video")
        .foregroundStyle(
          .secondary
        )

      Spacer()

      if configurations.isEmpty {
        Text("Driver default")
          .foregroundStyle(
            .secondary
          )
      } else {
        Picker(
          "",
          selection: Binding(
            get: {
              selectedConfigurationID
            },
            set: {
              onConfigurationChanged(
                $0
              )
            }
          )
        ) {
          ForEach(
            configurations
          ) { configuration in
            Text(
              configuration.title
            )
            .tag(
              Optional(
                configuration.id
              )
            )
          }
        }
        .labelsHidden()
        .frame(
          maxWidth: 270
        )
        .disabled(
          controller.isRecording
        )
      }
    }
  }

  private var audioDeviceRow: some View {
    HStack {
      Label(
        "Audio",
        systemImage:
          selectedAudioDeviceID
          == AudioDeviceInfo.noAudioID
          ? "mic.slash"
          : "mic"
      )
      .foregroundStyle(
        .secondary
      )

      Spacer()

      if audioAuthorizationStatus
        == .notDetermined
      {
        Button(
          "Enable Microphone"
        ) {
          onRequestMicrophoneAccess()
        }
      } else {
        Picker(
          "",
          selection: Binding(
            get: {
              selectedAudioDeviceID
            },
            set: {
              onAudioDeviceChanged(
                $0
              )
            }
          )
        ) {
          ForEach(
            audioDevices
          ) { audioDevice in
            Label(
              audioDevice.name,
              systemImage:
                audioDevice.isNoAudio
                ? "mic.slash"
                : "mic"
            )
            .tag(audioDevice.id)
          }
        }
        .labelsHidden()
        .frame(
          maxWidth: 270
        )
        .disabled(
          controller.isRecording
        )
      }
    }
  }

  private var recordingFormatRow: some View {
    HStack {
      Text("Recording")
        .foregroundStyle(
          .secondary
        )

      Spacer()

      Picker(
        "",
        selection: Binding(
          get: {
            selectedRecordingFormat
          },
          set: {
            onRecordingFormatChanged(
              $0
            )
          }
        )
      ) {
        ForEach(
          RecordingFileFormat.allCases
        ) { format in
          Text(format.title)
            .tag(format)
        }
      }
      .labelsHidden()
      .frame(
        maxWidth: 270
      )
      .disabled(
        controller.isRecording
      )
    }
  }

  private var audioControls: some View {
    VStack(spacing: 9) {
      HStack {
        Toggle(
          "Mono recording",
          isOn: Binding(
            get: {
              monoAudioEnabled
            },
            set: {
              onMonoAudioChanged(
                $0
              )
            }
          )
        )
        .toggleStyle(.checkbox)
        .disabled(
          controller.isRecording
        )

        Spacer()

        Toggle(
          isOn: Binding(
            get: {
              controller
                .isAudioMonitoring
            },
            set: {
              onMonitoringChanged(
                $0
              )
            }
          )
        ) {
          Label(
            "Live Monitor",
            systemImage:
              controller.isAudioMonitoring
              ? "headphones.circle.fill"
              : "headphones.circle"
          )
        }
        .toggleStyle(.button)
        .disabled(
          !controller.isRunning
            || !controller.hasAudioInput
        )
      }

      AudioLevelMeter(
        title: "L",
        level:
          controller.leftAudioLevel
      )

      AudioLevelMeter(
        title: "R",
        level:
          controller.rightAudioLevel
      )

      if controller.isAudioMonitoring {
        Label(
          "Live microphone monitoring is active. Use headphones to prevent feedback.",
          systemImage:
            "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(
          .orange
        )
        .frame(
          maxWidth: .infinity,
          alignment: .leading
        )
      }
    }
    .padding(10)
    .background(
      Color.secondary
        .opacity(0.08),
      in: RoundedRectangle(
        cornerRadius: 8
      )
    )
  }

  private var cameraControls: some View {
    HStack {
      if controller.isRunning {
        Button(
          action: onStop
        ) {
          Label(
            "Stop",
            systemImage:
              "stop.fill"
          )
        }
      } else {
        Button(
          action: onStart
        ) {
          Label(
            "Start",
            systemImage:
              "play.fill"
          )
        }
      }

      Button(
        action: onOpenPreview
      ) {
        Label(
          "Preview",
          systemImage:
            "rectangle.on.rectangle"
        )
      }

      Spacer()

      if controller.isRecording {
        Button(
          action:
            onStopRecording
        ) {
          Label(
            "Stop Recording",
            systemImage:
              "stop.circle.fill"
          )
        }
        .tint(.red)
      } else {
        Button(
          action:
            onStartRecording
        ) {
          Label(
            "Record \(selectedRecordingFormat.shortTitle)",
            systemImage:
              "record.circle"
          )
        }
        .disabled(
          !controller.isRunning
            || !controller.canRecord
        )
      }
    }
  }

  @ViewBuilder
  private var audioDescription: some View {
    if controller.hasAudioInput,
      let audioName =
        controller
        .activeAudioDeviceName
    {
      Text(
        monoAudioEnabled
          ? "Recording mono audio from: \(audioName)"
          : "Recording audio from: \(audioName)"
      )
      .font(.caption)
      .foregroundStyle(
        .secondary
      )
      .lineLimit(1)
      .frame(
        maxWidth: .infinity,
        alignment: .leading
      )
    } else {
      Text(
        "Recording without audio"
      )
      .font(.caption)
      .foregroundStyle(
        .secondary
      )
      .frame(
        maxWidth: .infinity,
        alignment: .leading
      )
    }
  }

  @ViewBuilder
  private var recordingDescription: some View {
    if !controller.canRecord,
      controller.isConfigured
    {
      Text(
        "This camera supports preview but does not expose movie recording."
      )
      .font(.caption)
      .foregroundStyle(
        .secondary
      )
      .frame(
        maxWidth: .infinity,
        alignment: .leading
      )
    }

    if let recordingURL =
      controller.lastRecordingURL,
      !controller.isRecording
    {
      Text(
        "Last recording: \(recordingURL.lastPathComponent)"
      )
      .font(.caption)
      .foregroundStyle(
        .secondary
      )
      .lineLimit(1)
      .truncationMode(
        .middle
      )
      .frame(
        maxWidth: .infinity,
        alignment: .leading
      )
    }
  }

  private var statusBadge: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(statusColor)
        .frame(
          width: 8,
          height: 8
        )

      Text(statusTitle)
        .font(.caption)
    }
    .padding(
      .horizontal,
      8
    )
    .padding(
      .vertical,
      4
    )
    .background(
      Color.secondary
        .opacity(0.12),
      in: Capsule()
    )
  }

  private var statusTitle: String {
    if controller.isRecording {
      return "Recording"
    }

    if controller.isRunning {
      return "Running"
    }

    if controller.isConfigured {
      return "Stopped"
    }

    return "Not configured"
  }

  private var statusColor: Color {
    if controller.isRecording {
      return .red
    }

    if controller.isRunning {
      return .green
    }

    if controller.errorMessage != nil {
      return .red
    }

    return .secondary
  }
}

private struct AudioLevelMeter: View {
  let title: String
  let level: Double

  var body: some View {
    HStack(spacing: 8) {
      Text(title)
        .font(
          .system(
            .caption,
            design: .monospaced
          )
        )
        .frame(width: 12)

      GeometryReader { geometry in
        ZStack(
          alignment: .leading
        ) {
          Capsule()
            .fill(
              Color.secondary
                .opacity(0.16)
            )

          Capsule()
            .fill(
              meterColor
            )
            .frame(
              width:
                geometry.size.width
                * min(
                  1,
                  max(
                    0,
                    level
                  )
                )
            )
        }
      }
      .frame(height: 8)

      Text(
        percentageTitle
      )
      .font(
        .system(
          .caption2,
          design: .monospaced
        )
      )
      .foregroundStyle(
        .secondary
      )
      .frame(
        width: 38,
        alignment: .trailing
      )
    }
    .frame(height: 14)
  }

  private var percentageTitle: String {
    "\(Int((level * 100).rounded()))%"
  }

  private var meterColor: Color {
    if level >= 0.9 {
      return .red
    }

    if level >= 0.7 {
      return .orange
    }

    return .green
  }
}

struct CameraPreviewWindow:
  View
{
  @EnvironmentObject
  private var appState:
    AppState

  let cameraID:
    String

  var body: some View {
    Group {
      if let androidController =
        appState.androidController(
          for: cameraID
        )
      {
        androidPreview(
          androidController
        )
      } else if let controller =
        appState.controller(
          for: cameraID
        )
      {
        localPreview(
          controller
        )
      } else {
        ContentUnavailableView(
          "Camera Unavailable",
          systemImage:
            "video.slash",
          description: Text(
            "The camera is no longer selected or connected."
          )
        )
      }
    }
    .frame(
      minWidth: 640,
      minHeight: 400
    )
    .navigationTitle(
      appState.cameraName(
        for: cameraID
      )
    )
  }

  private func androidPreview(
    _ controller:
      AndroidCameraController
  ) -> some View {
    ZStack {
      Color.black
        .ignoresSafeArea()

      AndroidVideoPreviewView(
        pixelBuffer:
          controller
          .latestPixelBuffer
      )

      if controller
        .latestPixelBuffer == nil
      {
        VStack(spacing: 12) {
          Image(
            systemName:
              "video.slash"
          )
          .font(
            .system(size: 48)
          )

          Text(
            controller
              .statusMessage
          )
          .font(.title2)

          Button(
            "Start Camera"
          ) {
            appState.startCamera(
              cameraID
            )
          }
        }
        .foregroundStyle(
          .white
        )
      }

      VStack {
        HStack {
          Spacer()

          if controller
            .torchAvailable
          {
            Button {
              appState
                .toggleAndroidTorch(
                  cameraID:
                    cameraID
                )
            } label: {
              Image(
                systemName:
                  controller
                    .torchEnabled
                  ? "flashlight.on.fill"
                  : "flashlight.off.fill"
              )
              .font(.title2)
            }
            .buttonStyle(
              .borderedProminent
            )
          }
        }

        Spacer()
      }
      .padding()

      if controller.isRecording {
        VStack {
          HStack {
            Label(
              "REC",
              systemImage:
                "record.circle.fill"
            )
            .fontWeight(.bold)
            .foregroundStyle(.red)
            .padding(
              .horizontal,
              10
            )
            .padding(
              .vertical,
              6
            )
            .background(
              .black.opacity(0.65),
              in: Capsule()
            )

            Spacer()
          }

          Spacer()
        }
        .padding()
      }

      if let error =
        controller.errorMessage
      {
        VStack {
          Spacer()

          Text(error)
            .foregroundStyle(
              .white
            )
            .padding(12)
            .frame(
              maxWidth:
                .infinity
            )
            .background(
              .red.opacity(0.85)
            )
        }
      }
    }
  }

  private func localPreview(
    _ controller:
      CameraController
  ) -> some View {
    ZStack {
      Color.black
        .ignoresSafeArea()

      VideoPreviewView(
        session:
          controller.session
      )

      if !controller.isRunning {
        VStack(spacing: 12) {
          Image(
            systemName:
              "video.slash"
          )
          .font(
            .system(size: 48)
          )

          Text(
            "Camera stopped"
          )
          .font(.title2)

          Button(
            "Start Camera"
          ) {
            appState.startCamera(
              cameraID
            )
          }
        }
        .foregroundStyle(
          .white
        )
      }

      if controller.isRecording {
        VStack {
          HStack {
            Spacer()

            Label(
              "REC",
              systemImage:
                "record.circle.fill"
            )
            .fontWeight(.bold)
            .foregroundStyle(
              .red
            )
            .padding(
              .horizontal,
              10
            )
            .padding(
              .vertical,
              6
            )
            .background(
              .black.opacity(0.65),
              in: Capsule()
            )
          }

          Spacer()
        }
        .padding()
      }
    }
  }
}
