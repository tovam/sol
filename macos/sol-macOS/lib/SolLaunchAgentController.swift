import Foundation

final class SolLaunchAgentController {
  static let shared = SolLaunchAgentController()

  private let jobLabel = "com.ospfranco.sol.watchdog"
  private let fileManager = FileManager.default
  private let stateLock = NSLock()
  private var restartRequested = false

  private var userID: uid_t {
    getuid()
  }

  private var launchDomain: String {
    "gui/\(userID)"
  }

  private var serviceTarget: String {
    "\(launchDomain)/\(jobLabel)"
  }

  private var configDirectory: URL {
    fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("sol", isDirectory: true)
  }

  private var runtimeDirectory: URL {
    configDirectory.appendingPathComponent("watchdog", isDirectory: true)
  }

  private var launchAgentsDirectory: URL {
    fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("LaunchAgents", isDirectory: true)
  }

  private var launchAgentURL: URL {
    launchAgentsDirectory.appendingPathComponent("\(jobLabel).plist")
  }

  private var watchdogScriptURL: URL {
    runtimeDirectory.appendingPathComponent("watch-sol.zsh")
  }

  private var processIDURL: URL {
    runtimeDirectory.appendingPathComponent("sol.pid")
  }

  private var intentionalQuitURL: URL {
    runtimeDirectory.appendingPathComponent("intentional-quit")
  }

  private init() {}

