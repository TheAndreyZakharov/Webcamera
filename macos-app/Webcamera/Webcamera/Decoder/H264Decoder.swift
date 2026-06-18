import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

final class H264Decoder:
  @unchecked Sendable
{
  typealias FrameHandler = (
    CVPixelBuffer,
    CMTime
  ) -> Void

  enum DecoderError:
    LocalizedError
  {
    case missingParameterSets
    case invalidParameterSets
    case formatDescriptionFailed(
      OSStatus
    )
    case sessionCreationFailed(
      OSStatus
    )
    case blockBufferCreationFailed(
      OSStatus
    )
    case sampleBufferCreationFailed(
      OSStatus
    )
    case decodeFailed(OSStatus)

    var errorDescription: String? {
      switch self {
      case .missingParameterSets:
        return "The H.264 SPS or PPS is missing."

      case .invalidParameterSets:
        return "The H.264 codec configuration is invalid."

      case let .formatDescriptionFailed(status):
        return "H.264 format creation failed with status \(status)."

      case let .sessionCreationFailed(status):
        return "H.264 decoder creation failed with status \(status)."

      case let .blockBufferCreationFailed(status):
        return "H.264 block-buffer creation failed with status \(status)."

      case let .sampleBufferCreationFailed(status):
        return "H.264 sample-buffer creation failed with status \(status)."

      case let .decodeFailed(status):
        return "H.264 frame decoding failed with status \(status)."
      }
    }
  }

  var onFrame:
    FrameHandler?

  var onError:
    ((Error) -> Void)?

  private let queue =
    DispatchQueue(
      label:
        "com.theandreyzakharov.webcamera.h264-decoder",
      qos: .userInteractive
    )

  private var formatDescription:
    CMVideoFormatDescription?

  private var decompressionSession:
    VTDecompressionSession?

  func configure(
    annexBData: Data
  ) {
    queue.async { [weak self] in
      guard let self else {
        return
      }

      do {
        try self.configureDecoder(
          annexBData:
            annexBData
        )
      } catch {
        self.publishError(error)
      }
    }
  }

  func decode(
    annexBData: Data,
    presentationTime:
      CMTime,
    decodeTime:
      CMTime,
    isKeyFrame: Bool
  ) {
    queue.async { [weak self] in
      guard let self else {
        return
      }

      do {
        try self.decodeFrame(
          annexBData:
            annexBData,
          presentationTime:
            presentationTime,
          decodeTime:
            decodeTime,
          isKeyFrame:
            isKeyFrame
        )
      } catch {
        self.publishError(error)
      }
    }
  }

  func reset() {
    queue.sync {
      invalidateSession()
      formatDescription = nil
    }
  }

  private func configureDecoder(
    annexBData: Data
  ) throws {
    let units =
      splitAnnexBNALUnits(
        annexBData
      )

    let sps =
      units.first {
        nalUnitType($0) == 7
      }

    let pps =
      units.first {
        nalUnitType($0) == 8
      }

    guard
      let sps,
      let pps
    else {
      throw
        DecoderError
        .missingParameterSets
    }

    invalidateSession()

    var newDescription:
      CMFormatDescription?

    let status =
      sps.withUnsafeBytes {
        spsBytes in

        pps.withUnsafeBytes {
          ppsBytes in

          guard
            let spsAddress =
              spsBytes
              .baseAddress?
              .assumingMemoryBound(
                to: UInt8.self
              ),
            let ppsAddress =
              ppsBytes
              .baseAddress?
              .assumingMemoryBound(
                to: UInt8.self
              )
          else {
            return
              OSStatus(
                kCMFormatDescriptionError_InvalidParameter
              )
          }

          var pointers: [
            UnsafePointer<UInt8>
          ] = [
            UnsafePointer(
              spsAddress
            ),
            UnsafePointer(
              ppsAddress
            ),
          ]

          var sizes: [Int] = [
            sps.count,
            pps.count,
          ]

          return pointers
            .withUnsafeMutableBufferPointer {
              pointerBuffer in

              sizes
                .withUnsafeMutableBufferPointer {
                  sizeBuffer in

                  CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator:
                      kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers:
                      pointerBuffer.baseAddress!,
                    parameterSetSizes:
                      sizeBuffer.baseAddress!,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut:
                      &newDescription
                  )
                }
            }
        }
      }

    guard status == noErr,
      let description =
        newDescription
    else {
      throw
        DecoderError
        .formatDescriptionFailed(
          status
        )
    }

    formatDescription =
      description

    var callback =
      VTDecompressionOutputCallbackRecord(
        decompressionOutputCallback: {
          decompressionOutputRefCon,
          _,
          status,
          _,
          imageBuffer,
          presentationTimeStamp,
          _ in

          guard status == noErr,
            let imageBuffer,
            let decompressionOutputRefCon
          else {
            return
          }

          let decoder =
            Unmanaged<
              H264Decoder
            >
            .fromOpaque(
              decompressionOutputRefCon
            )
            .takeUnretainedValue()

          decoder.publishFrame(
            imageBuffer,
            presentationTime:
              presentationTimeStamp
          )
        },
        decompressionOutputRefCon:
          Unmanaged
          .passUnretained(self)
          .toOpaque()
      )

    let destinationAttributes:
      [CFString: Any] = [
        kCVPixelBufferPixelFormatTypeKey:
          kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferMetalCompatibilityKey:
          true,
      ]

    var newSession:
      VTDecompressionSession?

    let sessionStatus =
      VTDecompressionSessionCreate(
        allocator:
          kCFAllocatorDefault,
        formatDescription:
          description,
        decoderSpecification: nil,
        imageBufferAttributes:
          destinationAttributes
            as CFDictionary,
        outputCallback:
          &callback,
        decompressionSessionOut:
          &newSession
      )

    guard sessionStatus == noErr,
      let newSession
    else {
      throw
        DecoderError
        .sessionCreationFailed(
          sessionStatus
        )
    }

    decompressionSession =
      newSession
  }

  private func decodeFrame(
    annexBData: Data,
    presentationTime:
      CMTime,
    decodeTime:
      CMTime,
    isKeyFrame: Bool
  ) throws {
    guard
      let formatDescription,
      let decompressionSession
    else {
      throw
        DecoderError
        .missingParameterSets
    }

    let avccData =
      convertAnnexBToAVCC(
        annexBData
      )

    guard !avccData.isEmpty else {
      return
    }

    var blockBuffer:
      CMBlockBuffer?

    let blockStatus =
      avccData.withUnsafeBytes {
        rawBuffer in

        guard
          let baseAddress =
            rawBuffer.baseAddress
        else {
          return
            OSStatus(
              kCMBlockBufferBadLengthParameterErr
            )
        }

        return
          CMBlockBufferCreateWithMemoryBlock(
            allocator:
              kCFAllocatorDefault,
            memoryBlock:
              nil,
            blockLength:
              avccData.count,
            blockAllocator:
              kCFAllocatorDefault,
            customBlockSource:
              nil,
            offsetToData: 0,
            dataLength:
              avccData.count,
            flags: 0,
            blockBufferOut:
              &blockBuffer
          )
          == noErr
          ? CMBlockBufferReplaceDataBytes(
              with: baseAddress,
              blockBuffer:
                blockBuffer!,
              offsetIntoDestination: 0,
              dataLength:
                avccData.count
            )
          : OSStatus(
              kCMBlockBufferBadCustomBlockSourceErr
            )
      }

    guard blockStatus == noErr,
      let blockBuffer
    else {
      throw
        DecoderError
        .blockBufferCreationFailed(
          blockStatus
        )
    }

    var timing =
      CMSampleTimingInfo(
        duration: .invalid,
        presentationTimeStamp:
          presentationTime,
        decodeTimeStamp:
          decodeTime
      )

    var sampleSize =
      avccData.count

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

    guard sampleStatus == noErr,
      let sampleBuffer
    else {
      throw
        DecoderError
        .sampleBufferCreationFailed(
          sampleStatus
        )
    }

    if !isKeyFrame,
      let attachments =
        CMSampleBufferGetSampleAttachmentsArray(
          sampleBuffer,
          createIfNecessary: true
        ) as?
        [NSMutableDictionary],
      let first =
        attachments.first
    {
      first[
        kCMSampleAttachmentKey_NotSync
      ] = true
    }

    let decodeStatus =
      VTDecompressionSessionDecodeFrame(
        decompressionSession,
        sampleBuffer:
          sampleBuffer,
        flags: [
          ._EnableAsynchronousDecompression,
          ._EnableTemporalProcessing,
        ],
        frameRefcon: nil,
        infoFlagsOut: nil
      )

    guard decodeStatus == noErr else {
      throw
        DecoderError
        .decodeFailed(
          decodeStatus
        )
    }
  }

  private func invalidateSession() {
    if let decompressionSession {
      VTDecompressionSessionWaitForAsynchronousFrames(
        decompressionSession
      )

      VTDecompressionSessionInvalidate(
        decompressionSession
      )
    }

    decompressionSession = nil
  }

  private func publishFrame(
    _ pixelBuffer:
      CVPixelBuffer,
    presentationTime:
      CMTime
  ) {
    DispatchQueue.main.async {
      [weak self] in

      self?.onFrame?(
        pixelBuffer,
        presentationTime
      )
    }
  }

  private func publishError(
    _ error: Error
  ) {
    DispatchQueue.main.async {
      [weak self] in

      self?.onError?(error)
    }
  }

  private func nalUnitType(
    _ data: Data
  ) -> UInt8 {
    guard let first = data.first else {
      return 0
    }

    return first & 0x1F
  }

  private func splitAnnexBNALUnits(
    _ data: Data
  ) -> [Data] {
    let bytes = [UInt8](data)

    guard !bytes.isEmpty else {
      return []
    }

    var startOffsets: [
      (
        startCode: Int,
        payload: Int
      )
    ] = []

    var index = 0

    while index + 3 < bytes.count {
      if bytes[index] == 0,
        bytes[index + 1] == 0,
        bytes[index + 2] == 0,
        bytes[index + 3] == 1
      {
        startOffsets.append(
          (
            startCode: index,
            payload: index + 4
          )
        )

        index += 4
        continue
      }

      if bytes[index] == 0,
        bytes[index + 1] == 0,
        bytes[index + 2] == 1
      {
        startOffsets.append(
          (
            startCode: index,
            payload: index + 3
          )
        )

        index += 3
        continue
      }

      index += 1
    }

    if startOffsets.isEmpty {
      return [data]
    }

    var units: [Data] = []

    for offsetIndex
      in startOffsets.indices
    {
      let payloadStart =
        startOffsets[offsetIndex]
        .payload

      let payloadEnd =
        offsetIndex + 1
          < startOffsets.count
        ? startOffsets[
            offsetIndex + 1
          ].startCode
        : bytes.count

      guard payloadStart
        < payloadEnd
      else {
        continue
      }

      units.append(
        Data(
          bytes[
            payloadStart
              ..< payloadEnd
          ]
        )
      )
    }

    return units
  }

  private func convertAnnexBToAVCC(
    _ data: Data
  ) -> Data {
    let units =
      splitAnnexBNALUnits(
        data
      )

    var output = Data()

    for unit in units
    where !unit.isEmpty {
      let length =
        UInt32(unit.count)

      output.append(
        UInt8(
          (length >> 24)
          & 0xFF
        )
      )

      output.append(
        UInt8(
          (length >> 16)
          & 0xFF
        )
      )

      output.append(
        UInt8(
          (length >> 8)
          & 0xFF
        )
      )

      output.append(
        UInt8(
          length & 0xFF
        )
      )

      output.append(unit)
    }

    return output
  }
}
