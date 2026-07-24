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
    if arguments.isEmpty {
      task.arguments = ["-l", "-c", command]
    } else {
      // zsh treats the value after the command as $0, so the remaining Process
      // arguments become $1, $2, … without ever being interpolated as shell code.
      task.arguments = ["-l", "-c", command, "sol-script"] + arguments
    }
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.standardInput = nil

    do {
      try run(task, commandName: commandName, showOutput: true)
    } catch {
      // run(_:commandName:showOutput:) already presents launch failures.
    }
  }

  static func runScriptFile(
    _ path: String,
    arguments: [String] = [],
    commandName: String? = nil,
    showOutput: Bool = true
  ) throws {
    let scriptURL = URL(fileURLWithPath: path)
    let invocation = try scriptInvocation(for: scriptURL)
    let task = Process()

    // A login shell supplies the same user PATH as the rest of Sol, while the
    // fixed command and positional arguments keep paths and script arguments
    // out of shell interpolation.
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments =
      ["-l", "-c", "exec \"$@\"", "sol-script"] + invocation + arguments
    task.currentDirectoryURL = scriptURL.deletingLastPathComponent()
    task.standardInput = nil

    try run(task, commandName: commandName, showOutput: showOutput)
  }

  private static func scriptInvocation(for scriptURL: URL) throws -> [String] {
    let source = try String(contentsOf: scriptURL, encoding: .utf8)
    if let firstLine = source.split(
      separator: "\n",
      maxSplits: 1,
      omittingEmptySubsequences: false
    ).first {
      let line = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.hasPrefix("#!") {
        let shebang = String(line.dropFirst(2))
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let components = shebang.split(whereSeparator: \.isWhitespace).map(String.init)
        if !components.isEmpty {
          return components + [scriptURL.path]
        }
      }
    }

    let interpreter: [String] =
      switch scriptURL.pathExtension.lowercased() {
      case "bash":
        ["/bin/bash"]
      case "zsh", "sh", "command":
        ["/bin/zsh"]
      case "fish":
        ["/usr/bin/env", "fish"]
      case "py":
        ["/usr/bin/env", "python3"]
      case "rb":
        ["/usr/bin/env", "ruby"]
      case "js":
        ["/usr/bin/env", "node"]
      case "ts":
        ["/usr/bin/env", "tsx"]
      case "swift":
        ["/usr/bin/env", "swift"]
      case "pl":
        ["/usr/bin/env", "perl"]
      default:
        ["/bin/zsh"]
      }
    return interpreter + [scriptURL.path]
  }

  private static func run(
    _ task: Process,
    commandName: String?,
    showOutput: Bool
  ) throws {
    let pipe = Pipe()
    let outputQueue = DispatchQueue(label: "com.ospfranco.sol.shell-output")
    let activeReads = DispatchGroup()
    var output = ShellOutputAccumulator()

    task.standardOutput = pipe
    task.standardError = pipe

    if showOutput {
      if Thread.isMainThread {
        ToastManager.shared.showShellOutput()
      } else {
        DispatchQueue.main.sync {
          ToastManager.shared.showShellOutput()
        }
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
          if showOutput {
            DispatchQueue.main.async {
              ToastManager.shared.appendShellOutput(visibleOutput)
            }
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
          if !showOutput {
            if process.terminationStatus == 0 {
              if case let .replace(text) = completion {
                ToastManager.shared.showToast(
                  text,
                  variant: "success",
                  timeout: 5,
                  image: nil
                )
              }
              return
            }
            ToastManager.shared.showShellOutput()
            let failureOutput =
              output.fullOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            ToastManager.shared.replaceShellOutput(
              failureOutput.isEmpty
                ? "\(commandName ?? "Script") failed with exit code \(process.terminationStatus)."
                : failureOutput
            )
            ToastManager.shared.setShellFailedStyle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
              ToastManager.shared.closeShellOutput()
            }
            return
          }

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

    do {
      try task.run()
    } catch {
      fileHandle.readabilityHandler = nil
      DispatchQueue.main.async {
        if !showOutput {
          ToastManager.shared.showShellOutput()
        }
        ToastManager.shared.replaceShellOutput(
          "\(commandName ?? "Script") could not start: \(error.localizedDescription)"
        )
        ToastManager.shared.setShellFailedStyle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
          ToastManager.shared.closeShellOutput()
        }
      }
      throw error
    }
  }
}
