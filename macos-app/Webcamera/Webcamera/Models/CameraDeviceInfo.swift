import AVFoundation
import CoreMedia
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
  static let noAudioID =
    "__webcamera_no_audio__"

  static let phoneAudioID =
    "__webcamera_phone_audio__"

  let id: String
  let name: String
  let device: AVCaptureDevice?

  var isNoAudio: Bool {
    id == Self.noAudioID
  }
  var isPhoneAudio: Bool {
    id == Self.phoneAudioID
  }


  static var noAudio: AudioDeviceInfo {
    AudioDeviceInfo(
      id: noAudioID,
      name: "No Audio",
      device: nil
    )
  }

  static var phoneMicrophone:
    AudioDeviceInfo
  {
    AudioDeviceInfo(
      id: phoneAudioID,
      name: "Phone Microphone",
      device: nil
    )
  }

  static func systemAudioDevices()
    -> [AudioDeviceInfo]
  {
    let discovery =
      AVCaptureDevice.DiscoverySession(
        deviceTypes: [
          .microphone,
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
        $0.name
          .localizedCaseInsensitiveCompare(
            $1.name
          ) == .orderedAscending
      }

    return [.noAudio] + devices
  }

  static func preferredDeviceID(
    for camera: CameraDeviceInfo,
    from audioDevices: [AudioDeviceInfo]
  ) -> String {
    /*
    Для Android по умолчанию используем микрофон телефона.
    При необходимости пользователь сможет выбрать любой
    системный микрофон macOS или No Audio.
    */
    if camera.kind == .android {
      return phoneAudioID
    }

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

  /*
   Для обычной камеры это nil.
   Для Android здесь находится серийный номер ADB.
   */
  let androidDeviceID: String?

  var isAndroid: Bool {
    kind == .android
  }

  var subtitle: String {
    switch kind {
    case .builtIn:
      return "Built-in camera"

    case .external:
      return "Connected or virtual camera"

    case .android:
      if let androidDeviceID,
        !androidDeviceID.isEmpty
      {
        return
          "Android USB camera · \(androidDeviceID)"
      }

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
            ),
          androidDeviceID: nil
        )
      }
      .sorted(
        by: sortCameras
      )
  }

  static func androidCamera(
    device: ADBController.Device
  ) -> CameraDeviceInfo {
    CameraDeviceInfo(
      id:
        "android:\(device.id)",
      name:
        "\(device.displayName) Camera",
      kind: .android,
      device: nil,
      formats:
        defaultAndroidFormats(
          deviceID: device.id
        ),
      androidDeviceID:
        device.id
    )
  }

  static func sorted(
    _ cameras: [CameraDeviceInfo]
  ) -> [CameraDeviceInfo] {
    cameras.sorted(
      by: sortCameras
    )
  }

  private static func defaultAndroidFormats(
    deviceID: String
  ) -> [VideoFormat] {
    let subtype =
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

    let values: [
      (
        width: Int,
        height: Int,
        frameRate: Double
      )
    ] = [
      (1920, 1080, 30),
      (1280, 720, 30),
      (960, 540, 30),
      (640, 480, 30),
    ]

    return values.enumerated().map {
      index,
      value in

      VideoFormat(
        id:
          "android:\(deviceID):\(value.width)x\(value.height)@\(Int(value.frameRate))",
        width: value.width,
        height: value.height,
        frameRate:
          value.frameRate,
        formatIndex: index,
        mediaSubType:
          subtype
      )
    }
  }

  private static func sortCameras(
    _ lhs: CameraDeviceInfo,
    _ rhs: CameraDeviceInfo
  ) -> Bool {
    if lhs.kind.sortOrder
      != rhs.kind.sortOrder
    {
      return lhs.kind.sortOrder
        < rhs.kind.sortOrder
    }

    return lhs.name
      .localizedCaseInsensitiveCompare(
        rhs.name
      ) == .orderedAscending
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
