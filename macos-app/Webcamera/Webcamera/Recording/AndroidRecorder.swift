import AVFoundation
import AudioToolbox
import CoreMedia
import CoreVideo
import Foundation

final class AndroidRecorder:
  NSObject,
  AVCaptureAudioDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  enum RecorderError:
    LocalizedError
  {
    case alreadyRecording
    case writerCreationFailed
    case cannotAddVideoInput
    case cannotAddAudioInput
    case phoneAudioConfigurationMissing
    case microphoneUnavailable
    case microphonePermissionDenied
    case writerStartFailed
    case recordingNotStarted

    var errorDescription: String? {
      switch self {
      case .alreadyRecording:
        return "Android recording is already active."

      case .writerCreationFailed:
        return "The Android recording file could not be created."

      case .cannotAddVideoInput:
        return "The Android video track could not be added."

      case .cannotAddAudioInput:
        return "The selected audio track could not be added."

      case .phoneAudioConfigurationMissing:
        return "Phone microphone data is not ready yet. Start the Android camera and wait for audio packets before recording."

      case .microphoneUnavailable:
        return "The selected macOS microphone is unavailable."

      case .microphonePermissionDenied:
        return "Microphone access is not granted on macOS."

      case .writerStartFailed:
        return "The Android recording writer could not start."

      case .recordingNotStarted:
        return "Android recording has not started."
      }
    }
  }

  var onRecordingStateChange:
    ((
      _ isRecording: Bool,
      _ lastRecordingURL: URL?,
      _ errorMessage: String?
    ) -> Void)?

  private let queue =
    DispatchQueue(
      label:
        "com.theandreyzakharov.webcamera.android-recorder",
      qos: .userInitiated
    )

  private let audioOutputQueue =
    DispatchQueue(
      label:
        "com.theandreyzakharov.webcamera.android-recorder-audio",
      qos: .userInteractive
    )

  private var writer:
    AVAssetWriter?

  private var videoInput:
    AVAssetWriterInput?

  private var pixelBufferAdaptor:
    AVAssetWriterInputPixelBufferAdaptor?

  private var audioInput:
    AVAssetWriterInput?

  private var microphoneSession:
    AVCaptureSession?

  private var microphoneOutput:
    AVCaptureAudioDataOutput?

  private var firstVideoTime:
    CMTime?

  private var firstPhoneAudioTime:
    CMTime?

  private var firstMacAudioTime:
    CMTime?

  private var outputURL:
    URL?

  private var recordingActive = false

  private var phoneAudioSelected = false

  private var phoneAudioFormatDescription:
    CMAudioFormatDescription?

  private var pendingPhoneAudioConfiguration:
    Data?

  func setPhoneAudioConfiguration(
    _ data: Data
  ) {
    queue.async {
      self.pendingPhoneAudioConfiguration =
        data
    }
  }

  func startRecording(
    folderURL: URL,
    cameraName: String,
    format: RecordingFileFormat,
    width: Int,
    height: Int,
    audioDevice: AudioDeviceInfo,
    monoAudio: Bool
  ) {
    queue.async {
      do {
        try self.startRecordingNow(
          folderURL: folderURL,
          cameraName: cameraName,
          format: format,
          width: width,
          height: height,
          audioDevice: audioDevice,
          monoAudio: monoAudio
        )
      } catch {
        self.publishState(
          isRecording: false,
          lastRecordingURL: nil,
          errorMessage:
            error.localizedDescription
        )
      }
    }
  }

  func appendVideoFrame(
    pixelBuffer: CVPixelBuffer,
    presentationTime: CMTime
  ) {
    queue.async {
      guard
        self.recordingActive,
        let adaptor =
          self.pixelBufferAdaptor,
        let videoInput =
          self.videoInput,
        videoInput.isReadyForMoreMediaData
      else {
        return
      }

      if self.firstVideoTime == nil {
        self.firstVideoTime =
          presentationTime
      }

      guard
        let firstVideoTime =
          self.firstVideoTime
      else {
        return
      }

      let normalizedTime =
        CMTimeSubtract(
          presentationTime,
          firstVideoTime
        )

      guard
        normalizedTime.isValid,
        normalizedTime
          >= .zero
      else {
        return
      }

      if !adaptor.append(
        pixelBuffer,
        withPresentationTime:
          normalizedTime
      ) {
        self.publishWriterError()
      }
    }
  }

  func appendPhoneAudioFrame(
    data: Data,
    presentationTime: CMTime
  ) {
    queue.async {
      guard
        self.recordingActive,
        self.phoneAudioSelected,
        let audioInput =
          self.audioInput,
        let formatDescription =
          self.phoneAudioFormatDescription,
        audioInput.isReadyForMoreMediaData
      else {
        return
      }

      if self.firstPhoneAudioTime == nil {
        self.firstPhoneAudioTime =
          presentationTime
      }

      guard
        let firstPhoneAudioTime =
          self.firstPhoneAudioTime
      else {
        return
      }

      let normalizedTime =
        CMTimeSubtract(
          presentationTime,
          firstPhoneAudioTime
        )

      guard
        normalizedTime.isValid,
        normalizedTime >= .zero,
        let sampleBuffer =
          self.makeCompressedAudioSampleBuffer(
            data: data,
            formatDescription:
              formatDescription,
            presentationTime:
              normalizedTime
          )
      else {
        return
      }

      if !audioInput.append(
        sampleBuffer
      ) {
        self.publishWriterError()
      }
    }
  }

  func stopRecording() {
    queue.async {
      self.stopRecordingNow()
    }
  }

  func cancelRecording() {
    queue.async {
      self.microphoneOutput?
        .setSampleBufferDelegate(
          nil,
          queue: nil
        )

      if self.microphoneSession?
        .isRunning == true
      {
        self.microphoneSession?
          .stopRunning()
      }

      self.writer?.cancelWriting()

      self.resetState()

      self.publishState(
        isRecording: false,
        lastRecordingURL: nil,
        errorMessage: nil
      )
    }
  }

  private func startRecordingNow(
    folderURL: URL,
    cameraName: String,
    format: RecordingFileFormat,
    width: Int,
    height: Int,
    audioDevice: AudioDeviceInfo,
    monoAudio: Bool
  ) throws {
    guard !recordingActive else {
      throw RecorderError.alreadyRecording
    }

    try FileManager.default
      .createDirectory(
        at: folderURL,
        withIntermediateDirectories:
          true
      )

    let destinationURL =
      makeRecordingURL(
        folderURL: folderURL,
        cameraName: cameraName,
        fileExtension:
          format.fileExtension
      )

    if FileManager.default
      .fileExists(
        atPath:
          destinationURL.path
      )
    {
      try FileManager.default
        .removeItem(
          at: destinationURL
        )
    }

    let fileType:
      AVFileType =
        format == .mov
        ? .mov
        : .mp4

    let writer =
      try AVAssetWriter(
        outputURL:
          destinationURL,
        fileType:
          fileType
      )

    let videoSettings:
      [String: Any] = [
        AVVideoCodecKey:
          AVVideoCodecType.h264,
        AVVideoWidthKey:
          width,
        AVVideoHeightKey:
          height,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey:
            8_000_000,
          AVVideoExpectedSourceFrameRateKey:
            30,
          AVVideoMaxKeyFrameIntervalKey:
            60,
        ],
      ]

    let videoInput =
      AVAssetWriterInput(
        mediaType: .video,
        outputSettings:
          videoSettings
      )

    videoInput.expectsMediaDataInRealTime =
      true

    guard writer.canAdd(
      videoInput
    ) else {
      throw
        RecorderError
        .cannotAddVideoInput
    }

    writer.add(
      videoInput
    )

    let adaptor =
      AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput:
          videoInput,
        sourcePixelBufferAttributes: [
          kCVPixelBufferPixelFormatTypeKey
            as String:
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
          kCVPixelBufferWidthKey
            as String:
            width,
          kCVPixelBufferHeightKey
            as String:
            height,
        ]
      )

    self.writer = writer
    self.videoInput = videoInput
    self.pixelBufferAdaptor =
      adaptor

    phoneAudioSelected =
      audioDevice.isPhoneAudio

    if audioDevice.isPhoneAudio {
      guard
        let configuration =
          pendingPhoneAudioConfiguration
      else {
        throw
          RecorderError
          .phoneAudioConfigurationMissing
      }

      let formatDescription =
        try makePhoneAudioFormatDescription(
          configuration:
            configuration
        )

      let audioInput =
        AVAssetWriterInput(
          mediaType: .audio,
          outputSettings: nil,
          sourceFormatHint:
            formatDescription
        )

      audioInput.expectsMediaDataInRealTime =
        true

      guard writer.canAdd(
        audioInput
      ) else {
        throw
          RecorderError
          .cannotAddAudioInput
      }

      writer.add(
        audioInput
      )

      self.audioInput =
        audioInput

      phoneAudioFormatDescription =
        formatDescription
    } else if !audioDevice.isNoAudio {
      let audioInput =
        AVAssetWriterInput(
          mediaType: .audio,
          outputSettings: [
            AVFormatIDKey:
              kAudioFormatMPEG4AAC,
            AVSampleRateKey:
              48_000,
            AVNumberOfChannelsKey:
              monoAudio
              ? 1
              : 2,
            AVEncoderBitRateKey:
              monoAudio
              ? 96_000
              : 160_000,
          ]
        )

      audioInput.expectsMediaDataInRealTime =
        true

      guard writer.canAdd(
        audioInput
      ) else {
        throw
          RecorderError
          .cannotAddAudioInput
      }

      writer.add(
        audioInput
      )

      self.audioInput =
        audioInput

      try configureMacMicrophone(
        audioDevice:
          audioDevice
      )
    }

    guard writer.startWriting() else {
      throw
        writer.error
        ?? RecorderError
        .writerStartFailed
    }

    writer.startSession(
      atSourceTime:
        .zero
    )

    outputURL =
      destinationURL

    recordingActive = true

    firstVideoTime = nil
    firstPhoneAudioTime = nil
    firstMacAudioTime = nil

    if microphoneSession?
      .isRunning == false
    {
      microphoneSession?
        .startRunning()
    }

    publishState(
      isRecording: true,
      lastRecordingURL: nil,
      errorMessage: nil
    )
  }

  private func stopRecordingNow() {
    guard
      recordingActive,
      let writer
    else {
      return
    }

    recordingActive = false

    microphoneOutput?
      .setSampleBufferDelegate(
        nil,
        queue: nil
      )

    if microphoneSession?
      .isRunning == true
    {
      microphoneSession?
        .stopRunning()
    }

    videoInput?
      .markAsFinished()

    audioInput?
      .markAsFinished()

    let finishedURL =
      outputURL

    writer.finishWriting {
      let errorMessage =
        writer.status == .completed
        ? nil
        : writer.error?
          .localizedDescription
          ?? "Android recording failed."

      self.queue.async {
        self.resetState()

        self.publishState(
          isRecording: false,
          lastRecordingURL:
            errorMessage == nil
            ? finishedURL
            : nil,
          errorMessage:
            errorMessage
        )
      }
    }
  }

  private func configureMacMicrophone(
    audioDevice: AudioDeviceInfo
  ) throws {
    guard
      AVCaptureDevice.authorizationStatus(
        for: .audio
      ) == .authorized
    else {
      throw
        RecorderError
        .microphonePermissionDenied
    }

    guard
      let device =
        audioDevice.device
    else {
      throw
        RecorderError
        .microphoneUnavailable
    }

    let input =
      try AVCaptureDeviceInput(
        device: device
      )

    let output =
      AVCaptureAudioDataOutput()

    let session =
      AVCaptureSession()

    session.beginConfiguration()

    guard session.canAddInput(
      input
    ) else {
      session.commitConfiguration()

      throw
        RecorderError
        .microphoneUnavailable
    }

    session.addInput(
      input
    )

    guard session.canAddOutput(
      output
    ) else {
      session.commitConfiguration()

      throw
        RecorderError
        .cannotAddAudioInput
    }

    session.addOutput(
      output
    )

    session.commitConfiguration()

    output.setSampleBufferDelegate(
      self,
      queue:
        audioOutputQueue
    )

    microphoneSession =
      session

    microphoneOutput =
      output
  }

  private func makePhoneAudioFormatDescription(
    configuration: Data
  ) throws -> CMAudioFormatDescription {
    var streamDescription =
      AudioStreamBasicDescription(
        mSampleRate:
          48_000,
        mFormatID:
          kAudioFormatMPEG4AAC,
        mFormatFlags:
        AudioFormatFlags(
            2
        ),
        mBytesPerPacket: 0,
        mFramesPerPacket: 1024,
        mBytesPerFrame: 0,
        mChannelsPerFrame: 1,
        mBitsPerChannel: 0,
        mReserved: 0
      )

    var description:
      CMAudioFormatDescription?

    let status =
      configuration.withUnsafeBytes {
        bytes in

        CMAudioFormatDescriptionCreate(
          allocator:
            kCFAllocatorDefault,
          asbd:
            &streamDescription,
          layoutSize: 0,
          layout: nil,
          magicCookieSize:
            configuration.count,
          magicCookie:
            bytes.baseAddress,
          extensions: nil,
          formatDescriptionOut:
            &description
        )
      }

    guard
      status == noErr,
      let description
    else {
      throw
        RecorderError
        .phoneAudioConfigurationMissing
    }

    return description
  }

  private func makeCompressedAudioSampleBuffer(
    data: Data,
    formatDescription:
      CMAudioFormatDescription,
    presentationTime:
      CMTime
  ) -> CMSampleBuffer? {
    var blockBuffer:
      CMBlockBuffer?

    let blockStatus =
      CMBlockBufferCreateWithMemoryBlock(
        allocator:
          kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength:
          data.count,
        blockAllocator:
          kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength:
          data.count,
        flags: 0,
        blockBufferOut:
          &blockBuffer
      )

    guard
      blockStatus == noErr,
      let blockBuffer
    else {
      return nil
    }

    let replaceStatus =
      data.withUnsafeBytes {
        bytes in

        guard
          let baseAddress =
            bytes.baseAddress
        else {
          return
            OSStatus(
              kCMBlockBufferBadLengthParameterErr
            )
        }

        return
          CMBlockBufferReplaceDataBytes(
            with:
              baseAddress,
            blockBuffer:
              blockBuffer,
            offsetIntoDestination:
              0,
            dataLength:
              data.count
          )
      }

    guard replaceStatus == noErr else {
      return nil
    }

    var timing =
      CMSampleTimingInfo(
        duration:
          CMTime(
            value: 1024,
            timescale:
              48_000
          ),
        presentationTimeStamp:
          presentationTime,
        decodeTimeStamp:
          .invalid
      )

    var sampleSize =
      data.count

    var sampleBuffer:
      CMSampleBuffer?

    let sampleStatus =
      CMSampleBufferCreateReady(
        allocator:
          kCFAllocatorDefault,
        dataBuffer:
          blockBuffer,
        formatDescription:
          formatDescription,
        sampleCount: 1,
        sampleTimingEntryCount: 1,
        sampleTimingArray:
          &timing,
        sampleSizeEntryCount: 1,
        sampleSizeArray:
          &sampleSize,
        sampleBufferOut:
          &sampleBuffer
      )

    guard sampleStatus == noErr else {
      return nil
    }

    return sampleBuffer
  }

  private func retimedMacAudioSampleBuffer(
    _ sampleBuffer:
      CMSampleBuffer
  ) -> CMSampleBuffer? {
    let originalTime =
      CMSampleBufferGetPresentationTimeStamp(
        sampleBuffer
      )

    if firstMacAudioTime == nil {
      firstMacAudioTime =
        originalTime
    }

    guard
      let firstMacAudioTime
    else {
      return nil
    }

    let normalizedTime =
      CMTimeSubtract(
        originalTime,
        firstMacAudioTime
      )

    let duration =
      CMSampleBufferGetDuration(
        sampleBuffer
      )

    var timing =
      CMSampleTimingInfo(
        duration:
          duration,
        presentationTimeStamp:
          normalizedTime,
        decodeTimeStamp:
          .invalid
      )

    var result:
      CMSampleBuffer?

    let status =
      CMSampleBufferCreateCopyWithNewTiming(
        allocator:
          kCFAllocatorDefault,
        sampleBuffer:
          sampleBuffer,
        sampleTimingEntryCount: 1,
        sampleTimingArray:
          &timing,
        sampleBufferOut:
          &result
      )

    guard status == noErr else {
      return nil
    }

    return result
  }

  private func makeRecordingURL(
    folderURL: URL,
    cameraName: String,
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

    let safeName =
      cameraName
      .replacingOccurrences(
        of: "[^A-Za-z0-9_-]+",
        with: "-",
        options:
          .regularExpression
      )
      .trimmingCharacters(
        in: CharacterSet(
          charactersIn: "-"
        )
      )

    let name =
      safeName.isEmpty
      ? "Android-Camera"
      : safeName

    return folderURL
      .appendingPathComponent(
        "\(date)_\(name)"
      )
      .appendingPathExtension(
        fileExtension
      )
  }

  private func publishWriterError() {
    guard
      let error =
        writer?.error
    else {
      return
    }

    publishState(
      isRecording:
        recordingActive,
      lastRecordingURL: nil,
      errorMessage:
        error.localizedDescription
    )
  }

  private func resetState() {
    writer = nil
    videoInput = nil
    pixelBufferAdaptor = nil
    audioInput = nil

    microphoneSession = nil
    microphoneOutput = nil

    firstVideoTime = nil
    firstPhoneAudioTime = nil
    firstMacAudioTime = nil

    outputURL = nil

    recordingActive = false
    phoneAudioSelected = false

    phoneAudioFormatDescription =
      nil
  }

  private func publishState(
    isRecording: Bool,
    lastRecordingURL: URL?,
    errorMessage: String?
  ) {
    DispatchQueue.main.async {
      self.onRecordingStateChange?(
        isRecording,
        lastRecordingURL,
        errorMessage
      )
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer:
      CMSampleBuffer,
    from connection:
      AVCaptureConnection
  ) {
    queue.async {
      guard
        self.recordingActive,
        !self.phoneAudioSelected,
        let audioInput =
          self.audioInput,
        audioInput.isReadyForMoreMediaData,
        let retimedBuffer =
          self.retimedMacAudioSampleBuffer(
            sampleBuffer
          )
      else {
        return
      }

      if !audioInput.append(
        retimedBuffer
      ) {
        self.publishWriterError()
      }
    }
  }
}
