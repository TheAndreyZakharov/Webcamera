import AVFoundation
import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
  @Published private(set)
    var authorizationStatus =
    AVCaptureDevice.authorizationStatus(
      for: .video
    )

  @Published private(set)
    var audioAuthorizationStatus =
    AVCaptureDevice.authorizationStatus(
      for: .audio
    )

  @Published private(set)
    var cameras: [CameraDeviceInfo] = []

  @Published private(set)
    var audioDevices: [AudioDeviceInfo] = [
      .noAudio
    ]

  @Published var selectedCameraIDs =
    Set<String>()

  @Published private(set)
    var selectedConfigurationIDs: [String: String] = [:]

  @Published private(set)
    var selectedAudioDeviceIDs: [String: String] = [:]

  @Published private(set)
    var selectedRecordingFormats: [String: RecordingFileFormat] = [:]

  @Published private(set)
    var selectedMonoAudioStates: [String: Bool] = [:]

  @Published private(set)
    var controllers: [String: CameraController] = [:]

  @Published var isSidebarVisible = true
  @Published var isSettingsPresented = false

  private var controllerTeardownTokens: [String: UUID] = [:]

  var selectedCameras: [CameraDeviceInfo] {
    cameras.filter {
      selectedCameraIDs.contains($0.id)
    }
  }

  var isAnyCameraRunning: Bool {
    controllers.values.contains {
      $0.isRunning
    }
  }

  var isAnyCameraRecording: Bool {
    controllers.values.contains {
      $0.isRecording
    }
  }

  init() {
    refreshAuthorizationStatus()

    if authorizationStatus == .authorized {
      refreshCameras()
    }

    if audioAuthorizationStatus == .authorized {
      refreshAudioDevices()
    } else {
      audioDevices = [.noAudio]
    }
  }

  func requestCameraAccess() {
    AVCaptureDevice.requestAccess(
      for: .video
    ) { [weak self] granted in
      DispatchQueue.main.async {
        guard let self else {
          return
        }

        self.authorizationStatus =
          granted
          ? .authorized
          : .denied

        if granted {
          self.refreshCameras()
        }
      }
    }
  }

  func requestMicrophoneAccess() {
    AVCaptureDevice.requestAccess(
      for: .audio
    ) { [weak self] granted in
      DispatchQueue.main.async {
        guard let self else {
          return
        }

        self.audioAuthorizationStatus =
          granted
          ? .authorized
          : .denied

        if granted {
          self.refreshAudioDevices()
          self.applyDefaultAudioSelections()
          self.reconfigureSelectedCameras()
        } else {
          self.audioDevices = [.noAudio]

          for cameraID in self.selectedCameraIDs {
            self.selectedAudioDeviceIDs[cameraID] =
              AudioDeviceInfo.noAudioID

            self.configureCamera(cameraID)
          }
        }
      }
    }
  }

  func refreshAuthorizationStatus() {
    authorizationStatus =
      AVCaptureDevice.authorizationStatus(
        for: .video
      )

    audioAuthorizationStatus =
      AVCaptureDevice.authorizationStatus(
        for: .audio
      )
  }

  func refreshCameras() {
    guard authorizationStatus == .authorized else {
      stopAndRemoveAllControllers()

      cameras = []
      selectedCameraIDs = []
      selectedConfigurationIDs = [:]
      selectedAudioDeviceIDs = [:]
      selectedRecordingFormats = [:]
      selectedMonoAudioStates = [:]
      controllerTeardownTokens = [:]

      return
    }

    if audioAuthorizationStatus == .authorized {
      refreshAudioDevices()
    }

    let previousSelection =
      selectedCameraIDs

    let discoveredCameras =
      CameraDeviceInfo.localCameras()

    let availableIDs =
      Set(discoveredCameras.map(\.id))

    cameras = discoveredCameras

    selectedCameraIDs =
      previousSelection.intersection(
        availableIDs
      )

    if selectedCameraIDs.isEmpty,
      controllers.isEmpty,
      let firstCamera = cameras.first
    {
      selectedCameraIDs.insert(
        firstCamera.id
      )
    }

    removeUnavailableControllers(
      availableIDs: availableIDs
    )

    for camera in selectedCameras {
      cancelScheduledControllerRemoval(
        cameraID: camera.id
      )

      ensureController(
        for: camera
      )

      ensureConfigurationSelection(
        for: camera
      )

      ensureAudioSelection(
        for: camera
      )

      ensureRecordingFormatSelection(
        for: camera.id
      )

      ensureMonoAudioSelection(
        for: camera.id
      )

      configureCamera(camera.id)
    }
  }

  func refreshAudioDevices() {
    guard audioAuthorizationStatus == .authorized else {
      audioDevices = [.noAudio]
      return
    }

    audioDevices =
      AudioDeviceInfo.systemAudioDevices()

    let availableAudioIDs =
      Set(audioDevices.map(\.id))

    for camera in selectedCameras {
      if let selectedID =
        selectedAudioDeviceIDs[camera.id],
        availableAudioIDs.contains(
          selectedID
        )
      {
        continue
      }

      selectedAudioDeviceIDs[camera.id] =
        AudioDeviceInfo.preferredDeviceID(
          for: camera,
          from: audioDevices
        )
    }
  }

  func toggleSidebar() {
    isSidebarVisible.toggle()
  }

  func setCameraSelected(
    _ cameraID: String,
    selected: Bool
  ) {
    guard
      let camera = camera(
        withID: cameraID
      )
    else {
      return
    }

    if selected {
      cancelScheduledControllerRemoval(
        cameraID: cameraID
      )

      selectedCameraIDs.insert(
        cameraID
      )

      ensureController(
        for: camera
      )

      ensureConfigurationSelection(
        for: camera
      )

      ensureAudioSelection(
        for: camera
      )

      ensureRecordingFormatSelection(
        for: cameraID
      )

      ensureMonoAudioSelection(
        for: cameraID
      )

      configureCamera(cameraID)
    } else {
      selectedCameraIDs.remove(
        cameraID
      )

      scheduleControllerRemoval(
        cameraID: cameraID
      )
    }
  }

  func configurations(
    for cameraID: String
  ) -> [VideoFormat] {
    camera(withID: cameraID)?
      .formats
      ?? []
  }

  func selectedConfigurationID(
    for cameraID: String
  ) -> String? {
    selectedConfigurationIDs[
      cameraID
    ]
  }

  func selectConfiguration(
    cameraID: String,
    configurationID: String?
  ) {
    guard selectedCameraIDs.contains(cameraID) else {
      return
    }

    selectedConfigurationIDs[
      cameraID
    ] = configurationID

    configureCamera(cameraID)
  }

  func selectedAudioDeviceID(
    for cameraID: String
  ) -> String {
    selectedAudioDeviceIDs[
      cameraID
    ]
      ?? AudioDeviceInfo.noAudioID
  }

  func selectAudioDevice(
    cameraID: String,
    audioDeviceID: String
  ) {
    guard selectedCameraIDs.contains(cameraID) else {
      return
    }

    if audioDeviceID != AudioDeviceInfo.noAudioID,
      audioAuthorizationStatus != .authorized
    {
      requestMicrophoneAccess()
      return
    }

    selectedAudioDeviceIDs[
      cameraID
    ] = audioDeviceID

    configureCamera(cameraID)
  }

  func recordingFormat(
    for cameraID: String
  ) -> RecordingFileFormat {
    selectedRecordingFormats[
      cameraID
    ]
      ?? defaultRecordingFileFormat
  }

  func selectRecordingFormat(
    cameraID: String,
    format: RecordingFileFormat
  ) {
    guard
      selectedCameraIDs.contains(
        cameraID
      ),
      controllers[cameraID]?.isRecording
        != true
    else {
      return
    }

    selectedRecordingFormats[
      cameraID
    ] = format
  }

  func isMonoAudioEnabled(
    for cameraID: String
  ) -> Bool {
    selectedMonoAudioStates[
      cameraID
    ]
      ?? false
  }

  func setMonoAudioEnabled(
    cameraID: String,
    enabled: Bool
  ) {
    guard
      selectedCameraIDs.contains(
        cameraID
      ),
      let controller =
        controllers[cameraID],
      !controller.isRecording
    else {
      return
    }

    selectedMonoAudioStates[
      cameraID
    ] = enabled

    controller.setMonoAudioEnabled(
      enabled
    )
  }

  func setAudioMonitoringEnabled(
    cameraID: String,
    enabled: Bool
  ) {
    guard
      selectedCameraIDs.contains(
        cameraID
      ),
      let controller =
        controllers[cameraID]
    else {
      return
    }

    controller.setAudioMonitoringEnabled(
      enabled
    )
  }

  func controller(
    for cameraID: String
  ) -> CameraController? {
    controllers[cameraID]
  }

  func cameraName(
    for cameraID: String
  ) -> String {
    camera(withID: cameraID)?
      .name
      ?? "Camera Preview"
  }

  func startCamera(
    _ cameraID: String
  ) {
    guard
      selectedCameraIDs.contains(cameraID),
      let controller =
        controllers[cameraID]
    else {
      return
    }

    if controller.isConfigured {
      controller.start()
    } else {
      configureCamera(cameraID)
    }
  }

  func stopCamera(
    _ cameraID: String
  ) {
    controllers[cameraID]?
      .stop()
  }

  func startAllCameras() {
    for cameraID in selectedCameraIDs {
      startCamera(cameraID)
    }
  }

  func stopAllCameras() {
    for cameraID in selectedCameraIDs {
      controllers[cameraID]?
        .stop()
    }
  }

  func startRecording(
    cameraID: String
  ) {
    guard
      selectedCameraIDs.contains(cameraID),
      let controller =
        controllers[cameraID],
      controller.isRunning
    else {
      return
    }

    controller.startRecording(
      folderURL: recordingFolderURL,
      format: recordingFormat(
        for: cameraID
      )
    )
  }

  func stopRecording(
    cameraID: String
  ) {
    controllers[cameraID]?
      .stopRecording()
  }

  func startRecordingAll() {
    for cameraID in selectedCameraIDs {
      guard
        let controller =
          controllers[cameraID],
        controller.isRunning,
        controller.canRecord
      else {
        continue
      }

      controller.startRecording(
        folderURL: recordingFolderURL,
        format: recordingFormat(
          for: cameraID
        )
      )
    }
  }

  func stopRecordingAll() {
    for controller in controllers.values
    where controller.isRecording {
      controller.stopRecording()
    }
  }

  func applyDefaultRecordingFormatToAll() {
    let format =
      defaultRecordingFileFormat

    for cameraID in selectedCameraIDs {
      guard
        controllers[cameraID]?
          .isRecording != true
      else {
        continue
      }

      selectedRecordingFormats[
        cameraID
      ] = format
    }
  }

  func openRecordingsFolder() {
    NSWorkspace.shared.open(
      recordingFolderURL
    )
  }

  func openCameraPrivacySettings() {
    guard
      let url = URL(
        string:
          "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
      )
    else {
      return
    }

    NSWorkspace.shared.open(url)
  }

  func openMicrophonePrivacySettings() {
    guard
      let url = URL(
        string:
          "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
      )
    else {
      return
    }

    NSWorkspace.shared.open(url)
  }

  private var defaultRecordingFileFormat: RecordingFileFormat {
    let rawValue =
      UserDefaults.standard.string(
        forKey: "recordingFileFormat"
      )
      ?? RecordingFileFormat.mov.rawValue

    return RecordingFileFormat(
      rawValue: rawValue
    )
      ?? .mov
  }

  private var recordingFolderURL: URL {
    let storedPath =
      UserDefaults.standard.string(
        forKey: "recordingFolderPath"
      )
      ?? ""

    if !storedPath.isEmpty {
      return URL(
        fileURLWithPath: storedPath,
        isDirectory: true
      )
    }

    return FileManager.default
      .urls(
        for: .downloadsDirectory,
        in: .userDomainMask
      )
      .first
      ?? FileManager.default
      .homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Downloads",
        isDirectory: true
      )
  }

  private func camera(
    withID cameraID: String
  ) -> CameraDeviceInfo? {
    cameras.first {
      $0.id == cameraID
    }
  }

  private func audioDevice(
    withID audioDeviceID: String
  ) -> AudioDeviceInfo? {
    audioDevices.first {
      $0.id == audioDeviceID
    }
  }

  private func configureCamera(
    _ cameraID: String
  ) {
    guard
      selectedCameraIDs.contains(cameraID),
      let camera =
        camera(withID: cameraID),
      let controller =
        controllers[cameraID]
    else {
      return
    }

    let configuration =
      selectedConfiguration(
        for: camera
      )

    let selectedAudioID =
      selectedAudioDeviceID(
        for: cameraID
      )

    let selectedAudioDevice =
      audioDevice(
        withID: selectedAudioID
      )
      ?? .noAudio

    let monoAudio =
      isMonoAudioEnabled(
        for: cameraID
      )

    controller.configure(
      camera: camera,
      configuration: configuration,
      audioDevice: selectedAudioDevice,
      monoAudio: monoAudio
    )
  }

  private func selectedConfiguration(
    for camera: CameraDeviceInfo
  ) -> VideoFormat? {
    guard
      let selectedID =
        selectedConfigurationIDs[
          camera.id
        ]
    else {
      return nil
    }

    return camera.formats.first {
      $0.id == selectedID
    }
  }

  private func ensureController(
    for camera: CameraDeviceInfo
  ) {
    guard controllers[camera.id] == nil else {
      return
    }

    let controller =
      CameraController(
        cameraID: camera.id,
        cameraName: camera.name
      )

    controller.onStateChange = {
      Task { @MainActor [weak self] in
        self?.objectWillChange.send()
      }
    }

    controllers[camera.id] =
      controller
  }

  private func ensureConfigurationSelection(
    for camera: CameraDeviceInfo
  ) {
    if let existingID =
      selectedConfigurationIDs[
        camera.id
      ],
      camera.formats.contains(
        where: {
          $0.id == existingID
        }
      )
    {
      return
    }

    selectedConfigurationIDs[
      camera.id
    ] =
      preferredConfiguration(
        for: camera
      )?.id
  }

  private func ensureAudioSelection(
    for camera: CameraDeviceInfo
  ) {
    if let existingID =
      selectedAudioDeviceIDs[
        camera.id
      ],
      audioDevices.contains(
        where: {
          $0.id == existingID
        }
      )
    {
      return
    }

    guard audioAuthorizationStatus == .authorized else {
      selectedAudioDeviceIDs[
        camera.id
      ] =
        AudioDeviceInfo.noAudioID

      return
    }

    selectedAudioDeviceIDs[
      camera.id
    ] =
      AudioDeviceInfo.preferredDeviceID(
        for: camera,
        from: audioDevices
      )
  }

  private func ensureRecordingFormatSelection(
    for cameraID: String
  ) {
    guard
      selectedRecordingFormats[
        cameraID
      ] == nil
    else {
      return
    }

    selectedRecordingFormats[
      cameraID
    ] =
      defaultRecordingFileFormat
  }

  private func ensureMonoAudioSelection(
    for cameraID: String
  ) {
    guard
      selectedMonoAudioStates[
        cameraID
      ] == nil
    else {
      return
    }

    selectedMonoAudioStates[
      cameraID
    ] = false
  }

  private func applyDefaultAudioSelections() {
    for camera in selectedCameras {
      let existingID =
        selectedAudioDeviceIDs[
          camera.id
        ]

      if existingID == nil
        || existingID
          == AudioDeviceInfo.noAudioID
      {
        selectedAudioDeviceIDs[
          camera.id
        ] =
          AudioDeviceInfo.preferredDeviceID(
            for: camera,
            from: audioDevices
          )
      }
    }
  }

  private func reconfigureSelectedCameras() {
    for cameraID in selectedCameraIDs {
      configureCamera(cameraID)
    }
  }

  private func preferredConfiguration(
    for camera: CameraDeviceInfo
  ) -> VideoFormat? {
    camera.formats.first {
      $0.width == 1920
        && $0.height == 1080
        && abs(
          $0.frameRate - 30
        ) < 0.1
    }
      ?? camera.formats.first {
        $0.width == 1280
          && $0.height == 720
          && abs(
            $0.frameRate - 30
          ) < 0.1
      }
      ?? camera.formats.first
  }

  private func scheduleControllerRemoval(
    cameraID: String
  ) {
    guard
      let controller =
        controllers[cameraID]
    else {
      removeSelections(
        for: cameraID
      )

      return
    }

    let token = UUID()

    controllerTeardownTokens[
      cameraID
    ] = token

    DispatchQueue.main.asyncAfter(
      deadline: .now() + 0.4
    ) { [weak self, weak controller] in
      guard
        let self,
        let controller,
        self.controllerTeardownTokens[
          cameraID
        ] == token,
        !self.selectedCameraIDs.contains(
          cameraID
        )
      else {
        return
      }

      controller.clear { [weak self, weak controller] in
        guard
          let self,
          let controller,
          self.controllerTeardownTokens[
            cameraID
          ] == token,
          !self.selectedCameraIDs.contains(
            cameraID
          )
        else {
          return
        }

        if self.controllers[
          cameraID
        ] === controller {
          self.controllers[
            cameraID
          ] = nil
        }

        self.removeSelections(
          for: cameraID
        )

        self.controllerTeardownTokens[
          cameraID
        ] = nil
      }
    }
  }

  private func cancelScheduledControllerRemoval(
    cameraID: String
  ) {
    controllerTeardownTokens[
      cameraID
    ] = nil
  }

  private func removeUnavailableControllers(
    availableIDs: Set<String>
  ) {
    let unavailableIDs =
      Set(controllers.keys)
      .subtracting(availableIDs)

    for cameraID in unavailableIDs {
      controllerTeardownTokens[
        cameraID
      ] = nil

      let controller =
        controllers[cameraID]

      controllers[cameraID] =
        nil

      removeSelections(
        for: cameraID
      )

      controller?.clear()
    }
  }

  private func removeSelections(
    for cameraID: String
  ) {
    selectedConfigurationIDs[
      cameraID
    ] = nil

    selectedAudioDeviceIDs[
      cameraID
    ] = nil

    selectedRecordingFormats[
      cameraID
    ] = nil

    selectedMonoAudioStates[
      cameraID
    ] = nil
  }

  private func stopAndRemoveAllControllers() {
    controllerTeardownTokens = [:]

    let existingControllers =
      Array(controllers.values)

    controllers = [:]

    for controller in existingControllers {
      controller.clear()
    }
  }
}