  func applicationDidStart() {
    do {
      try prepareRuntimeDirectory()
      try? fileManager.removeItem(at: intentionalQuitURL)
      try writeSecurely(
        Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8),
        to: processIDURL,
        permissions: 0o600
      )
    } catch {
      NSLog("Could not initialize the Sol watchdog state: \(error.localizedDescription)")
    }
  }

  func applicationWillTerminate() {
    stateLock.lock()
    let shouldRelaunch = restartRequested
    restartRequested = false
    stateLock.unlock()

    guard !shouldRelaunch, fileManager.fileExists(atPath: launchAgentURL.path) else {
      return
    }

    do {
      try prepareRuntimeDirectory()
      try writeSecurely(Data("quit\n".utf8), to: intentionalQuitURL, permissions: 0o600)
    } catch {
      NSLog("Could not notify the Sol watchdog of an intentional quit: \(error.localizedDescription)")
    }

    // Stop the watchdog before Sol exits. Relying on the watchdog to notice
    // the marker after the app has disappeared creates a race where it can
    // relaunch Sol after a deliberate Quit. Keep the plist installed so
    // launchd will load it again at the next login; opening Sol manually in
    // the current session also bootstraps it again from setEnabled(true).
    let status = launchctl(["bootout", serviceTarget])
    if status != 0 {
      NSLog("Could not stop the Sol watchdog after an intentional quit (\(status)); using the quit marker fallback.")
    }
  }

  func prepareForApplicationRestart() {
    stateLock.lock()
    restartRequested = true
    stateLock.unlock()
  }

  func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try installAndStart()
    } else {
      disableAndRemove()
    }
  }

  private func installAndStart() throws {
    try prepareRuntimeDirectory()
    try fileManager.createDirectory(
      at: launchAgentsDirectory,
      withIntermediateDirectories: true
    )

    let scriptData = Data(watchdogScript.utf8)
    let plistData = try PropertyListSerialization.data(
      fromPropertyList: launchAgentPropertyList,
      format: .xml,
      options: 0
    )
    let scriptChanged = try contentsDiffer(at: watchdogScriptURL, from: scriptData)
    let plistChanged = try contentsDiffer(at: launchAgentURL, from: plistData)

    if scriptChanged {
      try writeSecurely(scriptData, to: watchdogScriptURL, permissions: 0o700)
    }
    if plistChanged {
      try writeSecurely(plistData, to: launchAgentURL, permissions: 0o600)
    }

    let loaded = launchctl(["print", serviceTarget]) == 0
    if loaded && (scriptChanged || plistChanged) {
      _ = launchctl(["bootout", serviceTarget])
    }

    if !loaded || scriptChanged || plistChanged {
      let status = launchctl(["bootstrap", launchDomain, launchAgentURL.path])
      guard status == 0 else {
        throw NSError(
          domain: "com.ospfranco.sol.watchdog",
          code: Int(status),
          userInfo: [NSLocalizedDescriptionKey: "launchctl could not register the Sol watchdog (\(status))."]
        )
      }
    }

    // A clean quit leaves the job loaded but inactive for the rest of the
    // login session. Starting Sol manually should arm crash monitoring again.
    _ = launchctl(["kickstart", serviceTarget])
  }

  private func disableAndRemove() {
    _ = launchctl(["bootout", serviceTarget])
    try? fileManager.removeItem(at: launchAgentURL)
    try? fileManager.removeItem(at: watchdogScriptURL)
    try? fileManager.removeItem(at: processIDURL)
    try? fileManager.removeItem(at: intentionalQuitURL)
  }

  private func prepareRuntimeDirectory() throws {
    try fileManager.createDirectory(
      at: configDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try fileManager.createDirectory(
      at: runtimeDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try fileManager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: runtimeDirectory.path
    )
  }

  private func contentsDiffer(at url: URL, from expected: Data) throws -> Bool {
    guard fileManager.fileExists(atPath: url.path) else { return true }
    return try Data(contentsOf: url) != expected
  }

  private func writeSecurely(_ data: Data, to url: URL, permissions: Int) throws {
    try data.write(to: url, options: .atomic)
    try fileManager.setAttributes(
      [.posixPermissions: permissions],
      ofItemAtPath: url.path
    )
  }

  @discardableResult
  private func launchctl(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus
    } catch {
      NSLog("Could not run launchctl: \(error.localizedDescription)")
      return -1
    }
  }

  private var launchAgentPropertyList: [String: Any] {
    [
      "Label": jobLabel,
      "ProgramArguments": [
        "/bin/zsh",
        watchdogScriptURL.path,
        Bundle.main.bundleURL.path,
        processIDURL.path,
        intentionalQuitURL.path,
      ],
      "RunAtLoad": true,
      "KeepAlive": ["SuccessfulExit": false],
      "ProcessType": "Interactive",
      "LimitLoadToSessionType": "Aqua",
    ]
  }

  private var watchdogScript: String {
    #"""
    #!/bin/zsh
    set -u

    integer has_zselect=0
    if zmodload zsh/zselect 2>/dev/null; then
      has_zselect=1
    fi

    readonly app_bundle="$1"
    readonly pid_file="$2"
    readonly intentional_quit="$3"
    readonly app_executable="$app_bundle/Contents/MacOS/sol"

    /bin/rm -f "$intentional_quit"

    watchdog_sleep() {
      local hundredths="$1"
      local fallback_seconds="$2"
      if (( has_zselect )); then
        zselect -t "$hundredths" 2>/dev/null || true
      else
        /bin/sleep "$fallback_seconds"
      fi
    }

    valid_sol_pid() {
      local candidate="${1:-}"
      [[ "$candidate" == <-> ]] || return 1
      kill -0 "$candidate" 2>/dev/null || return 1
      local command_line
      command_line="$(/bin/ps -p "$candidate" -o command= 2>/dev/null)"
      [[ "$command_line" == "$app_executable"* ]]
    }

    sol_pid_is_alive() {
      local candidate="${1:-}"
      [[ "$candidate" == <-> ]] || return 1
      kill -0 "$candidate" 2>/dev/null
    }

    current_sol_pid() {
      local candidate=""
      if [[ -f "$pid_file" ]]; then
        IFS= read -r candidate < "$pid_file" || true
      fi
      if valid_sol_pid "$candidate"; then
        print -r -- "$candidate"
        return 0
      fi
      return 1
    }

    launch_sol() {
      local previous_pid="${1:-}"
      /usr/bin/open -n "$app_bundle" >/dev/null 2>&1 || return 1
      local attempt candidate
      for attempt in {1..100}; do
        candidate="$(current_sol_pid 2>/dev/null || true)"
        if [[ -n "$candidate" && "$candidate" != "$previous_pid" ]]; then
          print -r -- "$candidate"
          return 0
        fi
        watchdog_sleep 10 0.1
      done
      return 1
    }

    integer retry_delay=1
    while true; do
      if [[ -f "$intentional_quit" ]]; then
        /bin/rm -f "$intentional_quit"
        exit 0
      fi

      pid="$(current_sol_pid 2>/dev/null || true)"
      if [[ -z "$pid" ]]; then
        pid="$(launch_sol "" 2>/dev/null || true)"
        if [[ -z "$pid" ]]; then
          watchdog_sleep "$(( retry_delay * 100 ))" "$retry_delay"
          (( retry_delay = retry_delay < 30 ? retry_delay * 2 : 30 ))
          continue
        fi
      fi

      integer started_at="$(/bin/date +%s)"
      while sol_pid_is_alive "$pid"; do
        if [[ -f "$intentional_quit" ]]; then
          /bin/rm -f "$intentional_quit"
          exit 0
        fi
        watchdog_sleep 200 2
      done

      if [[ -f "$intentional_quit" ]]; then
        /bin/rm -f "$intentional_quit"
        exit 0
      fi

      integer runtime=$(( $(/bin/date +%s) - started_at ))
      if (( runtime >= 30 )); then
        retry_delay=1
      else
        (( retry_delay = retry_delay < 30 ? retry_delay * 2 : 30 ))
      fi
      watchdog_sleep "$(( retry_delay * 100 ))" "$retry_delay"
    done
    """#
  }
}
