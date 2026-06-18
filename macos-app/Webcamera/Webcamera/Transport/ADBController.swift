import Foundation

final class ADBController {
  enum ADBError: LocalizedError {
    case executableNotFound
    case commandFailed(
      arguments: [String],
      output: String
    )
    case deviceNotFound(String)

    var errorDescription: String? {
      switch self {
      case .executableNotFound:
        return """
        adb was not found. Install Android Platform Tools or \
        configure the adb executable path.
        """

      case let .commandFailed(arguments, output):
        return """
        adb \(arguments.joined(separator: " ")) failed:
        \(output)
        """

      case let .deviceNotFound(identifier):
        return """
        Android device \(identifier) is no longer connected.
        """
      }
    }
  }

  struct Device:
    Identifiable,
    Hashable,
    Sendable
  {
    let id: String
    let model: String
    let product: String
    let deviceName: String

    var displayName: String {
      if !model.isEmpty {
        return model
      }

      if !deviceName.isEmpty {
        return deviceName
      }

      return id
    }
  }

  struct CommandResult: Sendable {
    let standardOutput: String
    let standardError: String
    let terminationStatus: Int32

    var combinedOutput: String {
      [standardOutput, standardError]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }
  }

  private let executableURL: URL

  init(
    executableURL: URL? = nil
  ) {
    self.executableURL =
      executableURL
      ?? Self.findADBExecutable()
      ?? URL(
        fileURLWithPath:
          "/opt/homebrew/bin/adb"
      )
  }

  func connectedDevices() async throws
    -> [Device]
  {
    let result =
      try await run([
        "devices",
        "-l",
      ])

    guard result.terminationStatus == 0 else {
      throw ADBError.commandFailed(
        arguments: [
          "devices",
          "-l",
        ],
        output:
          result.combinedOutput
      )
    }

    return parseDevices(
      result.standardOutput
    )
  }

  func ensureDeviceConnected(
    _ identifier: String
  ) async throws {
    let devices =
      try await connectedDevices()

    guard
      devices.contains(
        where: {
          $0.id == identifier
        }
      )
    else {
      throw
        ADBError.deviceNotFound(
          identifier
        )
    }
  }

  func forward(
    deviceID: String,
    localPort: UInt16,
    remotePort: UInt16
  ) async throws {
    try await ensureDeviceConnected(
      deviceID
    )

    let result =
      try await run([
        "-s",
        deviceID,
        "forward",
        "tcp:\(localPort)",
        "tcp:\(remotePort)",
      ])

    guard result.terminationStatus == 0 else {
      throw ADBError.commandFailed(
        arguments: [
          "-s",
          deviceID,
          "forward",
          "tcp:\(localPort)",
          "tcp:\(remotePort)",
        ],
        output:
          result.combinedOutput
      )
    }
  }

  func removeForward(
    deviceID: String,
    localPort: UInt16
  ) async {
    _ = try? await run([
      "-s",
      deviceID,
      "forward",
      "--remove",
      "tcp:\(localPort)",
    ])
  }

  func startAndroidApplication(
    deviceID: String
  ) async throws {
    let result =
      try await run([
        "-s",
        deviceID,
        "shell",
        "am",
        "start",
        "-n",
        "com.theandreyzakharov.webcamera.debug/com.theandreyzakharov.webcamera.ui.MainActivity",
      ])

    guard result.terminationStatus == 0 else {
      throw ADBError.commandFailed(
        arguments: [
          "-s",
          deviceID,
          "shell",
          "am",
          "start",
        ],
        output:
          result.combinedOutput
      )
    }
  }

  func startAndroidService(
    deviceID: String
  ) async throws {
    let result =
      try await run([
        "-s",
        deviceID,
        "shell",
        "am",
        "startservice",
        "-n",
        "com.theandreyzakharov.webcamera.debug/com.theandreyzakharov.webcamera.service.CameraService",
        "-a",
        "com.theandreyzakharov.webcamera.START_SERVICE",
      ])

    guard result.terminationStatus == 0 else {
      throw ADBError.commandFailed(
        arguments: [
          "-s",
          deviceID,
          "shell",
          "am",
          "startservice",
        ],
        output:
          result.combinedOutput
      )
    }
  }

