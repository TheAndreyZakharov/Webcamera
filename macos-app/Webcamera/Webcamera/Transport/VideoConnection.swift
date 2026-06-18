import CoreMedia
import Foundation
import Network

final class VideoConnection:
  @unchecked Sendable
{
  enum State:
    Equatable,
    Sendable
  {
    case disconnected
    case connecting
    case connected
    case failed(String)
  }

  enum PacketType:
    UInt8,
    Sendable
  {
    case videoConfiguration = 1
    case videoFrame = 2
    case audioConfiguration = 3
    case audioFrame = 4
    case endOfStream = 5
  }

  struct Packet:
    Sendable
  {
    let version: UInt8
    let type: PacketType
    let flags: UInt16
    let sequence: UInt64
    let presentationTimestamp:
      CMTime
    let decodeTimestamp:
      CMTime
    let payload: Data

    var isCodecConfiguration: Bool {
      flags & 0x0002 != 0
    }

    var isKeyFrame: Bool {
      flags & 0x0001 != 0
    }
  }

  enum ConnectionError:
    LocalizedError
  {
    case invalidPort
    case connectionClosed
    case invalidMagic
    case unsupportedVersion(UInt8)
    case unknownPacketType(UInt8)
    case payloadTooLarge(Int)

    var errorDescription: String? {
      switch self {
      case .invalidPort:
        return "The video port is invalid."

      case .connectionClosed:
        return "The Android video connection was closed."

      case .invalidMagic:
        return "The Android video stream has an invalid WBCM header."

      case let .unsupportedVersion(version):
        return "Unsupported video protocol version: \(version)."

      case let .unknownPacketType(type):
        return "Unknown WBCM packet type: \(type)."

      case let .payloadTooLarge(size):
        return "The WBCM payload is too large: \(size) bytes."
      }
    }
  }

  private static let headerSize = 36
  private static let maximumPayloadSize =
    32 * 1024 * 1024

  private(set) var state:
    State = .disconnected
  {
    didSet {
      onStateChange?(state)
    }
  }

  var onStateChange:
    ((State) -> Void)?

  var onPacket:
    ((Packet) -> Void)?

  private let queue =
    DispatchQueue(
      label:
        "com.theandreyzakharov.webcamera.video",
      qos: .userInteractive
    )

  private var connection:
    NWConnection?

  private var receiveBuffer =
    Data()

  func connect(
    host: String,
    port: UInt16
  ) {
    disconnect()

    guard
      let networkPort =
        NWEndpoint.Port(
          rawValue: port
        )
    else {
      state =
        .failed(
          ConnectionError
            .invalidPort
            .localizedDescription
        )

      return
    }

    state = .connecting

    let connection =
      NWConnection(
        host:
          NWEndpoint.Host(host),
        port:
          networkPort,
        using: .tcp
      )

    self.connection =
      connection

    connection.stateUpdateHandler = {
      [weak self, weak connection]
      newState in

      guard
        let self,
        connection === self.connection
      else {
        return
      }

      self.queue.async {
        self.handleConnectionState(
          newState
        )
      }
    }

    connection.start(
      queue: queue
    )
  }

  func disconnect() {
    let oldConnection =
      connection

    connection = nil
    receiveBuffer.removeAll(
      keepingCapacity: false
    )

    oldConnection?
      .stateUpdateHandler = nil

    oldConnection?.cancel()

    state = .disconnected
  }

  private func handleConnectionState(
    _ newState:
      NWConnection.State
  ) {
    switch newState {
    case .setup, .preparing:
      state = .connecting

    case .ready:
      state = .connected
      receiveNextChunk()

    case let .waiting(error):
      state =
        .failed(
          error.localizedDescription
        )

    case let .failed(error):
      state =
        .failed(
          error.localizedDescription
        )

    case .cancelled:
      state = .disconnected

    @unknown default:
      state =
        .failed(
          "Unknown Network.framework state."
        )
    }
  }

  private func receiveNextChunk() {
    guard
      let connection
    else {
      return
    }

    connection.receive(
      minimumIncompleteLength: 1,
      maximumLength:
        256 * 1024
    ) {
      [weak self, weak connection]
      content,
      _,
      isComplete,
      error in

      guard
        let self,
        connection === self.connection
      else {
        return
      }

      self.queue.async {
        if let content,
          !content.isEmpty
        {
          self.receiveBuffer.append(
            content
          )

          do {
            try self.processPackets()
          } catch {
            self.state =
              .failed(
                error.localizedDescription
              )

            self.connection?
              .cancel()

            return
          }
        }

        if let error {
          self.state =
            .failed(
              error.localizedDescription
            )

          return
        }

        if isComplete {
          self.state =
            .failed(
              ConnectionError
                .connectionClosed
                .localizedDescription
            )

          return
        }

        self.receiveNextChunk()
      }
    }
  }

  private func processPackets()
    throws
  {
    while receiveBuffer.count
      >= Self.headerSize
    {
      let magic =
        receiveBuffer.subdata(
          in: 0..<4
        )

      guard
        magic == Data([
          0x57,
          0x42,
          0x43,
          0x4D,
        ])
      else {
        throw
          ConnectionError
          .invalidMagic
      }

      let version =
        receiveBuffer[4]

      guard version == 1 else {
        throw
          ConnectionError
          .unsupportedVersion(
            version
          )
      }

      let rawType =
        receiveBuffer[5]

      guard
        let packetType =
          PacketType(
            rawValue: rawType
          )
      else {
        throw
          ConnectionError
          .unknownPacketType(
            rawType
          )
      }

      let flags =
        receiveBuffer.readUInt16BE(
          at: 6
        )

      let sequence =
        receiveBuffer.readUInt64BE(
          at: 8
        )

      let presentationTimeUs =
        receiveBuffer.readUInt64BE(
          at: 16
        )

      let decodeTimeUs =
        receiveBuffer.readUInt64BE(
          at: 24
        )

      let payloadSize =
        Int(
          receiveBuffer.readUInt32BE(
            at: 32
          )
        )

      guard
        payloadSize >= 0,
        payloadSize
          <= Self.maximumPayloadSize
      else {
        throw
          ConnectionError
          .payloadTooLarge(
            payloadSize
          )
      }

      let packetSize =
        Self.headerSize
        + payloadSize

      guard receiveBuffer.count
        >= packetSize
      else {
        return
      }

      let payload =
        receiveBuffer.subdata(
          in:
            Self.headerSize
            ..< packetSize
        )

      receiveBuffer.removeSubrange(
        0..<packetSize
      )

      let packet =
        Packet(
          version: version,
          type: packetType,
          flags: flags,
          sequence: sequence,
          presentationTimestamp:
            CMTime(
              value:
                clampedTimeValue(
                  presentationTimeUs
                ),
              timescale:
                1_000_000
            ),
          decodeTimestamp:
            CMTime(
              value:
                clampedTimeValue(
                  decodeTimeUs
                ),
              timescale:
                1_000_000
            ),
          payload: payload
        )

      onPacket?(packet)
    }
  }

  private func clampedTimeValue(
    _ value: UInt64
  ) -> CMTimeValue {
    if value
      > UInt64(Int64.max)
    {
      return Int64.max
    }

    return Int64(value)
  }
}

private extension Data {
  func readUInt16BE(
    at offset: Int
  ) -> UInt16 {
    let first =
      UInt16(self[offset])

    let second =
      UInt16(self[offset + 1])

    return
      (first << 8)
      | second
  }

  func readUInt32BE(
    at offset: Int
  ) -> UInt32 {
    var result: UInt32 = 0

    for index in 0..<4 {
      result =
        (result << 8)
        | UInt32(
          self[offset + index]
        )
    }

    return result
  }

  func readUInt64BE(
    at offset: Int
  ) -> UInt64 {
    var result: UInt64 = 0

    for index in 0..<8 {
      result =
        (result << 8)
        | UInt64(
          self[offset + index]
        )
    }

    return result
  }
}
