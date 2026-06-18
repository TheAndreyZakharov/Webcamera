import AVFoundation
import Foundation

enum CameraSourceKind: String, Codable {
  case builtIn
  case external
  case android

  var title: String {
    switch self {
    case .builtIn:
      return "Built-in"

    case .external:
      return "External"

    case .android:
      return "Android"
    }
  }

  var systemImage: String {
    switch self {
    case .builtIn:
      return "laptopcomputer"

    case .external:
      return "video"

    case .android:
      return "iphone.gen3"
    }
  }

  var sortOrder: Int {
    switch self {
    case .builtIn:
      return 0

    case .external:
      return 1

    case .android:
      return 2
    }
  }
}

struct AudioDeviceInfo: Identifiable, Hashable {
  static let noAudioID = "__webcamera_no_audio__"

  let id: String
  let name: String
  let device: AVCaptureDevice?

  var isNoAudio: Bool {
    id == Self.noAudioID
  }

  static var noAudio: AudioDeviceInfo {
    AudioDeviceInfo(
      id: noAudioID,
      name: "No Audio",
      device: nil
    )
  }

  static func systemAudioDevices() -> [AudioDeviceInfo] {
    let discovery =
      AVCaptureDevice.DiscoverySession(
        deviceTypes: [
          .microphone
        ],
        mediaType: .audio,
        position: .unspecified
      )

    let devices =
      discovery.devices
      .map { device in
        AudioDeviceInfo(
          id: device.uniqueID,
          name: device.localizedName,
          device: device
        )
      }
      .sorted {
        $0.name.localizedCaseInsensitiveCompare(
          $1.name
        ) == .orderedAscending
      }

    return [.noAudio] + devices
  }

  static func preferredDeviceID(
    for camera: CameraDeviceInfo,
    from audioDevices: [AudioDeviceInfo]
  ) -> String {
    let availableDevices =
      audioDevices.filter {
        !$0.isNoAudio
      }

    guard !availableDevices.isEmpty else {
      return noAudioID
    }

    let cameraName =
      normalizedWords(camera.name)

    guard !cameraName.isEmpty else {
      return noAudioID
    }

    let scoredDevices =
      availableDevices.map { audioDevice in
        let audioName =
          normalizedWords(
            audioDevice.name
          )

        let commonWords =
          cameraName.intersection(
            audioName
          )

        return (
          device: audioDevice,
          score: commonWords.count
        )
      }
      .filter {
        $0.score > 0
      }
      .sorted {
        if $0.score != $1.score {
          return $0.score > $1.score
        }

        return $0.device.name
          .localizedCaseInsensitiveCompare(
            $1.device.name
          ) == .orderedAscending
      }

    return scoredDevices.first?
      .device.id
      ?? noAudioID
  }

  private static func normalizedWords(
    _ value: String
  ) -> Set<String> {
    let ignoredWords: Set<String> = [
      "camera",
      "webcam",
      "microphone",
      "mic",
      "audio",
      "video",
      "usb",
      "hd",
      "pro",
      "built",
      "in",
    ]

    let normalized =
      value
      .folding(
        options: [
          .caseInsensitive,
          .diacriticInsensitive,
        ],
        locale: .current
      )
      .lowercased()
      .replacingOccurrences(
        of: "[^a-z0-9]+",
        with: " ",
        options: .regularExpression
      )

    let words =
      normalized
      .split(separator: " ")
      .map(String.init)
      .filter {
        $0.count >= 2
          && !ignoredWords.contains($0)
      }

    return Set(words)
  }

  static func == (
    lhs: AudioDeviceInfo,
    rhs: AudioDeviceInfo
  ) -> Bool {
    lhs.id == rhs.id
  }

  func hash(
    into hasher: inout Hasher
  ) {
    hasher.combine(id)
  }
}

struct CameraDeviceInfo:
  Identifiable,
  Hashable
{
  let id: String
  let name: String
  let kind: CameraSourceKind
  let device: AVCaptureDevice?
  let formats: [VideoFormat]

  var subtitle: String {
    switch kind {
    case .builtIn:
      return "Built-in camera"

    case .external:
      return "Connected or virtual camera"

    case .android:
      return "Android USB camera"
    }
  }

  static func localCameras()
    -> [CameraDeviceInfo]
  {
    let discovery =
      AVCaptureDevice.DiscoverySession(
        deviceTypes: [
          .builtInWideAngleCamera,
          .external,
        ],
        mediaType: .video,
        position: .unspecified
      )

    return discovery.devices
      .map { device in
        let kind: CameraSourceKind =
          device.deviceType == .external
          ? .external
          : .builtIn

        return CameraDeviceInfo(
          id: device.uniqueID,
          name: device.localizedName,
          kind: kind,
          device: device,
          formats:
            VideoFormat.formats(
              for: device
            )
        )
      }
      .sorted {
        if $0.kind.sortOrder
          != $1.kind.sortOrder
        {
          return $0.kind.sortOrder
            < $1.kind.sortOrder
        }

        return $0.name
          .localizedCaseInsensitiveCompare(
            $1.name
          )
          == .orderedAscending
      }
  }

  static func == (
    lhs: CameraDeviceInfo,
    rhs: CameraDeviceInfo
  ) -> Bool {
    lhs.id == rhs.id
  }

  func hash(
    into hasher: inout Hasher
  ) {
    hasher.combine(id)
  }
}