  private func run(
    _ arguments: [String]
  ) async throws -> CommandResult {
    let executableURL =
      executableURL

    guard
      FileManager.default
        .isExecutableFile(
          atPath:
            executableURL.path
        )
    else {
      throw ADBError.executableNotFound
    }

    return try await withCheckedThrowingContinuation {
      continuation in

      let process = Process()
      let standardOutput = Pipe()
      let standardError = Pipe()

      process.executableURL =
        executableURL

      process.arguments =
        arguments

      process.standardOutput =
        standardOutput

      process.standardError =
        standardError

      process.environment =
        Self.environment()

      process.terminationHandler = {
        terminatedProcess in

        let outputData =
          standardOutput
          .fileHandleForReading
          .readDataToEndOfFile()

        let errorData =
          standardError
          .fileHandleForReading
          .readDataToEndOfFile()

        let result =
          CommandResult(
            standardOutput:
              String(
                data: outputData,
                encoding: .utf8
              ) ?? "",
            standardError:
              String(
                data: errorData,
                encoding: .utf8
              ) ?? "",
            terminationStatus:
              terminatedProcess
              .terminationStatus
          )

        continuation.resume(
          returning: result
        )
      }

      do {
        try process.run()
      } catch {
        continuation.resume(
          throwing: error
        )
      }
    }
  }

  private func parseDevices(
    _ output: String
  ) -> [Device] {
    output
      .split(
        whereSeparator:
          \.isNewline
      )
      .dropFirst()
      .compactMap { rawLine in
        let line =
          rawLine.trimmingCharacters(
            in: .whitespacesAndNewlines
          )

        guard !line.isEmpty else {
          return nil
        }

        let components =
          line.split(
            whereSeparator:
              \.isWhitespace
          )

        guard components.count >= 2 else {
          return nil
        }

        let identifier =
          String(components[0])

        let state =
          String(components[1])

        guard state == "device" else {
          return nil
        }

        var properties:
          [String: String] = [:]

        for component in components.dropFirst(2) {
          let value =
            String(component)

          guard
            let separator =
              value.firstIndex(
                of: ":"
              )
          else {
            continue
          }

          let key =
            String(
              value[
                ..<separator
              ]
            )

          let propertyValue =
            String(
              value[
                value.index(
                  after: separator
                )...
              ]
            )

          properties[key] =
            propertyValue
        }

        return Device(
          id: identifier,
          model:
            properties["model"]?
            .replacingOccurrences(
              of: "_",
              with: " "
            ) ?? "",
          product:
            properties["product"]
            ?? "",
          deviceName:
            properties["device"]
            ?? ""
        )
      }
  }

  private static func findADBExecutable()
    -> URL?
  {
    let candidates = [
      "/opt/homebrew/bin/adb",
      "/usr/local/bin/adb",
      NSHomeDirectory()
        + "/Library/Android/sdk/platform-tools/adb",
      NSHomeDirectory()
        + "/Android/Sdk/platform-tools/adb",
    ]

    return candidates
      .first {
        FileManager.default
          .isExecutableFile(
            atPath: $0
          )
      }
      .map {
        URL(
          fileURLWithPath: $0
        )
      }
  }

  private static func environment()
    -> [String: String]
  {
    var environment =
      ProcessInfo.processInfo
      .environment

    environment["ADB_LIBUSB"] =
      "0"

    let additionalPaths = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      NSHomeDirectory()
        + "/Library/Android/sdk/platform-tools",
    ]

    let currentPath =
      environment["PATH"]
      ?? "/usr/bin:/bin:/usr/sbin:/sbin"

    environment["PATH"] =
      (
        additionalPaths
        + [currentPath]
      )
      .joined(separator: ":")

    return environment
  }
}
