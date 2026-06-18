import AVFoundation
import AudioToolbox
import Combine
import CoreMedia
import Foundation

enum RecordingFileFormat:
  String,
  CaseIterable,
  Identifiable
{
  case mov
  case mp4

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .mov:
      return "QuickTime Movie (.mov)"

    case .mp4:
      return "MPEG-4 Video (.mp4)"
    }
  }

  var shortTitle: String {
    rawValue.uppercased()
  }

  var fileExtension: String {
    rawValue
  }
}

final class CameraController:
  NSObject,
  ObservableObject,
  AVCaptureFileOutputRecordingDelegate,
  AVCaptureAudioDataOutputSampleBufferDelegate
{
  enum CameraError: LocalizedError {
    case missingDevice
    case missingFormat
    case cannotCreateVideoInput
    case cannotCreateAudioInput
    case cannotAddVideoInput
    case cannotAddAudioInput
    case microphonePermissionDenied
    case recordingUnavailable
    case cameraNotRunning
    case mp4ExportUnavailable
    case configurationFailed(String)

    var errorDescription: String? {
      switch self {
      case .missingDevice:
        return
          "The selected camera is unavailable."

      case .missingFormat:
        return
          "The selected camera configuration is no longer available."

      case .cannotCreateVideoInput:
        return
          "The camera input could not be created."

      case .cannotCreateAudioInput:
        return
          "The selected microphone input could not be created."

      case .cannotAddVideoInput:
        return
          "The camera input cannot be added to the capture session."

      case .cannotAddAudioInput:
        return
          "The selected microphone cannot be added to this camera session."

      case .microphonePermissionDenied:
        return
          "Microphone access is denied. Select No Audio or enable microphone access in System Settings."

      case .recordingUnavailable:
        return
          "Recording is not supported by this camera."

      case .cameraNotRunning:
        return
          "Start the camera before recording."

      case .mp4ExportUnavailable:
        return
          "The recording was captured, but this video cannot be exported as MP4."

      case .configurationFailed(
        let message
      ):
        return message
      }
    }
  }

  let cameraID: String
  let cameraName: String
  let session = AVCaptureSession()

  @Published private(set)
    var isConfigured = false

  @Published private(set)
    var isRunning = false

  @Published private(set)
    var isRecording = false

  @Published private(set)
    var canRecord = false

  @Published private(set)
    var hasAudioInput = false

  @Published private(set)
    var activeAudioDeviceName: String?

  @Published private(set)
    var isAudioMonitoring = false

  @Published private(set)
    var isMonoAudioEnabled = false

  @Published private(set)
    var leftAudioLevel: Double = 0

  @Published private(set)
    var rightAudioLevel: Double = 0

  @Published private(set)
    var errorMessage: String?

  @Published private(set)
    var lastRecordingURL: URL?

  var onStateChange: (() -> Void)?

  private let sessionQueue: DispatchQueue

  private let audioProcessingQueue: DispatchQueue

  private let movieOutput =
    AVCaptureMovieFileOutput()

  private let audioDataOutput =
    AVCaptureAudioDataOutput()

  private let audioEngine =
    AVAudioEngine()

  private let audioPlayerNode =
    AVAudioPlayerNode()

  private var currentVideoInput: AVCaptureDeviceInput?

  private var currentAudioInput: AVCaptureDeviceInput?

  private var audioMonitoringRequested =
    false

  private var monoAudioRequested =
    false

  private var monitorFormat: AVAudioFormat?

  private var pendingStopAfterRecording =
    false

  private var pendingRemovalAfterRecording =
    false

  private var pendingClearCompletion: (() -> Void)?

  private var currentRecordingFormat: RecordingFileFormat = .mov

  private var currentFinalRecordingURL: URL?

  init(
    cameraID: String,
    cameraName: String
  ) {
    self.cameraID = cameraID
    self.cameraName = cameraName

    sessionQueue = DispatchQueue(
      label:
        "com.theandreyzakharov.webcamera.capture.\(cameraID)",
      qos: .userInitiated
    )

    audioProcessingQueue =
      DispatchQueue(
        label:
          "com.theandreyzakharov.webcamera.audio-monitor.\(cameraID)",
        qos: .userInteractive
      )

    super.init()

    audioEngine.attach(
      audioPlayerNode
    )

    audioDataOutput
      .setSampleBufferDelegate(
        self,
        queue: audioProcessingQueue
      )
  }

  deinit {
    audioDataOutput
      .setSampleBufferDelegate(
        nil,
        queue: nil
      )

    audioPlayerNode.stop()
    audioEngine.stop()
  }

  func configure(
    camera: CameraDeviceInfo,
    configuration: VideoFormat?,
    audioDevice: AudioDeviceInfo?,
    monoAudio: Bool
  ) {
    guard
      let videoDevice =
        camera.device
    else {
      publishError(
        CameraError.missingDevice
      )

      return
    }

    sessionQueue.async { [weak self] in
      guard let self else {
        return
      }

      guard
        !self.movieOutput.isRecording,
        !self.isRecording
      else {
        self.publishError(
          CameraError.configurationFailed(
            "Stop recording before changing the camera or microphone configuration."
          )
        )

        return
      }

      self.pendingStopAfterRecording =
        false

      self.pendingRemovalAfterRecording =
        false

      self.pendingClearCompletion =
        nil

      self.monoAudioRequested =
        monoAudio

      self.resetMonitoringGraph()

      do {
        let state =
          try CaptureSessionGate.shared
          .withLock(
            for: self.session
          ) {
            try self.configureSession(
              videoDevice: videoDevice,
              configuration:
                configuration,
              audioDevice:
                audioDevice,
              monoAudio:
                monoAudio
            )

            if !self.session.isRunning {
              self.session.startRunning()
            }

            return (
              running:
                self.session.isRunning,
              hasAudio:
                self.currentAudioInput
                != nil,
              audioName:
                self.currentAudioInput?
                .device.localizedName
            )
          }

        if !state.hasAudio {
          self.audioMonitoringRequested =
            false
        }

        self.publishState {
          self.isConfigured = true

          self.isRunning =
            state.running

          self.isRecording = false

          self.hasAudioInput =
            state.hasAudio

          self.activeAudioDeviceName =
            state.audioName

          self.isMonoAudioEnabled =
            monoAudio

          self.isAudioMonitoring =
            state.running
            && state.hasAudio
            && self.audioMonitoringRequested

          if !state.hasAudio {
            self.leftAudioLevel = 0
            self.rightAudioLevel = 0
          }

          self.errorMessage =
            state.running
            ? nil
            : "The camera capture session did not start."
        }
      } catch {
        self.audioMonitoringRequested =
          false

        self.resetMonitoringGraph()

        self.publishState {
          self.isConfigured = false
          self.isRunning = false
          self.isRecording = false
          self.hasAudioInput = false

          self.activeAudioDeviceName =
            nil

          self.isAudioMonitoring =
            false

          self.leftAudioLevel = 0
          self.rightAudioLevel = 0

          self.errorMessage =
            error.localizedDescription
        }
      }
    }
  }

  func start() {
    sessionQueue.async { [weak self] in
      guard let self else {
        return
      }

      self.pendingStopAfterRecording =
        false

      self.pendingRemovalAfterRecording =
        false

      self.pendingClearCompletion =
        nil

      let result:
        (
          valid: Bool,
          running: Bool
        ) =
          CaptureSessionGate.shared
          .withLock(
            for: self.session
          ) {
            guard
              self.isConfigured,
              !self.session.inputs.isEmpty
            else {
              return (
                false,
                false
              )
            }

            if !self.session.isRunning {
              self.session.startRunning()
            }

            return (
              true,
              self.session.isRunning
            )
          }

      guard result.valid else {
        self.publishError(
          CameraError.configurationFailed(
            "Configure the camera before starting it."
          )
        )

        return
      }

      self.publishState {
        self.isRunning =
          result.running

        self.isAudioMonitoring =
          result.running
          && self.hasAudioInput
          && self.audioMonitoringRequested

        self.errorMessage =
          result.running
          ? nil
          : "The camera capture session did not start."
      }
    }
  }

  func stop() {
    sessionQueue.async { [weak self] in
      guard let self else {
        return
      }

      if self.movieOutput.isRecording {
        self.pendingStopAfterRecording =
          true

        self.pendingRemovalAfterRecording =
          false

        self.movieOutput.stopRecording()

        return
      }

      if self.isRecording {
        self.pendingStopAfterRecording =
          true

        self.pendingRemovalAfterRecording =
          false

        return
      }

      self.stopSessionNow()
    }
  }

  func clear(
    completion: (() -> Void)? = nil
  ) {
    sessionQueue.async { [weak self] in
      guard let self else {
        DispatchQueue.main.async {
          completion?()
        }

        return
      }

      self.audioMonitoringRequested =
        false

      self.resetMonitoringGraph()

      if self.movieOutput.isRecording {
        self.pendingStopAfterRecording =
          false

        self.pendingRemovalAfterRecording =
          true

        self.pendingClearCompletion =
          completion

        self.movieOutput.stopRecording()

        return
      }

      if self.isRecording {
        self.pendingStopAfterRecording =
          false

        self.pendingRemovalAfterRecording =
          true

        self.pendingClearCompletion =
          completion

        return
      }

      self.removeSessionConfiguration(
        completion: completion
      )
    }
  }

  func setAudioMonitoringEnabled(
    _ enabled: Bool
  ) {
    sessionQueue.async { [weak self] in
      guard let self else {
        return
      }

      let shouldEnable =
        enabled
        && self.currentAudioInput
          != nil
        && self.session.isRunning

      self.audioMonitoringRequested =
        shouldEnable

      if !shouldEnable {
        self.resetMonitoringGraph()
      }

      self.publishState {
        self.isAudioMonitoring =
          shouldEnable

        if !shouldEnable {
          self.leftAudioLevel = 0
          self.rightAudioLevel = 0
        }
      }
    }
  }

  func setMonoAudioEnabled(
    _ enabled: Bool
  ) {
    sessionQueue.async { [weak self] in
      guard let self else {
        return
      }

      guard
        !self.movieOutput.isRecording,
        !self.isRecording
      else {
        self.publishError(
          CameraError.configurationFailed(
            "Stop recording before changing the mono audio setting."
          )
        )

        return
      }

      self.monoAudioRequested =
        enabled

      /*
       The live-monitor graph must be rebuilt because its input
       format changes between stereo and one-channel mono.
       */
      self.resetMonitoringGraph()

      CaptureSessionGate.shared
        .withLock(
          for: self.session
        ) {
          self.applyAudioRecordingSettings(
            monoAudio: enabled
          )
        }

      self.publishState {
        self.isMonoAudioEnabled =
          enabled
      }
    }
  }

  func startRecording(
    folderURL: URL,
    format: RecordingFileFormat
  ) {
    sessionQueue.async { [weak self] in
      guard let self else {
        return
      }

      guard self.session.isRunning else {
        self.publishError(
          CameraError.cameraNotRunning
        )

        return
      }

      guard
        self.canRecord,
        self.session.outputs.contains(
          where: {
            $0 === self.movieOutput
          }
        )
      else {
        self.publishError(
          CameraError.recordingUnavailable
        )

        return
      }

      guard
        !self.movieOutput.isRecording,
        !self.isRecording
      else {
        return
      }

      do {
        try FileManager.default
          .createDirectory(
            at: folderURL,
            withIntermediateDirectories:
              true
          )

        let finalURL =
          self.makeRecordingURL(
            folderURL: folderURL,
            fileExtension:
              format.fileExtension
          )

        let captureURL: URL

        switch format {
        case .mov:
          captureURL = finalURL

        case .mp4:
          captureURL =
            folderURL
            .appendingPathComponent(
              ".webcamera-\(UUID().uuidString)"
            )
            .appendingPathExtension(
              "mov"
            )
        }

        try self.removeFileIfNeeded(
          at: captureURL
        )

        try self.removeFileIfNeeded(
          at: finalURL
        )

        self.pendingStopAfterRecording =
          false

        self.pendingRemovalAfterRecording =
          false

        self.pendingClearCompletion =
          nil

        self.currentRecordingFormat =
          format

        self.currentFinalRecordingURL =
          finalURL

        self.applyAudioRecordingSettings(
          monoAudio:
            self.monoAudioRequested
        )

        self.movieOutput.startRecording(
          to: captureURL,
          recordingDelegate: self
        )
      } catch {
        self.publishError(error)
      }
    }
  }

  func stopRecording() {
    sessionQueue.async { [weak self] in
      guard let self else {
        return
      }

      self.pendingStopAfterRecording =
        false

      self.pendingRemovalAfterRecording =
        false

      self.pendingClearCompletion =
        nil

      if self.movieOutput.isRecording {
        self.movieOutput.stopRecording()
      }
    }
  }

  private func configureSession(
    videoDevice: AVCaptureDevice,
    configuration: VideoFormat?,
    audioDevice: AudioDeviceInfo?,
    monoAudio: Bool
  ) throws {
    let videoInput: AVCaptureDeviceInput

    do {
      videoInput =
        try AVCaptureDeviceInput(
          device: videoDevice
        )
    } catch {
      throw
        CameraError
        .cannotCreateVideoInput
    }

    var audioInput: AVCaptureDeviceInput?

    if let audioDevice,
      !audioDevice.isNoAudio,
      let device = audioDevice.device
    {
      guard
        AVCaptureDevice.authorizationStatus(
          for: .audio
        ) == .authorized
      else {
        throw
          CameraError
          .microphonePermissionDenied
      }

      do {
        audioInput =
          try AVCaptureDeviceInput(
            device: device
          )
      } catch {
        throw
          CameraError
          .cannotCreateAudioInput
      }
    }

    session.beginConfiguration()

    defer {
      session.commitConfiguration()
    }

    for existingInput in session.inputs {
      session.removeInput(
        existingInput
      )
    }

    for existingOutput in session.outputs {
      session.removeOutput(
        existingOutput
      )
    }

    currentVideoInput = nil
    currentAudioInput = nil

    guard
      session.canAddInput(
        videoInput
      )
    else {
      throw
        CameraError
        .cannotAddVideoInput
    }

    session.addInput(
      videoInput
    )

    currentVideoInput =
      videoInput

    if let audioInput {
      guard
        session.canAddInput(
          audioInput
        )
      else {
        throw
          CameraError
          .cannotAddAudioInput
      }

      session.addInput(
        audioInput
      )

      currentAudioInput =
        audioInput
    }

    if let configuration {
      try applyConfiguration(
        configuration,
        to: videoDevice
      )
    }

    let recordingSupported =
      session.canAddOutput(
        movieOutput
      )

    if recordingSupported {
      session.addOutput(
        movieOutput
      )
    }

    if currentAudioInput != nil,
      session.canAddOutput(
        audioDataOutput
      )
    {
      session.addOutput(
        audioDataOutput
      )
    }

    if recordingSupported {
      applyAudioRecordingSettings(
        monoAudio: monoAudio
      )
    }

    publishState {
      self.canRecord =
        recordingSupported
    }
  }

  private func applyAudioRecordingSettings(
    monoAudio: Bool
  ) {
    guard
      let audioConnection =
        movieOutput.connection(
          with: .audio
        )
    else {
      return
    }

    let sourceChannelCount =
      audioConnection
      .audioChannels
      .count

    let channelCount =
      monoAudio
      ? 1
      : max(
        1,
        min(
          2,
          sourceChannelCount
        )
      )

    let settings: [String: Any] = [
      AVFormatIDKey:
        kAudioFormatMPEG4AAC,
      AVNumberOfChannelsKey:
        channelCount,
      AVSampleRateKey:
        48_000,
      AVEncoderBitRateKey:
        monoAudio
        ? 96_000
        : 160_000,
    ]

    movieOutput.setOutputSettings(
      settings,
      for: audioConnection
    )
  }

  private func applyConfiguration(
    _ configuration: VideoFormat,
    to device: AVCaptureDevice
  ) throws {
    guard
      let resolvedFormat =
        VideoFormat.resolveDeviceFormat(
          configuration,
          for: device
        )
    else {
      throw
        CameraError.missingFormat
    }

    do {
      try device.lockForConfiguration()

      defer {
        device.unlockForConfiguration()
      }

      device.activeFormat =
        resolvedFormat
    } catch {
      throw
        CameraError.configurationFailed(
          "The camera format could not be applied: \(error.localizedDescription)"
        )
    }
  }

  private func resetMonitoringGraph() {
    audioProcessingQueue.async { [weak self] in
      guard let self else {
        return
      }

      self.audioPlayerNode.stop()

      if self.audioEngine.isRunning {
        self.audioEngine.stop()
      }

      self.audioEngine
        .disconnectNodeOutput(
          self.audioPlayerNode
        )

      self.monitorFormat = nil
    }
  }

  private func processAudioSampleBuffer(
    _ sampleBuffer: CMSampleBuffer
  ) {
    guard
      audioMonitoringRequested,
      session.isRunning
    else {
      return
    }

    guard
      let sourceBuffer =
        makePCMBuffer(
          from: sampleBuffer
        )
    else {
      return
    }

    let sourceFormat =
      sourceBuffer.format

    let requestedChannels: AVAudioChannelCount

    if monoAudioRequested {
      requestedChannels = 1
    } else {
      requestedChannels =
        max(
          1,
          min(
            2,
            sourceFormat.channelCount
          )
        )
    }

    guard
      let playbackFormat =
        AVAudioFormat(
          commonFormat: .pcmFormatFloat32,
          sampleRate:
            sourceFormat.sampleRate,
          channels:
            requestedChannels,
          interleaved: false
        )
    else {
      return
    }

    guard
      let playbackBuffer =
        convertAudioBuffer(
          sourceBuffer,
          to: playbackFormat
        )
    else {
      return
    }

    updateMeters(
      from: playbackBuffer,
      monoAudio:
        monoAudioRequested
    )

    do {
      try prepareMonitoringGraph(
        format: playbackFormat
      )

      audioPlayerNode.scheduleBuffer(
        playbackBuffer,
        completionHandler: nil
      )

      if !audioPlayerNode.isPlaying {
        audioPlayerNode.play()
      }
    } catch {
      audioMonitoringRequested =
        false

      resetMonitoringGraph()

      publishError(error)
    }
  }

  private func prepareMonitoringGraph(
    format: AVAudioFormat
  ) throws {
    if let monitorFormat,
      formatsMatch(
        monitorFormat,
        format
      ),
      audioEngine.isRunning
    {
      return
    }

    audioPlayerNode.stop()

    if audioEngine.isRunning {
      audioEngine.stop()
    }

    audioEngine
      .disconnectNodeOutput(
        audioPlayerNode
      )

    /*
     A one-channel player node is mixed to the system output by
     AVAudioEngine's main mixer. The mono signal is therefore
     delivered equally to the left and right output channels.
     */
    audioEngine.connect(
      audioPlayerNode,
      to: audioEngine.mainMixerNode,
      format: format
    )

    audioEngine.mainMixerNode
      .outputVolume = 1

    audioEngine.prepare()

    try audioEngine.start()

    monitorFormat =
      format
  }

  private func formatsMatch(
    _ lhs: AVAudioFormat,
    _ rhs: AVAudioFormat
  ) -> Bool {
    lhs.commonFormat
      == rhs.commonFormat
      && lhs.sampleRate
        == rhs.sampleRate
      && lhs.channelCount
        == rhs.channelCount
      && lhs.isInterleaved
        == rhs.isInterleaved
  }

  private func makePCMBuffer(
    from sampleBuffer: CMSampleBuffer
  ) -> AVAudioPCMBuffer? {
    guard
      let formatDescription =
        CMSampleBufferGetFormatDescription(
          sampleBuffer
        ),
      let streamDescription =
        CMAudioFormatDescriptionGetStreamBasicDescription(
          formatDescription
        )
    else {
      return nil
    }

    var mutableDescription =
      streamDescription.pointee

    guard
      let sourceFormat =
        AVAudioFormat(
          streamDescription:
            &mutableDescription
        )
    else {
      return nil
    }

    let sampleCount =
      CMSampleBufferGetNumSamples(
        sampleBuffer
      )

    guard sampleCount > 0 else {
      return nil
    }

    var requiredSize = 0

    let sizeStatus =
      CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer,
        bufferListSizeNeededOut:
          &requiredSize,
        bufferListOut: nil,
        bufferListSize: 0,
        blockBufferAllocator:
          kCFAllocatorDefault,
        blockBufferMemoryAllocator:
          kCFAllocatorDefault,
        flags: 0,
        blockBufferOut: nil
      )

    guard
      sizeStatus == noErr,
      requiredSize > 0
    else {
      return nil
    }

    let rawBuffer =
      UnsafeMutableRawPointer.allocate(
        byteCount: requiredSize,
        alignment:
          MemoryLayout<
            AudioBufferList
          >.alignment
      )

    defer {
      rawBuffer.deallocate()
    }

    let sourceBufferList =
      rawBuffer.bindMemory(
        to: AudioBufferList.self,
        capacity: 1
      )

    var retainedBlockBuffer: CMBlockBuffer?

    let listStatus =
      CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer,
        bufferListSizeNeededOut: nil,
        bufferListOut:
          sourceBufferList,
        bufferListSize:
          requiredSize,
        blockBufferAllocator:
          kCFAllocatorDefault,
        blockBufferMemoryAllocator:
          kCFAllocatorDefault,
        flags:
          UInt32(
            kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment
          ),
        blockBufferOut:
          &retainedBlockBuffer
      )

    guard listStatus == noErr else {
      return nil
    }

    let frameCapacity =
      AVAudioFrameCount(
        sampleCount
      )

    guard
      let pcmBuffer =
        AVAudioPCMBuffer(
          pcmFormat: sourceFormat,
          frameCapacity:
            frameCapacity
        )
    else {
      return nil
    }

    pcmBuffer.frameLength =
      frameCapacity

    let sourceBuffers =
      UnsafeMutableAudioBufferListPointer(
        sourceBufferList
      )

    let destinationBuffers =
      UnsafeMutableAudioBufferListPointer(
        pcmBuffer
          .mutableAudioBufferList
      )

    guard
      sourceBuffers.count
        == destinationBuffers.count
    else {
      return nil
    }

    for index in sourceBuffers.indices {
      let source =
        sourceBuffers[index]

      var destination =
        destinationBuffers[index]

      guard
        let sourceData =
          source.mData,
        let destinationData =
          destination.mData
      else {
        continue
      }

      let byteCount =
        min(
          Int(
            source.mDataByteSize
          ),
          Int(
            destination.mDataByteSize
          )
        )

      memcpy(
        destinationData,
        sourceData,
        byteCount
      )

      destination.mDataByteSize =
        UInt32(byteCount)

      destinationBuffers[index] =
        destination
    }

    _ = retainedBlockBuffer

    return pcmBuffer
  }

  private func convertAudioBuffer(
    _ sourceBuffer: AVAudioPCMBuffer,
    to destinationFormat:
      AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    guard
      let converter =
        AVAudioConverter(
          from:
            sourceBuffer.format,
          to:
            destinationFormat
        )
    else {
      return nil
    }

    let ratio =
      destinationFormat.sampleRate
      / sourceBuffer.format.sampleRate

    let estimatedFrames =
      max(
        1,
        Int(
          ceil(
            Double(
              sourceBuffer.frameLength
            ) * ratio
          )
        ) + 32
      )

    guard
      let destinationBuffer =
        AVAudioPCMBuffer(
          pcmFormat:
            destinationFormat,
          frameCapacity:
            AVAudioFrameCount(
              estimatedFrames
            )
        )
    else {
      return nil
    }

    var suppliedInput =
      false

    var conversionError: NSError?

    let status =
      converter.convert(
        to: destinationBuffer,
        error: &conversionError
      ) {
        _,
        outputStatus in

        if suppliedInput {
          outputStatus.pointee =
            .noDataNow

          return nil
        }

        suppliedInput =
          true

        outputStatus.pointee =
          .haveData

        return sourceBuffer
      }

    guard
      conversionError == nil,
      status == .haveData
        || status == .inputRanDry,
      destinationBuffer.frameLength > 0
    else {
      return nil
    }

    return destinationBuffer
  }

  private func updateMeters(
    from buffer: AVAudioPCMBuffer,
    monoAudio: Bool
  ) {
    guard
      let channelData =
        buffer.floatChannelData,
      buffer.frameLength > 0
    else {
      publishAudioLevels(
        left: 0,
        right: 0
      )

      return
    }

    let frameCount =
      Int(
        buffer.frameLength
      )

    let channelCount =
      Int(
        buffer.format.channelCount
      )

    guard channelCount > 0 else {
      publishAudioLevels(
        left: 0,
        right: 0
      )

      return
    }

    let left =
      audioLevel(
        samples:
          channelData[0],
        frameCount:
          frameCount
      )

    let right: Double

    if monoAudio
      || channelCount == 1
    {
      right = left
    } else {
      right =
        audioLevel(
          samples:
            channelData[1],
          frameCount:
            frameCount
        )
    }

    publishAudioLevels(
      left: left,
      right: right
    )
  }

  private func audioLevel(
    samples: UnsafePointer<Float>,
    frameCount: Int
  ) -> Double {
    guard frameCount > 0 else {
      return 0
    }

    var sum: Double = 0

    for index in 0..<frameCount {
      let sample =
        Double(
          samples[index]
        )

      sum += sample * sample
    }

    let rms =
      sqrt(
        sum
          / Double(frameCount)
      )

    guard rms.isFinite else {
      return 0
    }

    let decibels =
      20
      * log10(
        max(
          rms,
          0.000_001
        )
      )

    let normalized =
      (decibels + 60) / 60

    return min(
      1,
      max(
        0,
        normalized
      )
    )
  }

  private func publishAudioLevels(
    left: Double,
    right: Double
  ) {
    publishState {
      self.leftAudioLevel =
        left

      self.rightAudioLevel =
        right
    }
  }

  private func stopSessionNow() {
    audioMonitoringRequested =
      false

    resetMonitoringGraph()

    CaptureSessionGate.shared
      .withLock(
        for: session
      ) {
        if session.isRunning {
          session.stopRunning()
        }
      }

    publishState {
      self.isRunning = false
      self.isRecording = false

      self.isAudioMonitoring =
        false

      self.leftAudioLevel = 0
      self.rightAudioLevel = 0
    }
  }

  private func removeSessionConfiguration(
    completion: (() -> Void)? = nil
  ) {
    audioMonitoringRequested =
      false

    resetMonitoringGraph()

    CaptureSessionGate.shared
      .withLock(
        for: session
      ) {
        if session.isRunning {
          session.stopRunning()
        }

        session.beginConfiguration()

        for input in session.inputs {
          session.removeInput(
            input
          )
        }

        for output in session.outputs {
          session.removeOutput(
            output
          )
        }

        session.commitConfiguration()
      }

    currentVideoInput = nil
    currentAudioInput = nil

    currentFinalRecordingURL =
      nil

    pendingStopAfterRecording =
      false

    pendingRemovalAfterRecording =
      false

    pendingClearCompletion =
      nil

    publishState {
      self.isConfigured = false
      self.isRunning = false
      self.isRecording = false
      self.canRecord = false
      self.hasAudioInput = false

      self.activeAudioDeviceName =
        nil

      self.isAudioMonitoring =
        false

      self.leftAudioLevel = 0
      self.rightAudioLevel = 0
      self.errorMessage = nil

      completion?()
    }
  }

  private func makeRecordingURL(
    folderURL: URL,
    fileExtension: String
  ) -> URL {
    let formatter =
      DateFormatter()

    formatter.locale =
      Locale(
        identifier:
          "en_US_POSIX"
      )

    formatter.dateFormat =
      "yyyy-MM-dd_HH-mm-ss"

    let date =
      formatter.string(
        from: Date()
      )

    let safeCameraName =
      cameraName
      .replacingOccurrences(
        of: "[^A-Za-z0-9_-]+",
        with: "-",
        options: .regularExpression
      )
      .trimmingCharacters(
        in: CharacterSet(
          charactersIn: "-"
        )
      )

    let name =
      safeCameraName.isEmpty
      ? cameraID
      : safeCameraName

    return
      folderURL
      .appendingPathComponent(
        "\(date)_\(name)"
      )
      .appendingPathExtension(
        fileExtension
      )
  }

  private func removeFileIfNeeded(
    at url: URL
  ) throws {
    if FileManager.default
      .fileExists(
        atPath: url.path
      )
    {
      try FileManager.default
        .removeItem(
          at: url
        )
    }
  }

  private func exportMP4(
    sourceURL: URL,
    destinationURL: URL
  ) {
    let asset =
      AVURLAsset(
        url: sourceURL
      )

    guard
      let exporter =
        AVAssetExportSession(
          asset: asset,
          presetName:
            AVAssetExportPresetHighestQuality
        )
    else {
      finishMP4Export(
        sourceURL: sourceURL,
        destinationURL:
          destinationURL,
        error:
          CameraError
          .mp4ExportUnavailable
      )

      return
    }

    exporter.outputURL =
      destinationURL

    exporter.outputFileType =
      .mp4

    exporter.shouldOptimizeForNetworkUse =
      true

    exporter.exportAsynchronously { [weak self] in
      guard let self else {
        return
      }

      self.sessionQueue.async {
        switch exporter.status {
        case .completed:
          do {
            if FileManager.default
              .fileExists(
                atPath:
                  sourceURL.path
              )
            {
              try FileManager.default
                .removeItem(
                  at: sourceURL
                )
            }

            self.finishMP4Export(
              sourceURL: sourceURL,
              destinationURL:
                destinationURL,
              error: nil
            )
          } catch {
            self.finishMP4Export(
              sourceURL: sourceURL,
              destinationURL:
                destinationURL,
              error: error
            )
          }

        case .failed, .cancelled:
          self.finishMP4Export(
            sourceURL: sourceURL,
            destinationURL:
              destinationURL,
            error:
              exporter.error
              ?? CameraError
              .mp4ExportUnavailable
          )

        default:
          self.finishMP4Export(
            sourceURL: sourceURL,
            destinationURL:
              destinationURL,
            error:
              CameraError
              .mp4ExportUnavailable
          )
        }
      }
    }
  }

  private func finishMP4Export(
    sourceURL: URL,
    destinationURL: URL,
    error: Error?
  ) {
    currentFinalRecordingURL =
      nil

    publishState {
      self.isRecording = false

      if let error {
        self.lastRecordingURL =
          sourceURL

        self.errorMessage =
          "MP4 export failed: \(error.localizedDescription). The temporary MOV file was kept."
      } else {
        self.lastRecordingURL =
          destinationURL

        self.errorMessage = nil
      }
    }

    finishPendingActionIfNeeded()
  }

  private func finishPendingActionIfNeeded() {
    if pendingRemovalAfterRecording {
      let completion =
        pendingClearCompletion

      pendingRemovalAfterRecording =
        false

      pendingStopAfterRecording =
        false

      pendingClearCompletion =
        nil

      removeSessionConfiguration(
        completion: completion
      )

      return
    }

    if pendingStopAfterRecording {
      pendingStopAfterRecording =
        false

      stopSessionNow()
    }
  }

  private func publishError(
    _ error: Error
  ) {
    publishState {
      self.errorMessage =
        error.localizedDescription
    }
  }

  private func publishState(
    _ changes: @escaping () -> Void
  ) {
    DispatchQueue.main.async {
      changes()
      self.onStateChange?()
    }
  }

  nonisolated func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer:
      CMSampleBuffer,
    from connection:
      AVCaptureConnection
  ) {
    guard
      output === audioDataOutput
    else {
      return
    }

    processAudioSampleBuffer(
      sampleBuffer
    )
  }

  nonisolated func fileOutput(
    _ output: AVCaptureFileOutput,
    didStartRecordingTo fileURL: URL,
    from connections:
      [AVCaptureConnection]
  ) {
    Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      self.isRecording = true
      self.errorMessage = nil
      self.onStateChange?()
    }
  }

  nonisolated func fileOutput(
    _ output: AVCaptureFileOutput,
    didFinishRecordingTo outputFileURL:
      URL,
    from connections:
      [AVCaptureConnection],
    error: Error?
  ) {
    sessionQueue.async { [weak self] in
      guard let self else {
        return
      }

      let nsError =
        error as NSError?

      let successfullyFinished =
        nsError?.userInfo[
          AVErrorRecordingSuccessfullyFinishedKey
        ] as? Bool
        ?? false

      if let error,
        !successfullyFinished
      {
        self.currentFinalRecordingURL =
          nil

        self.publishState {
          self.isRecording = false

          self.lastRecordingURL =
            outputFileURL

          self.errorMessage =
            "Recording failed: \(error.localizedDescription)"
        }

        self.finishPendingActionIfNeeded()

        return
      }

      switch self.currentRecordingFormat {
      case .mov:
        let finalURL =
          self.currentFinalRecordingURL
          ?? outputFileURL

        self.currentFinalRecordingURL =
          nil

        self.publishState {
          self.isRecording = false

          self.lastRecordingURL =
            finalURL

          self.errorMessage = nil
        }

        self.finishPendingActionIfNeeded()

      case .mp4:
        guard
          let destinationURL =
            self.currentFinalRecordingURL
        else {
          self.publishState {
            self.isRecording = false

            self.lastRecordingURL =
              outputFileURL

            self.errorMessage =
              CameraError
              .mp4ExportUnavailable
              .localizedDescription
          }

          self.finishPendingActionIfNeeded()

          return
        }

        self.exportMP4(
          sourceURL: outputFileURL,
          destinationURL:
            destinationURL
        )
      }
    }
  }
}
