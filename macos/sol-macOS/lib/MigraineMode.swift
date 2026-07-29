import AppKit
import CoreGraphics
import Foundation

private struct MigraineDisplayTable: Codable {
  let displayID: CGDirectDisplayID
  let red: [CGGammaValue]
  let green: [CGGammaValue]
  let blue: [CGGammaValue]
}

private struct MigraineAudioState: Codable {
  let outputVolume: Int
  let alertVolume: Int
  let outputMuted: Bool
}

private struct MigraineBooleanPreference: Codable {
  let key: String
  let existed: Bool
  let value: Bool
}

private struct MigraineModeSnapshot: Codable {
  let darkModeEnabled: Bool
  let backgroundSoundsEnabled: Bool
  let audio: MigraineAudioState?
  let accessibilityPreferences: [MigraineBooleanPreference]
  let displayTables: [MigraineDisplayTable]
}

private enum MigraineModeError: LocalizedError {
  case displayEnumeration(CGError)
  case displayTableUnavailable(CGDirectDisplayID, CGError)
  case displayTableEmpty(CGDirectDisplayID)
  case displayUpdateFailed(CGDirectDisplayID, CGError)
  case appleScript(String)
  case preferenceUpdate
  case snapshotEncoding

  var errorDescription: String? {
    switch self {
    case let .displayEnumeration(error):
      return "Could not enumerate displays (Core Graphics \(error.rawValue))."
    case let .displayTableUnavailable(displayID, error):
      return
        "Could not read display \(displayID) colors (Core Graphics \(error.rawValue))."
    case let .displayTableEmpty(displayID):
      return "Display \(displayID) did not provide a color table."
    case let .displayUpdateFailed(displayID, error):
      return
        "Could not update display \(displayID) colors (Core Graphics \(error.rawValue))."
    case let .appleScript(message):
      return message
    case .preferenceUpdate:
      return "macOS did not accept the accessibility preference changes."
    case .snapshotEncoding:
      return "Sol could not save the settings needed to restore migraine mode."
    }
  }
}

final class MigraineModeController {
  static let shared = MigraineModeController()

  private let snapshotKey = "MigraineModeSnapshotV1"
  private let accessibilityDomain = "com.apple.universalaccess" as CFString
  private let accessibilityKeys = [
    "reduceMotion",
    "reduceTransparency",
  ]

  // The profile lowers total luminance while shifting white toward amber.
  // It is deliberately based on the current transfer table so disabling the
  // mode restores color calibration, Night Shift, or an existing red filter.
  private let redStrength: CGGammaValue = 0.48
  private let greenStrength: CGGammaValue = 0.34
  private let blueStrength: CGGammaValue = 0.20

  private var activeSnapshot: MigraineModeSnapshot? = nil

  var isEnabled: Bool {
    activeSnapshot != nil
  }

  private init() {
    activeSnapshot = loadSnapshot()
  }

  func toggle() -> [String: Any] {
    if let snapshot = activeSnapshot {
      return disable(snapshot)
    }
    return enable()
  }

  func resumeIfNeeded() {
    guard let snapshot = activeSnapshot else { return }
    var warnings: [String] = []
    _ = apply(snapshot, warnings: &warnings)
  }

  private func enable() -> [String: Any] {
    var warnings: [String] = []
    let audio = captureAudio(warnings: &warnings)
    let displays = captureDisplays(warnings: &warnings)
    let preferences = accessibilityKeys.map(captureAccessibilityPreference)
    let snapshot = MigraineModeSnapshot(
      darkModeEnabled: DarkMode.isEnabled,
      backgroundSoundsEnabled: BackgroundSoundsController.shared.isEnabled,
      audio: audio,
      accessibilityPreferences: preferences,
      displayTables: displays
    )

    do {
      try saveSnapshot(snapshot)
    } catch {
      return result(
        enabled: false,
        applied: [],
        warnings: [error.localizedDescription]
      )
    }

    let applied = apply(snapshot, warnings: &warnings)
    return result(enabled: true, applied: applied, warnings: warnings)
  }

  private func disable(_ snapshot: MigraineModeSnapshot) -> [String: Any] {
    var warnings: [String] = []
    var restored: [String] = []

    if restoreDisplays(snapshot.displayTables, warnings: &warnings) {
      restored.append("display")
    }
    if restoreAccessibilityPreferences(
      snapshot.accessibilityPreferences,
      warnings: &warnings
    ) {
      restored.append("accessibility")
    }

    do {
      _ = try BackgroundSoundsController.shared.setEnabled(
        snapshot.backgroundSoundsEnabled
      )
      restored.append("background sounds")
    } catch {
      warnings.append("Background sounds: \(error.localizedDescription)")
    }

    if let audio = snapshot.audio {
      do {
        try restoreAudio(audio)
        restored.append("sound")
      } catch {
        warnings.append("Sound: \(error.localizedDescription)")
      }
    }

    DarkMode.isEnabled = snapshot.darkModeEnabled
    restored.append("appearance")

    clearSnapshot()
    return result(enabled: false, applied: restored, warnings: warnings)
  }

