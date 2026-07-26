import CoreGraphics
import Foundation

private struct DisplayTransferTable {
  let displayID: CGDirectDisplayID
  let red: [CGGammaValue]
  let green: [CGGammaValue]
  let blue: [CGGammaValue]
}

private enum RedScreenError: LocalizedError {
  case displayEnumeration(CGError)
  case gammaTableUnavailable(CGDirectDisplayID, CGError)
  case gammaTableEmpty(CGDirectDisplayID)
  case gammaUpdateFailed(CGDirectDisplayID, CGError)

  var errorDescription: String? {
    switch self {
    case let .displayEnumeration(error):
      return "Could not enumerate displays (Core Graphics \(error.rawValue))."
    case let .gammaTableUnavailable(displayID, error):
      return
        "Could not read display \(displayID) colors (Core Graphics \(error.rawValue))."
    case let .gammaTableEmpty(displayID):
      return "Display \(displayID) did not provide a color table."
    case let .gammaUpdateFailed(displayID, error):
      return
        "Could not tint display \(displayID) (Core Graphics \(error.rawValue))."
    }
  }
}

final class RedScreenController {
  static let shared = RedScreenController()

  // Keep enough green and blue to preserve detail while strongly suppressing
  // short-wavelength light. White maps to a deep red-orange instead of
  // flattening the whole desktop behind a translucent window.
  private let greenStrength: CGGammaValue = 0.16
  private let blueStrength: CGGammaValue = 0.035

  private var originalTables: [CGDirectDisplayID: DisplayTransferTable] = [:]
  private(set) var isEnabled = false

  private init() {}

  func toggle() throws -> Bool {
    if isEnabled {
      restore()
      return false
    }

    let displays = try activeDisplayIDs()
    var capturedTables: [CGDirectDisplayID: DisplayTransferTable] = [:]
    for displayID in displays {
      capturedTables[displayID] = try captureTable(for: displayID)
    }

    do {
      for displayID in displays {
        guard let table = capturedTables[displayID] else { continue }
        try applyRedTint(to: table)
      }
    } catch {
      restore(tables: capturedTables)
      throw error
    }

    originalTables = capturedTables
    isEnabled = true
    return true
  }

  func restore() {
    guard isEnabled || !originalTables.isEmpty else { return }
    restore(tables: originalTables)
    originalTables.removeAll()
    isEnabled = false
  }

  private func activeDisplayIDs() throws -> [CGDirectDisplayID] {
    var displayCount: UInt32 = 0
    let countResult = CGGetActiveDisplayList(0, nil, &displayCount)
    guard countResult == .success else {
      throw RedScreenError.displayEnumeration(countResult)
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
      throw RedScreenError.displayEnumeration(listResult)
    }
    return Array(displays.prefix(Int(displayCount)))
  }

  private func captureTable(
    for displayID: CGDirectDisplayID
  ) throws -> DisplayTransferTable {
    let capacity = CGDisplayGammaTableCapacity(displayID)
    guard capacity > 0 else {
      throw RedScreenError.gammaTableEmpty(displayID)
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
      throw RedScreenError.gammaTableUnavailable(displayID, result)
    }
    guard sampleCount > 0 else {
      throw RedScreenError.gammaTableEmpty(displayID)
    }

    return DisplayTransferTable(
      displayID: displayID,
      red: Array(red.prefix(Int(sampleCount))),
      green: Array(green.prefix(Int(sampleCount))),
      blue: Array(blue.prefix(Int(sampleCount)))
    )
  }

  private func applyRedTint(to table: DisplayTransferTable) throws {
    let green = table.green.map { min(1, max(0, $0 * greenStrength)) }
    let blue = table.blue.map { min(1, max(0, $0 * blueStrength)) }
    let result = setTable(
      displayID: table.displayID,
      red: table.red,
      green: green,
      blue: blue
    )
    guard result == .success else {
      throw RedScreenError.gammaUpdateFailed(table.displayID, result)
    }
  }

  private func restore(
    tables: [CGDirectDisplayID: DisplayTransferTable]
  ) {
    var restorationFailed = false
    for table in tables.values {
      if setTable(
        displayID: table.displayID,
        red: table.red,
        green: table.green,
        blue: table.blue
      ) != .success {
        restorationFailed = true
      }
    }
    if restorationFailed {
      CGDisplayRestoreColorSyncSettings()
    }
  }

  private func setTable(
    displayID: CGDirectDisplayID,
    red: [CGGammaValue],
    green: [CGGammaValue],
    blue: [CGGammaValue]
  ) -> CGError {
    let sampleCount = UInt32(
      min(red.count, min(green.count, blue.count))
    )
    guard sampleCount > 0 else { return .failure }

    return red.withUnsafeBufferPointer { redBuffer in
      green.withUnsafeBufferPointer { greenBuffer in
        blue.withUnsafeBufferPointer { blueBuffer in
          CGSetDisplayTransferByTable(
            displayID,
            sampleCount,
            redBuffer.baseAddress,
            greenBuffer.baseAddress,
            blueBuffer.baseAddress
          )
        }
      }
    }
  }
}
