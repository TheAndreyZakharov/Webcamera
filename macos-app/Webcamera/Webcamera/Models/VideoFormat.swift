import AVFoundation
import CoreMedia
import Foundation

struct VideoFormat: Identifiable, Hashable {
  let id: String
  let width: Int
  let height: Int
  let frameRate: Double
  let formatIndex: Int
  let mediaSubType: FourCharCode

  var title: String {
    "\(width) × \(height) · \(frameRateTitle)"
  }

  var frameRateTitle: String {
    if frameRate.rounded() == frameRate {
      return "\(Int(frameRate)) FPS"
    }

    return String(
      format: "%.2f FPS",
      frameRate
    )
  }

  var pixelCount: Int {
    width * height
  }

  static func formats(
    for device: AVCaptureDevice
  ) -> [VideoFormat] {
    var uniqueFormats: [String: VideoFormat] = [:]

    for (
      formatIndex,
      deviceFormat
    ) in device.formats.enumerated() {
      let description =
        deviceFormat.formatDescription

      let dimensions =
        CMVideoFormatDescriptionGetDimensions(
          description
        )

      guard dimensions.width > 0,
        dimensions.height > 0
      else {
        continue
      }

      let width = Int(dimensions.width)
      let height = Int(dimensions.height)

      let mediaSubType =
        CMFormatDescriptionGetMediaSubType(
          description
        )

      let frameRates =
        supportedFrameRates(
          for: deviceFormat
        )

      for frameRate in frameRates {
        let normalizedRate =
          normalizeFrameRate(frameRate)

        let key =
          "\(width)x\(height)@\(normalizedRate)"

        let candidate = VideoFormat(
          id:
            "\(device.uniqueID)-\(width)x\(height)-\(normalizedRate)",
          width: width,
          height: height,
          frameRate: normalizedRate,
          formatIndex: formatIndex,
          mediaSubType: mediaSubType
        )

        if let existing = uniqueFormats[key] {
          if shouldPrefer(
            candidate,
            over: existing,
            device: device
          ) {
            uniqueFormats[key] = candidate
          }
        } else {
          uniqueFormats[key] = candidate
        }
      }
    }

    return uniqueFormats.values.sorted {
      if $0.pixelCount != $1.pixelCount {
        return $0.pixelCount > $1.pixelCount
      }

      if $0.width != $1.width {
        return $0.width > $1.width
      }

      return $0.frameRate > $1.frameRate
    }
  }

  static func resolveDeviceFormat(
    _ configuration: VideoFormat,
    for device: AVCaptureDevice
  ) -> AVCaptureDevice.Format? {
    if device.formats.indices.contains(
      configuration.formatIndex
    ) {
      let indexedFormat =
        device.formats[
          configuration.formatIndex
        ]

      if matches(
        configuration,
        deviceFormat: indexedFormat
      ) {
        return indexedFormat
      }
    }

    return device.formats.first {
      matches(
        configuration,
        deviceFormat: $0
      )
    }
  }

  private static func matches(
    _ configuration: VideoFormat,
    deviceFormat: AVCaptureDevice.Format
  ) -> Bool {
    let description =
      deviceFormat.formatDescription

    let dimensions =
      CMVideoFormatDescriptionGetDimensions(
        description
      )

    guard
      Int(dimensions.width)
        == configuration.width,
      Int(dimensions.height)
        == configuration.height
    else {
      return false
    }

    return deviceFormat
      .videoSupportedFrameRateRanges
      .contains { range in
        configuration.frameRate
          >= range.minFrameRate - 0.01
          && configuration.frameRate
            <= range.maxFrameRate + 0.01
      }
  }

  private static func supportedFrameRates(
    for format: AVCaptureDevice.Format
  ) -> [Double] {
    let commonRates: [Double] = [
      15,
      23.976,
      24,
      25,
      29.97,
      30,
      50,
      59.94,
      60,
      120,
    ]

    var rates = Set<Double>()

    for range in format.videoSupportedFrameRateRanges {
      for rate in commonRates {
        if rate
          >= range.minFrameRate - 0.01,
          rate
            <= range.maxFrameRate + 0.01
        {
          rates.insert(
            normalizeFrameRate(rate)
          )
        }
      }

      if rates.isEmpty {
        rates.insert(
          normalizeFrameRate(
            range.maxFrameRate
          )
        )
      }
    }

    return rates.sorted()
  }

  private static func normalizeFrameRate(
    _ frameRate: Double
  ) -> Double {
    let knownRates: [Double] = [
      15,
      23.976,
      24,
      25,
      29.97,
      30,
      50,
      59.94,
      60,
      120,
    ]

    if let knownRate =
      knownRates.min(
        by: {
          abs($0 - frameRate)
            < abs($1 - frameRate)
        }
      ),
      abs(knownRate - frameRate) < 0.1
    {
      return knownRate
    }

    return (frameRate * 100).rounded() / 100
  }

  private static func shouldPrefer(
    _ candidate: VideoFormat,
    over existing: VideoFormat,
    device: AVCaptureDevice
  ) -> Bool {
    guard
      device.formats.indices.contains(
        candidate.formatIndex
      ),
      device.formats.indices.contains(
        existing.formatIndex
      )
    else {
      return false
    }

    let candidateType =
      candidate.mediaSubType

    let existingType =
      existing.mediaSubType

    let preferredTypes: [FourCharCode] = [
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      kCVPixelFormatType_422YpCbCr8,
      kCVPixelFormatType_32BGRA,
    ]

    let candidatePriority =
      preferredTypes.firstIndex(
        of: candidateType
      )
      ?? preferredTypes.count

    let existingPriority =
      preferredTypes.firstIndex(
        of: existingType
      )
      ?? preferredTypes.count

    return candidatePriority
      < existingPriority
  }
}
