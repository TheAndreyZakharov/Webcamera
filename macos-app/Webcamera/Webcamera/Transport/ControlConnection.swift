import Foundation

final class ControlConnection {
  enum State {
    case disconnected
    case connecting
    case connected
    case failed(String)
  }

  private(set) var state: State = .disconnected

  func connect(
    host: String,
    port: UInt16
  ) {
    state = .connecting
  }

  func disconnect() {
    state = .disconnected
  }
}
