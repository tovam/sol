import Foundation

private enum BackgroundSoundsError: LocalizedError {
  case preferencesUnavailable
  case daemonReloadFailed(Int32)

  var errorDescription: String? {
    switch self {
    case .preferencesUnavailable:
      return "macOS did not accept the Background Sounds preference change."
    case let .daemonReloadFailed(status):
      return "The Background Sounds service could not reload (exit \(status))."
    }
  }
}

final class BackgroundSoundsController {
  static let shared = BackgroundSoundsController()

  private let domain = "com.apple.ComfortSounds" as CFString
  private let enabledKey = "comfortSoundsEnabled" as CFString
  private let timestampKey = "lastEnablementTimestamp" as CFString

  private init() {}

  func toggle() throws -> Bool {
    CFPreferencesAppSynchronize(domain)
    let wasEnabled =
      (CFPreferencesCopyAppValue(enabledKey, domain) as? NSNumber)?.boolValue
      ?? false
    let isEnabled = !wasEnabled

    CFPreferencesSetAppValue(
      enabledKey,
      NSNumber(value: isEnabled),
      domain
    )
    if isEnabled {
      CFPreferencesSetAppValue(
        timestampKey,
        NSNumber(value: Date().timeIntervalSince1970),
        domain
      )
    }

    guard CFPreferencesAppSynchronize(domain) else {
      throw BackgroundSoundsError.preferencesUnavailable
    }

    do {
      try reloadDaemon()
      return isEnabled
    } catch {
      CFPreferencesSetAppValue(
        enabledKey,
        NSNumber(value: wasEnabled),
        domain
      )
      CFPreferencesAppSynchronize(domain)
      try? reloadDaemon()
      throw error
    }
  }

  private func reloadDaemon() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = [
      "kill",
      "SIGHUP",
      "gui/\(getuid())/com.apple.accessibility.heard",
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw BackgroundSoundsError.daemonReloadFailed(
        process.terminationStatus
      )
    }
  }
}