  private func apply(
    _ snapshot: MigraineModeSnapshot,
    warnings: inout [String]
  ) -> [String] {
    var applied: [String] = []

    DarkMode.isEnabled = true
    applied.append("dark appearance")

    if applyAccessibilityPreferences(warnings: &warnings) {
      applied.append("reduced motion and transparency")
    }
    if applyDisplayProfile(snapshot.displayTables, warnings: &warnings) {
      applied.append("dim warm display")
    }

    if snapshot.audio != nil {
      do {
        try silenceAudio()
        applied.append("muted sound and alerts")
      } catch {
        warnings.append("Sound: \(error.localizedDescription)")
      }
    }

    do {
      _ = try BackgroundSoundsController.shared.setEnabled(false)
      applied.append("background sounds off")
    } catch {
      warnings.append("Background sounds: \(error.localizedDescription)")
    }

    applied.append("Sol animations off")
    return applied
  }

  private func result(
    enabled: Bool,
    applied: [String],
    warnings: [String]
  ) -> [String: Any] {
    [
      "enabled": enabled,
      "applied": applied,
      "warnings": warnings,
    ]
  }

  private func saveSnapshot(_ snapshot: MigraineModeSnapshot) throws {
    guard let data = try? JSONEncoder().encode(snapshot) else {
      throw MigraineModeError.snapshotEncoding
    }
    UserDefaults.standard.set(data, forKey: snapshotKey)
    activeSnapshot = snapshot
  }

  private func loadSnapshot() -> MigraineModeSnapshot? {
    guard let data = UserDefaults.standard.data(forKey: snapshotKey) else {
      return nil
    }
    return try? JSONDecoder().decode(MigraineModeSnapshot.self, from: data)
  }

  private func clearSnapshot() {
    UserDefaults.standard.removeObject(forKey: snapshotKey)
    activeSnapshot = nil
  }

  private func captureDisplays(
    warnings: inout [String]
  ) -> [MigraineDisplayTable] {
    let displayIDs: [CGDirectDisplayID]
    do {
      displayIDs = try activeDisplayIDs()
    } catch {
      warnings.append("Display: \(error.localizedDescription)")
      return []
    }

    return displayIDs.compactMap { displayID in
      do {
        return try captureDisplayTable(displayID)
      } catch {
        warnings.append("Display: \(error.localizedDescription)")
        return nil
      }
    }
  }

  private func activeDisplayIDs() throws -> [CGDirectDisplayID] {
    var displayCount: UInt32 = 0
    let countResult = CGGetActiveDisplayList(0, nil, &displayCount)
    guard countResult == .success else {
      throw MigraineModeError.displayEnumeration(countResult)
    }
    guard displayCount > 0 else { return [] }

    var displays = Array(
      repeating: CGDirectDisplayID(),
      count: Int(displayCount)
    )
    let listResult = displays.withUnsafeMutableBufferPointer { buffer in
      CGGetActiveDisplayList(displayCount, buffer.baseAddress, &displayCount)
    }
    guard listResult == .success else {
      throw MigraineModeError.displayEnumeration(listResult)
    }
    return Array(displays.prefix(Int(displayCount)))
  }

  private func captureDisplayTable(
    _ displayID: CGDirectDisplayID
  ) throws -> MigraineDisplayTable {
    let capacity = CGDisplayGammaTableCapacity(displayID)
    guard capacity > 0 else {
      throw MigraineModeError.displayTableEmpty(displayID)
    }

    var red = Array(repeating: CGGammaValue(0), count: Int(capacity))
    var green = Array(repeating: CGGammaValue(0), count: Int(capacity))
    var blue = Array(repeating: CGGammaValue(0), count: Int(capacity))
    var sampleCount: UInt32 = 0
    let result = red.withUnsafeMutableBufferPointer { redBuffer in
      green.withUnsafeMutableBufferPointer { greenBuffer in
        blue.withUnsafeMutableBufferPointer { blueBuffer in
          CGGetDisplayTransferByTable(
            displayID,
            capacity,
            redBuffer.baseAddress,
            greenBuffer.baseAddress,
            blueBuffer.baseAddress,
            &sampleCount
          )
        }
      }
    }

    guard result == .success else {
      throw MigraineModeError.displayTableUnavailable(displayID, result)
    }
    guard sampleCount > 0 else {
      throw MigraineModeError.displayTableEmpty(displayID)
    }

    return MigraineDisplayTable(
      displayID: displayID,
      red: Array(red.prefix(Int(sampleCount))),
      green: Array(green.prefix(Int(sampleCount))),
      blue: Array(blue.prefix(Int(sampleCount)))
    )
  }

  private func applyDisplayProfile(
    _ tables: [MigraineDisplayTable],
    warnings: inout [String]
  ) -> Bool {
    var changed = false
    for table in tables {
      do {
        try setDisplayTable(
          table,
          red: table.red.map { min(1, max(0, $0 * redStrength)) },
          green: table.green.map {
            min(1, max(0, $0 * greenStrength))
          },
          blue: table.blue.map { min(1, max(0, $0 * blueStrength)) }
        )
        changed = true
      } catch {
        warnings.append("Display: \(error.localizedDescription)")
      }
    }
    return changed
  }

