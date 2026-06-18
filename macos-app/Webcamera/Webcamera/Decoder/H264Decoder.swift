import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

final class H264Decoder {
  typealias FrameHandler = (
    CVPixelBuffer,
    CMTime
  ) -> Void

  var onFrame: FrameHandler?

  func reset() {
  }
}
