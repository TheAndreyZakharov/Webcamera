import Foundation

final class ADBController {
  struct Device: Identifiable, Hashable {
    let id: String
    let model: String
    let product: String
  }

  func connectedDevices() async throws -> [Device] {
    []
  }
}