  private func restoreDisplays(
    _ tables: [MigraineDisplayTable],
    warnings: inout [String]
  ) -> Bool {
    var restored = false
    for table in tables {
      do {
        try setDisplayTable(
          table,
          red: table.red,
          green: table.green,
          blue: table.blue
        )
        restored = true
      } catch {
        warnings.append("Display: \(error.localizedDescription)")
      }
    }
    return restored
  }

  private func setDisplayTable(
    _ table: MigraineDisplayTable,
    red: [CGGammaValue],
    green: [CGGammaValue],
    blue: [CGGammaValue]
  ) throws {
    let sampleCount = UInt32(
      min(red.count, min(green.count, blue.count))
    )
    guard sampleCount > 0 else {
      throw MigraineModeError.displayTableEmpty(table.displayID)
    }

    let result = red.withUnsafeBufferPointer { redBuffer in
      green.withUnsafeBufferPointer { greenBuffer in
        blue.withUnsafeBufferPointer { blueBuffer in
          CGSetDisplayTransferByTable(
            table.displayID,
            sampleCount,
            redBuffer.baseAddress,
            greenBuffer.baseAddress,
            blueBuffer.baseAddress
          )
        }
      }
    }
    guard result == .success else {
      throw MigraineModeError.displayUpdateFailed(table.displayID, result)
    }
  }

  private func captureAudio(
    warnings: inout [String]
  ) -> MigraineAudioState? {
    do {
      return MigraineAudioState(
        outputVolume: Int(
          try executeAppleScript(
            "output volume of (get volume settings)"
          ).int32Value
        ),
        alertVolume: Int(
          try executeAppleScript(
            "alert volume of (get volume settings)"
          ).int32Value
        ),
        outputMuted: try executeAppleScript(
          "output muted of (get volume settings)"
        ).booleanValue
      )
    } catch {
      warnings.append("Sound: \(error.localizedDescription)")
      return nil
    }
  }

  private func silenceAudio() throws {
    _ = try executeAppleScript(
      """
      set volume alert volume 0
      set volume with output muted
      """
    )
  }

  private func restoreAudio(_ audio: MigraineAudioState) throws {
    let muteClause = audio.outputMuted ? "with" : "without"
    _ = try executeAppleScript(
      """
      set volume output volume \(audio.outputVolume)
      set volume alert volume \(audio.alertVolume)
      set volume \(muteClause) output muted
      """
    )
  }

  private func executeAppleScript(
    _ source: String
  ) throws -> NSAppleEventDescriptor {
    var details: NSDictionary?
    guard let script = NSAppleScript(source: source) else {
      throw MigraineModeError.appleScript(
        "macOS could not prepare the sound settings change."
      )
    }
    let output = script.executeAndReturnError(&details)
    if details != nil {
      let message =
        (details?[NSAppleScript.errorMessage] as? String)
        ?? "macOS could not change the sound settings."
      throw MigraineModeError.appleScript(message)
    }
    return output
  }

  private func captureAccessibilityPreference(
    _ key: String
  ) -> MigraineBooleanPreference {
    let rawValue = CFPreferencesCopyValue(
      key as CFString,
      accessibilityDomain,
      kCFPreferencesCurrentUser,
      kCFPreferencesAnyHost
    )
    return MigraineBooleanPreference(
      key: key,
      existed: rawValue != nil,
      value: (rawValue as? NSNumber)?.boolValue ?? false
    )
  }

  private func applyAccessibilityPreferences(
    warnings: inout [String]
  ) -> Bool {
    for key in accessibilityKeys {
      CFPreferencesSetValue(
        key as CFString,
        NSNumber(value: true),
        accessibilityDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
      )
    }
    guard synchronizeAccessibilityPreferences() else {
      warnings.append(MigraineModeError.preferenceUpdate.localizedDescription)
      return false
    }
    notifyAccessibilityPreferencesChanged()
    return true
  }

  private func restoreAccessibilityPreferences(
    _ preferences: [MigraineBooleanPreference],
    warnings: inout [String]
  ) -> Bool {
    for preference in preferences {
      CFPreferencesSetValue(
        preference.key as CFString,
        preference.existed ? NSNumber(value: preference.value) : nil,
        accessibilityDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
      )
    }
    guard synchronizeAccessibilityPreferences() else {
      warnings.append(MigraineModeError.preferenceUpdate.localizedDescription)
      return false
    }
    notifyAccessibilityPreferencesChanged()
    return true
  }

  private func synchronizeAccessibilityPreferences() -> Bool {
    CFPreferencesSynchronize(
      accessibilityDomain,
      kCFPreferencesCurrentUser,
      kCFPreferencesAnyHost
    )
  }

  private func notifyAccessibilityPreferencesChanged() {
    DistributedNotificationCenter.default().postNotificationName(
      NSNotification.Name("com.apple.accessibility.api"),
      object: nil,
      userInfo: nil,
      deliverImmediately: true
    )
    NSWorkspace.shared.notificationCenter.post(
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil
    )
  }
}
