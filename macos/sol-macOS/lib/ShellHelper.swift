import Cocoa
import Foundation

private enum ShellOutputCompletion {
  case append(String)
  case replace(String)
  case none
}

private struct ShellOutputAccumulator {
  private static let toastKey = "_sol_toast"

  private(set) var fullOutput = ""
  private var holdsPossibleJSON = true

  mutating func consume(_ text: String) -> String? {
    fullOutput += text

    guard holdsPossibleJSON else { return text }
    guard let firstCharacter = fullOutput.first(where: { !$0.isWhitespace }) else {
      return nil
    }
    guard firstCharacter == "{" else {
      holdsPossibleJSON = false
      return fullOutput
    }
    return nil
  }

  func completion(commandName: String?) -> ShellOutputCompletion {
    if let toastMessage = Self.toastMessage(from: fullOutput) {
      let normalizedName = commandName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let message = normalizedName.isEmpty
        ? toastMessage
        : "\(normalizedName) : \(toastMessage)"
      return .replace(message)
    }
    if holdsPossibleJSON, !fullOutput.isEmpty {
      return .append(fullOutput)
    }
    return .none
  }

  private static func toastMessage(from output: String) -> String? {
    let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = trimmedOutput.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any],
      let value = dictionary[toastKey]
    else {
      return nil
    }

    if let string = value as? String {
      return string
    }
    if value is NSNull {
      return "null"
    }
    if let number = value as? NSNumber {
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return number.boolValue ? "true" : "false"
      }
      return number.stringValue
    }
    guard JSONSerialization.isValidJSONObject(value),
      let encoded = try? JSONSerialization.data(
        withJSONObject: value,
        options: [.prettyPrinted, .sortedKeys]
      )
    else {
      return String(describing: value)
    }
    return String(data: encoded, encoding: .utf8) ?? String(describing: value)
  }
}

struct ShellHelper {
  static func shWithFloatingPanel(
    _ command: String,
    arguments: [String] = [],
    commandName: String? = nil
  ) {
    let task = Process()
    let pipe = Pipe()
    let outputQueue = DispatchQueue(label: "com.ospfranco.sol.shell-output")
    let activeReads = DispatchGroup()
    var output = ShellOutputAccumulator()

    task.standardOutput = pipe
    task.standardError = pipe
    if arguments.isEmpty {
      task.arguments = ["-l", "-c", command]
    } else {
      // zsh treats the value after the command as $0, so the remaining Process
      // arguments become $1, $2, … without ever being interpolated as shell code.
      task.arguments = ["-l", "-c", command, "sol-script"] + arguments
    }
    task.launchPath = "/bin/zsh"
    task.standardInput = nil

    if Thread.isMainThread {
      ToastManager.shared.showShellOutput()
    } else {
      DispatchQueue.main.sync {
        ToastManager.shared.showShellOutput()
      }
    }

    let fileHandle = pipe.fileHandleForReading
    fileHandle.readabilityHandler = { handle in
      activeReads.enter()
      let data = handle.availableData
      guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
        activeReads.leave()
        return
      }
      outputQueue.async {
        if let visibleOutput = output.consume(text) {
          DispatchQueue.main.async {
            ToastManager.shared.appendShellOutput(visibleOutput)
          }
        }
        activeReads.leave()
      }
    }

    task.terminationHandler = { process in
      fileHandle.readabilityHandler = nil
      activeReads.wait()
      let remainingData = fileHandle.readDataToEndOfFile()
      let remainingOutput = String(data: remainingData, encoding: .utf8) ?? ""

      outputQueue.async {
        let visibleRemainder = remainingOutput.isEmpty
          ? nil
          : output.consume(remainingOutput)
        let completion = output.completion(commandName: commandName)

        DispatchQueue.main.async {
          if let visibleRemainder {
            ToastManager.shared.appendShellOutput(visibleRemainder)
          }
          switch completion {
          case let .append(text):
            ToastManager.shared.appendShellOutput(text)
          case let .replace(text):
            ToastManager.shared.replaceShellOutput(text)
          case .none:
            break
          }

          if process.terminationStatus == 0 {
            ToastManager.shared.setShellSuccessStyle()
          } else {
            ToastManager.shared.setShellFailedStyle()
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            ToastManager.shared.closeShellOutput()
          }
        }
      }
    }

    task.launch()
  }
}
