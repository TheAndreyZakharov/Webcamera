import AppKit
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject
  private var appState: AppState

  @AppStorage(
    "recordingFolderPath"
  )
  private var recordingFolderPath =
    ""

  @AppStorage(
    "recordingFileFormat"
  )
  private var recordingFileFormat =
    RecordingFileFormat.mov.rawValue

  var body: some View {
    Form {
      Section("Recording") {
        LabeledContent(
          "Destination"
        ) {
          Text(
            displayedFolderPath
          )
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
        }

        HStack {
          Button(
            "Choose Folder"
          ) {
            chooseFolder()
          }

          Button(
            "Use Downloads"
          ) {
            recordingFolderPath = ""
          }
        }

        Picker(
          "Default File Format",
          selection:
            $recordingFileFormat
        ) {
          ForEach(
            RecordingFileFormat.allCases
          ) { format in
            Text(format.title)
              .tag(format.rawValue)
          }
        }

        Text(
          recordingFormatDescription
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Button(
          "Apply Default Format to All Selected Cameras"
        ) {
          appState
            .applyDefaultRecordingFormatToAll()
        }
        .disabled(
          appState.selectedCameraIDs
            .isEmpty
            || appState
              .isAnyCameraRecording
        )

        Text(
          "Each camera can use its own format. The button above replaces the individual format of every selected camera with this default."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Audio") {
        Text(
          "Live Monitor plays the selected microphone through the current macOS audio output. Headphones are recommended to prevent feedback."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Text(
          "Mono recording creates a one-channel audio track and is useful when an audio interface supplies the microphone only on its left input."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Camera formats") {
        Text(
          "Resolution and reported frame rate are shown as one configuration. Some macOS camera drivers choose the actual frame rate themselves even when they advertise several supported values."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(
      width: 620,
      height: 500
    )
    .padding()
  }

  private var recordingFormatDescription: String {
    switch RecordingFileFormat(
      rawValue:
        recordingFileFormat
    ) {
    case .mp4:
      return
        "MP4 is the default for newly selected cameras. Each camera is captured separately and converted after recording stops."

    case .mov, .none:
      return
        "MOV is the default for newly selected cameras. Each camera creates a separate QuickTime movie."
    }
  }

  private var displayedFolderPath: String {
    if !recordingFolderPath.isEmpty {
      return recordingFolderPath
    }

    return FileManager.default
      .urls(
        for: .downloadsDirectory,
        in: .userDomainMask
      )
      .first?
      .path
      ?? "~/Downloads"
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()

    panel.title =
      "Choose Recording Folder"

    panel.prompt =
      "Choose"

    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true

    if !recordingFolderPath.isEmpty {
      panel.directoryURL =
        URL(
          fileURLWithPath:
            recordingFolderPath,
          isDirectory: true
        )
    } else {
      panel.directoryURL =
        FileManager.default
        .urls(
          for: .downloadsDirectory,
          in: .userDomainMask
        )
        .first
    }

    guard
      panel.runModal() == .OK,
      let url = panel.url
    else {
      return
    }

    recordingFolderPath =
      url.path
  }
}
