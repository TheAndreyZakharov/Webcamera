import Combine
import CoreMedia
import CoreVideo
import Foundation

@MainActor
final class AndroidCameraController:
  ObservableObject
{
  struct CameraOption:
    Identifiable,
    Hashable
  {
    let id: String
    let name: String
    let facing: String
    let flashAvailable: Bool
    let torchAvailable: Bool

    var displayName: String {
      switch facing {
      case "rear":
        return "Rear Camera"

      case "front":
        return "Front Camera"

      default:
        return name
      }
    }
  }

  static let controlPort:
    UInt16 = 27283

  static let videoPort:
    UInt16 = 27284

  let device:
    ADBController.Device

  @Published private(set)
    var isConnected = false

  @Published private(set)
    var isRunning = false

  @Published private(set)
    var latestPixelBuffer:
      CVPixelBuffer?

  @Published private(set)
    var latestPresentationTime:
      CMTime = .zero

  @Published private(set)
    var errorMessage:
      String?

  @Published private(set)
    var statusMessage =
      "Disconnected"

  @Published private(set)
    var torchEnabled = false

  @Published private(set)
    var cameraOptions:
      [CameraOption] = []

  @Published private(set)
    var selectedCameraID:
      String?

  @Published private(set)
    var phoneAudioAvailable = false

  @Published private(set)
    var receivedAudioPacketCount:
      UInt64 = 0

  @Published private(set)
    var isRecording = false

  @Published private(set)
    var lastRecordingURL:
      URL?

  var selectedCamera:
    CameraOption?
  {
    guard let selectedCameraID else {
      return nil
    }

    return cameraOptions.first {
      $0.id == selectedCameraID
    }
  }

  var torchAvailable: Bool {
    guard let selectedCamera else {
      return false
    }

    return selectedCamera.torchAvailable
      || selectedCamera.flashAvailable
      || selectedCamera.facing == "rear"
  }

  private let adbController:
    ADBController

  private let controlConnection =
    ControlConnection()

  private let videoConnection =
    VideoConnection()

  private let decoder =
    H264Decoder()

  private let recorder =
    AndroidRecorder()

  private var latestAudioConfiguration:
    Data?

  private var requestedWidth = 1280
  private var requestedHeight = 720
  private var requestedFrameRate = 30

  private var pendingStart = false
  private var pendingStartAfterConfigure = false
  private var controlReady = false
  private var videoReady = false
  private var capabilitiesReceived = false

  init(
    device: ADBController.Device,
    adbController:
      ADBController =
        ADBController()
  ) {
    self.device = device
    self.adbController =
      adbController

    configureCallbacks()
    configureRecorderCallbacks()
  }

  func connect() {
    guard !isConnected,
      !controlReady
    else {
      return
    }

    errorMessage = nil

    statusMessage =
      "Preparing ADB connection"

    Task {
      do {
        try await adbController
          .startAndroidApplication(
            deviceID: device.id
          )

        try? await adbController
          .startAndroidService(
            deviceID: device.id
          )

        try await Task.sleep(
          for: .milliseconds(700)
        )

        try await adbController
          .forward(
            deviceID: device.id,
            localPort:
              Self.controlPort,
            remotePort:
              Self.controlPort
          )

        try await adbController
          .forward(
            deviceID: device.id,
            localPort:
              Self.videoPort,
            remotePort:
              Self.videoPort
          )

        controlConnection.connect(
          host: "127.0.0.1",
          port:
            Self.controlPort
        )

        videoConnection.connect(
          host: "127.0.0.1",
          port:
            Self.videoPort
        )
      } catch {
        errorMessage =
          error.localizedDescription

        statusMessage =
          "Connection failed"
      }
    }
  }

  func start() {
    pendingStart = true
    errorMessage = nil

    if !controlReady
      || !videoReady
    {
      connect()
      return
    }

    beginStartIfPossible()
  }

  func stop() {
    if isRecording {
      recorder.stopRecording()
    }
    pendingStart = false
    pendingStartAfterConfigure = false

    controlConnection.send(
      type: "stop"
    )

    isRunning = false
    torchEnabled = false

    statusMessage =
      "Stopping Android camera"
  }

  func disconnect() {
    if isRecording {
      recorder.cancelRecording()
    }
    pendingStart = false
    pendingStartAfterConfigure = false

    controlReady = false
    videoReady = false
    capabilitiesReceived = false

    controlConnection.disconnect()
    videoConnection.disconnect()
    decoder.reset()

    latestPixelBuffer = nil
    isRunning = false
    isConnected = false
    torchEnabled = false

    statusMessage =
      "Disconnected"

    Task {
      await adbController
        .removeForward(
          deviceID: device.id,
          localPort:
            Self.controlPort
        )

      await adbController
        .removeForward(
          deviceID: device.id,
          localPort:
            Self.videoPort
        )
    }
  }

  func selectCamera(
    _ cameraID: String
  ) {
    guard cameraOptions.contains(
      where: {
        $0.id == cameraID
      }
    ) else {
      return
    }

    guard selectedCameraID
      != cameraID
    else {
      return
    }

    selectedCameraID =
      cameraID

    torchEnabled = false
    errorMessage = nil

    let restartAfterChange =
      isRunning
      || pendingStart

    if isRunning {
      controlConnection.send(
        type: "stop"
      )

      isRunning = false

      statusMessage =
        "Switching Android camera"

      Task {
        try? await Task.sleep(
          for: .milliseconds(350)
        )

        self.sendConfiguration(
          startAfter:
            restartAfterChange
        )
      }
    } else {
      sendConfiguration(
        startAfter:
          restartAfterChange
      )
    }
  }

  func setTorchEnabled(
    _ enabled: Bool
  ) {
    guard torchAvailable else {
      errorMessage =
        "Torch is unavailable for the selected camera."

      return
    }

    controlConnection.send(
      type: "setFlashMode",
      values: [
        "flashMode":
          enabled
          ? "torch"
          : "off",
      ]
    )
  }

  func toggleTorch() {
    setTorchEnabled(
      !torchEnabled
    )
  }

  func requestKeyFrame() {
    controlConnection.send(
      type: "requestKeyFrame"
    )
  }

  func selectVideoFormat(
    _ format: VideoFormat?
  ) {
    guard let format else {
      return
    }

    guard
      !isRecording
    else {
      errorMessage =
        "Stop recording before changing the Android video format."

      return
    }

    requestedWidth =
      format.width

    requestedHeight =
      format.height

    requestedFrameRate =
      max(
        1,
        Int(
          format.frameRate.rounded()
        )
      )

    let shouldRestart =
      isRunning
      || pendingStart

    if isRunning {
      controlConnection.send(
        type: "stop"
      )

      isRunning = false

      Task {
        try? await Task.sleep(
          for: .milliseconds(350)
        )

        self.sendConfiguration(
          startAfter:
            shouldRestart
        )
      }
    } else {
      sendConfiguration(
        startAfter:
          shouldRestart
      )
    }
  }

  func startRecording(
    folderURL: URL,
    cameraName: String,
    format: RecordingFileFormat,
    audioDevice: AudioDeviceInfo,
    monoAudio: Bool
  ) {
    guard isRunning else {
      errorMessage =
        "Start the Android camera before recording."

      return
    }

    guard !isRecording else {
      return
    }

    if audioDevice.isPhoneAudio,
      latestAudioConfiguration == nil
    {
      errorMessage =
        "Phone microphone is not ready yet. Wait until Android audio packets arrive."

      return
    }

    if let latestAudioConfiguration {
      recorder.setPhoneAudioConfiguration(
        latestAudioConfiguration
      )
    }

    recorder.startRecording(
      folderURL: folderURL,
      cameraName: cameraName,
      format: format,
      width: requestedWidth,
      height: requestedHeight,
      audioDevice: audioDevice,
      monoAudio: monoAudio
    )
  }

  func stopRecording() {
    recorder.stopRecording()
  }

  private func beginStartIfPossible() {
    guard pendingStart else {
      return
    }

    guard controlReady,
      videoReady
    else {
      return
    }

    guard capabilitiesReceived,
      selectedCameraID != nil
    else {
      controlConnection.send(
        type: "getCapabilities"
      )

      return
    }

    if isRunning {
      pendingStart = false

      statusMessage =
        "Streaming Android camera"

      return
    }

    sendConfiguration(
      startAfter: true
    )
  }

  private func sendConfiguration(
    startAfter: Bool
  ) {
    guard controlReady,
      let selectedCameraID
    else {
      pendingStart =
        startAfter

      return
    }

    pendingStartAfterConfigure =
      startAfter

    statusMessage =
      "Configuring Android camera"

    controlConnection.send(
      type: "configure",
      values: [
        "cameraId":
          selectedCameraID,
        "width":
          requestedWidth,
        "height":
          requestedHeight,
        "frameRate":
          requestedFrameRate,
        "bitRate":
          4_000_000,
        "audioEnabled":
          true,
        "audioBitRate":
          128_000,
        "flashMode":
          "off",
        "zoom":
          1.0,
      ]
    )
  }

  private func sendStartCommand() {
    guard controlReady,
      videoReady
    else {
      pendingStart = true
      return
    }

    errorMessage = nil

    statusMessage =
      "Starting Android stream"

    controlConnection.send(
      type: "start"
    )

    pendingStart = false
  }

  private func configureCallbacks() {
    controlConnection
      .onStateChange = {
        [weak self]
        newState in

        Task { @MainActor in
          guard let self else {
            return
          }

          switch newState {
          case .disconnected:
            self.controlReady = false
            self.isConnected = false

          case .connecting:
            self.statusMessage =
              "Connecting control channel"

          case .connected:
            self.controlReady = true

            self.isConnected =
              self.videoReady

            self.statusMessage =
              "Android control connected"

            self.controlConnection.send(
              type: "getCapabilities"
            )

            self.controlConnection.send(
              type: "getStatus"
            )

          case let .failed(message):
            self.controlReady = false
            self.isConnected = false

            self.errorMessage =
              message

            self.statusMessage =
              "Control connection failed"
          }
        }
      }

    controlConnection.onMessage = {
      [weak self]
      message in

      Task { @MainActor in
        self?.handleControlMessage(
          message
        )
      }
    }

    videoConnection
      .onStateChange = {
        [weak self]
        newState in

        Task { @MainActor in
          guard let self else {
            return
          }

          switch newState {
          case .disconnected:
            self.videoReady = false

            self.isConnected =
              false

          case .connecting:
            self.statusMessage =
              "Connecting video channel"

          case .connected:
            self.videoReady = true

            self.isConnected =
              self.controlReady

            self.statusMessage =
              "Android video connected"

            self.beginStartIfPossible()

          case let .failed(message):
            self.videoReady = false
            self.isConnected = false

            self.errorMessage =
              message

            self.statusMessage =
              "Video connection failed"
          }
        }
      }

    videoConnection.onPacket = {
      [weak self]
      packet in

      Task { @MainActor in
        self?.handleVideoPacket(
          packet
        )
      }
    }

    decoder.onFrame = {
      [weak self]
      pixelBuffer,
      presentationTime in

      guard let self else {
        return
      }

      self.latestPixelBuffer =
        pixelBuffer

      self.latestPresentationTime =
        presentationTime

      self.recorder.appendVideoFrame(
        pixelBuffer:
          pixelBuffer,
        presentationTime:
          presentationTime
      )

      self.isRunning = true
      self.pendingStart = false

      self.statusMessage =
        "Streaming Android camera"
    }

    decoder.onError = {
      [weak self]
      error in

      self?.errorMessage =
        error.localizedDescription
    }
  }

  private func handleControlMessage(
    _ message:
      [String: Any]
  ) {
    let type =
      message["type"]
        as? String
      ?? ""

    switch type {
    case "hello":
      statusMessage =
        "Connected to \(device.displayName)"

    case "capabilities":
      handleCapabilities(
        message
      )

      beginStartIfPossible()

    case "configured":
      statusMessage =
        "Android camera configured"

      if pendingStartAfterConfigure {
        pendingStartAfterConfigure =
          false

        sendStartCommand()
      }

    case "status":
      let state =
        message["state"]
          as? String
        ?? ""

      let streaming =
        state == "streaming"
        || (
          message["streaming"]
            as? Bool
          ?? false
        )

      isRunning =
        streaming

      if let enabled =
        message["torchEnabled"]
          as? Bool
      {
        torchEnabled = enabled
      }

      if streaming {
        pendingStart = false

        statusMessage =
          "Streaming Android camera"
      } else if !state.isEmpty {
        statusMessage =
          "Android: \(state)"
      }

      if let text =
        message["message"]
          as? String,
        !text.isEmpty
      {
        errorMessage = text
      }

      if pendingStart,
        !streaming
      {
        beginStartIfPossible()
      }

    case "flashStatus":
      let available =
        message["available"]
          as? Bool
        ?? false

      torchEnabled =
        (
          message["appliedMode"]
            as? String
        ) == "torch"

      if !available {
        errorMessage =
          message["message"]
            as? String
          ?? "The phone rejected the torch command."
      } else {
        errorMessage = nil
      }

    case "error":
      let code =
        message["code"]
          as? String
        ?? ""

      let text =
        message["message"]
          as? String
        ?? "Android camera error"

      /*
       Если приложение телефона уже стримит, configure может вернуть
       invalid_state. В этом случае поток всё равно можно показывать.
       */
      if code == "invalid_state",
        isRunning
      {
        pendingStart = false
        pendingStartAfterConfigure = false

        statusMessage =
          "Streaming Android camera"
      } else {
        errorMessage = text
        statusMessage =
          "Android camera error"
      }

    default:
      break
    }
  }

  private func handleCapabilities(
    _ message:
      [String: Any]
  ) {
    guard
      let rawCameras =
        message["cameras"]
          as? [[String: Any]]
    else {
      errorMessage =
        "Android did not return its camera list."

      return
    }

    let options =
      rawCameras.compactMap {
        value -> CameraOption? in

        guard
          let id =
            value["id"]
              as? String
        else {
          return nil
        }

        let facing =
          value["facing"]
            as? String
          ?? "unknown"

        let fallbackName =
          facing == "front"
          ? "Front Camera"
          : facing == "rear"
            ? "Rear Camera"
            : "Camera \(id)"

        return CameraOption(
          id: id,
          name:
            value["name"]
              as? String
            ?? fallbackName,
          facing: facing,
          flashAvailable:
            value["flashAvailable"]
              as? Bool
            ?? false,
          torchAvailable:
            value["torchAvailable"]
              as? Bool
            ?? false
        )
      }

    cameraOptions =
      options.sorted {
        cameraSortOrder($0)
          < cameraSortOrder($1)
      }

    capabilitiesReceived = true

    if let selectedCameraID,
      cameraOptions.contains(
        where: {
          $0.id == selectedCameraID
        }
      )
    {
      return
    }

    selectedCameraID =
      cameraOptions.first(
        where: {
          $0.facing == "rear"
        }
      )?.id
      ?? cameraOptions.first?.id
  }

  private func cameraSortOrder(
    _ camera:
      CameraOption
  ) -> Int {
    switch camera.facing {
    case "rear":
      return 0

    case "front":
      return 1

    default:
      return 2
    }
  }

  private func configureRecorderCallbacks() {
    recorder.onRecordingStateChange = {
      [weak self]
      isRecording,
      lastRecordingURL,
      errorMessage in

      guard let self else {
        return
      }

      self.isRecording =
        isRecording

      if let lastRecordingURL {
        self.lastRecordingURL =
          lastRecordingURL
      }

      if let errorMessage {
        self.errorMessage =
          errorMessage
      } else if isRecording {
        self.errorMessage = nil
      }

      self.objectWillChange.send()
    }
  }

  private func handleVideoPacket(
    _ packet:
      VideoConnection.Packet
  ) {
    switch packet.type {
    case .videoConfiguration:
      decoder.configure(
        annexBData:
          packet.payload
      )

    case .videoFrame:
      decoder.decode(
        annexBData:
          packet.payload,
        presentationTime:
          packet
          .presentationTimestamp,
        decodeTime:
          packet.decodeTimestamp,
        isKeyFrame:
          packet.isKeyFrame
      )

    case .audioConfiguration:
      phoneAudioAvailable = true

      latestAudioConfiguration =
        packet.payload

      recorder.setPhoneAudioConfiguration(
        packet.payload
      )

      receivedAudioPacketCount += 1

      print(
        "Android AAC configuration:",
        packet.payload.count,
        "bytes"
      )

    case .audioFrame:
      phoneAudioAvailable = true

      receivedAudioPacketCount += 1

      recorder.appendPhoneAudioFrame(
        data:
          packet.payload,
        presentationTime:
          packet.presentationTimestamp
      )

      if receivedAudioPacketCount % 100 == 0 {
        print(
          "Android AAC packets:",
          receivedAudioPacketCount,
          "last size:",
          packet.payload.count
        )
      }

    case .endOfStream:
      isRunning = false
      torchEnabled = false

      statusMessage =
        "Android stream stopped"
    }
  }
}
