import SwiftUI

@main
struct WebcameraApp: App {
  @StateObject
  private var appState =
    AppState()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(
          appState
        )
    }
    .defaultSize(
      width: 1280,
      height: 800
    )
    .commands {
      CommandGroup(
        after: .appInfo
      ) {
        Button(
          appState.isSidebarVisible
            ? "Hide Camera Sidebar"
            : "Show Camera Sidebar"
        ) {
          appState.toggleSidebar()
        }
        .keyboardShortcut(
          "s",
          modifiers: [
            .command,
            .option,
          ]
        )

        Divider()

        Button(
          "Refresh Cameras"
        ) {
          appState.refreshCameras()
        }
        .keyboardShortcut(
          "r",
          modifiers: [.command]
        )

        Divider()

        Button(
          "Start All Cameras"
        ) {
          appState.startAllCameras()
        }

        Button(
          "Stop All Cameras"
        ) {
          appState.stopAllCameras()
        }

        Divider()

        Button(
          appState
            .isAnyCameraRecording
            ? "Stop All Recordings"
            : "Record All Cameras"
        ) {
          if appState
            .isAnyCameraRecording
          {
            appState
              .stopRecordingAll()
          } else {
            appState
              .startRecordingAll()
          }
        }
        .keyboardShortcut(
          "r",
          modifiers: [
            .command,
            .shift,
          ]
        )
      }
    }

    WindowGroup(
      "Camera Preview",
      id: "camera-preview",
      for: String.self
    ) { $cameraID in
      if let cameraID {
        CameraPreviewWindow(
          cameraID: cameraID
        )
        .environmentObject(
          appState
        )
      } else {
        ContentUnavailableView(
          "Camera Unavailable",
          systemImage: "video.slash"
        )
      }
    }
    .defaultSize(
      width: 960,
      height: 640
    )

    Settings {
      SettingsView()
        .environmentObject(
          appState
        )
    }
  }
}
