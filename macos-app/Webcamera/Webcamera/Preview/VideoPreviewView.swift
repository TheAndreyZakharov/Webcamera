import AVFoundation
import AppKit
import CoreImage
import CoreVideo
import SwiftUI

final class CaptureSessionGate: @unchecked Sendable {
  static let shared =
    CaptureSessionGate()

  private let registryLock =
    NSLock()

  private var sessionLocks:
    [ObjectIdentifier:
      NSRecursiveLock] = [:]

  private init() {
  }

  func withLock<T>(
    for session: AVCaptureSession,
    _ operation: () throws -> T
  ) rethrows -> T {
    let sessionLock =
      lock(
        for: session
      )

    sessionLock.lock()

    defer {
      sessionLock.unlock()
    }

    return try operation()
  }

  private func lock(
    for session: AVCaptureSession
  ) -> NSRecursiveLock {
    let identifier =
      ObjectIdentifier(
        session
      )

    registryLock.lock()

    defer {
      registryLock.unlock()
    }

    if let existingLock =
      sessionLocks[
        identifier
      ]
    {
      return existingLock
    }

    let newLock =
      NSRecursiveLock()

    newLock.name =
      "com.theandreyzakharov.webcamera.capture-session.\(identifier)"

    sessionLocks[
      identifier
    ] = newLock

    return newLock
  }
}

struct VideoPreviewView:
  NSViewRepresentable
{
  let session: AVCaptureSession

  func makeNSView(
    context: Context
  ) -> CameraPreviewNSView {
    let view =
      CameraPreviewNSView()

    view.attach(
      session: session
    )

    return view
  }

  func updateNSView(
    _ nsView: CameraPreviewNSView,
    context: Context
  ) {
    nsView.attach(
      session: session
    )
  }

  static func dismantleNSView(
    _ nsView: CameraPreviewNSView,
    coordinator: Void
  ) {
    nsView.detachSession()
  }
}

final class CameraPreviewNSView:
  NSView
{
  let previewLayer =
    AVCaptureVideoPreviewLayer()

  override init(
    frame frameRect: NSRect
  ) {
    super.init(
      frame: frameRect
    )

    configure()
  }

  required init?(
    coder: NSCoder
  ) {
    super.init(
      coder: coder
    )

    configure()
  }

  override func layout() {
    super.layout()

    CATransaction.begin()

    CATransaction.setDisableActions(
      true
    )

    previewLayer.frame =
      bounds

    CATransaction.commit()
  }

  func attach(
    session: AVCaptureSession
  ) {
    guard
      previewLayer.session
        !== session
    else {
      return
    }

    /*
     Assigning AVCaptureVideoPreviewLayer.session internally
     changes the AVCaptureSession connection graph.

     It must never happen concurrently with startRunning(),
     stopRunning() or beginConfiguration()/commitConfiguration().
     */
    CaptureSessionGate.shared
      .withLock(
        for: session
      ) {
        CATransaction.begin()

        CATransaction.setDisableActions(
          true
        )

        previewLayer.session =
          session

        CATransaction.commit()
      }
  }

  func detachSession() {
    guard
      let currentSession =
        previewLayer.session
    else {
      return
    }

    /*
     Detaching the layer also changes the capture session graph,
     so it uses the same per-session lock as CameraController.
     */
    CaptureSessionGate.shared
      .withLock(
        for: currentSession
      ) {
        CATransaction.begin()

        CATransaction.setDisableActions(
          true
        )

        previewLayer.session =
          nil

        CATransaction.commit()
      }
  }

  private func configure() {
    wantsLayer = true

    layer?.backgroundColor =
      NSColor.black.cgColor

    previewLayer.videoGravity =
      .resizeAspect

    previewLayer.backgroundColor =
      NSColor.black.cgColor

    layer?.addSublayer(
      previewLayer
    )
  }
}

struct AndroidVideoPreviewView:
  NSViewRepresentable
{
  let pixelBuffer:
    CVPixelBuffer?

  func makeNSView(
    context: Context
  ) -> AndroidPixelBufferNSView {
    let view =
      AndroidPixelBufferNSView()

    view.display(
      pixelBuffer
    )

    return view
  }

  func updateNSView(
    _ nsView:
      AndroidPixelBufferNSView,
    context: Context
  ) {
    nsView.display(
      pixelBuffer
    )
  }
}

final class AndroidPixelBufferNSView:
  NSView
{
  private let imageContext =
    CIContext(
      options: [
        .cacheIntermediates:
          false,
      ]
    )

  override init(
    frame frameRect: NSRect
  ) {
    super.init(
      frame: frameRect
    )

    configure()
  }

  required init?(
    coder: NSCoder
  ) {
    super.init(
      coder: coder
    )

    configure()
  }

  func display(
    _ pixelBuffer:
      CVPixelBuffer?
  ) {
    guard let pixelBuffer else {
      layer?.contents = nil
      return
    }

    let image =
      CIImage(
        cvPixelBuffer:
          pixelBuffer
      )

    guard
      let cgImage =
        imageContext.createCGImage(
          image,
          from: image.extent
        )
    else {
      return
    }

    CATransaction.begin()

    CATransaction.setDisableActions(
      true
    )

    layer?.contents =
      cgImage

    CATransaction.commit()
  }

  private func configure() {
    wantsLayer = true

    layer?.backgroundColor =
      NSColor.black.cgColor

    layer?.contentsGravity =
      .resizeAspect

    layer?.masksToBounds =
      true
  }
}
