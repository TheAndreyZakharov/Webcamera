import Foundation
import Network

final class ControlConnection:
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

  enum ConnectionError:
    LocalizedError
  {
    case invalidPort
    case notConnected
    case invalidUTF8
    case invalidJSON
    case connectionClosed

    var errorDescription: String? {
      switch self {
      case .invalidPort:
        return "The control port is invalid."

      case .notConnected:
        return "The control connection is not active."

      case .invalidUTF8:
        return "The Android control response is not UTF-8."

      case .invalidJSON:
        return "The Android control response is not valid JSON."

      case .connectionClosed:
        return "The Android control connection was closed."
      }
    }
  }

  private(set) var state:
    State = .disconnected
  {
    didSet {
      onStateChange?(state)
    }
  }

  var onStateChange:
    ((State) -> Void)?

  var onMessage:
    (([String: Any]) -> Void)?

  private let queue =
    DispatchQueue(
      label:
        "com.theandreyzakharov.webcamera.control",
      qos: .userInitiated
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
    let previousConnection =
      connection

    connection = nil
    receiveBuffer.removeAll(
      keepingCapacity: false
    )

    previousConnection?
      .stateUpdateHandler = nil

    previousConnection?
      .cancel()

    state = .disconnected
  }

  func send(
    type: String,
    values: [String: Any] = [:],
    sequence: UInt64 =
      UInt64.random(
        in: 1...UInt64.max
      ),
    completion:
      ((Error?) -> Void)? = nil
  ) {
    var message = values

    message["version"] = 1
    message["type"] = type
    message["sequence"] = sequence
    message["timestamp"] =
      Int64(
        ProcessInfo.processInfo
          .systemUptime
        * 1000
      )

    send(
      jsonObject: message,
      completion: completion
    )
  }

  func send(
    jsonObject: [String: Any],
    completion:
      ((Error?) -> Void)? = nil
  ) {
    queue.async { [weak self] in
      guard
        let self,
        let connection =
          self.connection
      else {
        completion?(
          ConnectionError
            .notConnected
        )

        return
      }

      do {
        var data =
          try JSONSerialization.data(
            withJSONObject:
              jsonObject,
            options: []
          )

        data.append(0x0A)

        connection.send(
          content: data,
          completion:
            .contentProcessed {
              error in

              completion?(error)
            }
        )
      } catch {
        completion?(error)
      }
    }
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
        64 * 1024
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

          self.processLines()
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

  private func processLines() {
    while
      let newlineIndex =
        receiveBuffer.firstIndex(
          of: 0x0A
        )
    {
      let lineData =
        receiveBuffer.prefix(
          upTo: newlineIndex
        )

      receiveBuffer.removeSubrange(
        ...newlineIndex
      )

      guard !lineData.isEmpty else {
        continue
      }

      do {
        let object =
          try JSONSerialization
          .jsonObject(
            with: Data(lineData),
            options: []
          )

        guard
          let dictionary =
            object as?
              [String: Any]
        else {
          throw
            ConnectionError
            .invalidJSON
        }

        DispatchQueue.main.async {
          [weak self] in

          self?.onMessage?(
            dictionary
          )
        }
      } catch {
        state =
          .failed(
            error.localizedDescription
          )
      }
    }
  }
}
