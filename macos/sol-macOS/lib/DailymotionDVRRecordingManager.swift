import Foundation

private enum DailymotionDVRRecordingError: LocalizedError {
  case message(String)

  var errorDescription: String? {
    switch self {
    case .message(let message):
      return message
    }
  }
}

private struct DailymotionDVRInspection {
  let title: String
  let thumbnail: String?
  let start: String
  let end: String
  let duration: Double
  let isDVR: Bool
  let targetDuration: Double
  let bitrateKbps: Double?
  let qualities: [[String: Any]]

  var dictionary: [String: Any] {
    var result: [String: Any] = [
      "title": title,
      "start": start,
      "end": end,
      "duration": duration,
      "isDVR": isDVR,
      "targetDuration": targetDuration,
      "qualities": qualities,
    ]
    if let thumbnail {
      result["thumbnail"] = thumbnail
    }
    if let bitrateKbps {
      result["bitrateKbps"] = bitrateKbps
    }
    return result
  }
}

final class DailymotionDVRRecordingManager {
  static let shared = DailymotionDVRRecordingManager()

  private let workerQueue = DispatchQueue(
    label: "com.ospfranco.sol.dailymotion-dvr",
    qos: .userInitiated,
    attributes: .concurrent
  )
  private let lock = NSLock()
  private var activeJobID: String?
  private var activeProcess: Process?
  private var cancelRequested = false
  private var state: [String: Any] = ["status": "idle"]

  private init() {}

  func inspect(
    pageURL: String,
    qualityHeight: Int?,
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    workerQueue.async {
      do {
        let inspection = try self.performInspection(
          pageURL: pageURL,
          qualityHeight: qualityHeight
        )
        completion(.success(inspection.dictionary))
      } catch {
        completion(.failure(error))
      }
    }
  }

  func start(
    options: [String: Any],
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    do {
      let request = try recordingRequest(from: options)
      let jobID = UUID().uuidString

      lock.lock()
      if activeJobID != nil {
        lock.unlock()
        throw DailymotionDVRRecordingError.message(
          "A Dailymotion DVR recording is already running."
        )
      }
      activeJobID = jobID
      cancelRequested = false
      lock.unlock()

      publish([
        "id": jobID,
        "status": "preparing",
        "progress": 0.0,
        "message": "Resolving the Dailymotion DVR…",
        "outputPath": request.outputPath,
      ])
      completion(.success(currentState()))

      workerQueue.async {
        self.performRecording(jobID: jobID, request: request)
      }
    } catch {
      completion(.failure(error))
    }
  }

  func cancel(
    jobID: String,
    completion: @escaping (Result<Bool, Error>) -> Void
  ) {
    lock.lock()
    guard activeJobID == jobID else {
      lock.unlock()
      completion(.failure(DailymotionDVRRecordingError.message("Recording job not found.")))
      return
    }
    cancelRequested = true
    let process = activeProcess
    lock.unlock()

    updateState(status: "cancelling", message: "Stopping the recording safely…")
    if process?.isRunning == true {
      process?.interrupt()
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4) {
        if process?.isRunning == true {
          process?.terminate()
        }
      }
    }
    completion(.success(true))
  }

  func currentState() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    return state
  }

  func availableCapacity(path: String) -> Int64 {
    return availableCapacity(at: URL(fileURLWithPath: path))
  }

  func shutdown() {
    lock.lock()
    cancelRequested = true
    let process = activeProcess
    lock.unlock()
    guard process?.isRunning == true else { return }
    process?.interrupt()
    Thread.sleep(forTimeInterval: 0.2)
    if process?.isRunning == true {
      process?.terminate()
    }
  }

  private struct RecordingRequest {
    let pageURL: String
    let qualityHeight: Int?
    let start: String
    let end: String
    let startAtDVRBeginning: Bool
    let endAtDVREnd: Bool
    let outputPath: String
  }

  private func recordingRequest(from options: [String: Any]) throws -> RecordingRequest {
    guard
      let pageURL = options["url"] as? String,
      let start = options["start"] as? String,
      let end = options["end"] as? String,
      let outputPath = options["outputPath"] as? String
    else {
      throw DailymotionDVRRecordingError.message("The recording request is incomplete.")
    }
    try validateDailymotionPageURL(pageURL)

    guard
      let startDate = parseISODate(start),
      let endDate = parseISODate(end),
      endDate > startDate
    else {
      throw DailymotionDVRRecordingError.message("The selected time range is invalid.")
    }

    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    guard outputURL.pathExtension.lowercased() == "mp4", outputURL.path.hasPrefix("/") else {
      throw DailymotionDVRRecordingError.message("Choose an absolute MP4 destination.")
    }

    return RecordingRequest(
      pageURL: pageURL,
      qualityHeight: (options["qualityHeight"] as? NSNumber)?.intValue,
      start: start,
      end: end,
      startAtDVRBeginning: options["startAtDVRBeginning"] as? Bool ?? false,
      endAtDVREnd: options["endAtDVREnd"] as? Bool ?? false,
      outputPath: outputURL.path
    )
  }

  private func performInspection(
    pageURL: String,
    qualityHeight: Int?
  ) throws -> DailymotionDVRInspection {
    try validateDailymotionPageURL(pageURL)
    let metadata = try dailymotionMetadata(pageURL: pageURL)
    let sourceURL = try resolveMediaPlaylist(
      pageURL: pageURL,
      qualityHeight: qualityHeight
    )
    let range = try inspectPlaylist(sourceURL)

    guard
      let start = range["start"] as? String,
      let end = range["end"] as? String,
      let duration = (range["duration"] as? NSNumber)?.doubleValue,
      let isDVR = range["isDVR"] as? Bool
    else {
      throw DailymotionDVRRecordingError.message(
        "The DVR worker returned an incomplete time range."
      )
    }

    return DailymotionDVRInspection(
      title: metadata["title"] as? String ?? "Dailymotion DVR",
      thumbnail: metadata["thumbnail"] as? String,
      start: start,
      end: end,
      duration: duration,
      isDVR: isDVR,
      targetDuration: (range["targetDuration"] as? NSNumber)?.doubleValue ?? 3,
      bitrateKbps: selectedBitrate(
        metadata: metadata,
        qualityHeight: qualityHeight
      ),
      qualities: availableQualities(metadata: metadata)
    )
  }

  private func performRecording(jobID: String, request: RecordingRequest) {
    let activity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .idleSystemSleepDisabled],
      reason: "Recording a Dailymotion DVR"
    )
    defer {
      ProcessInfo.processInfo.endActivity(activity)
      lock.lock()
      if activeJobID == jobID {
        activeJobID = nil
        activeProcess = nil
        cancelRequested = false
      }
      lock.unlock()
    }

    do {
      try throwIfCancelled()
      let metadata = try dailymotionMetadata(
        pageURL: request.pageURL,
        trackForCancellation: true
      )
      try throwIfCancelled()
      let sourceURL = try resolveMediaPlaylist(
        pageURL: request.pageURL,
        qualityHeight: request.qualityHeight,
        trackForCancellation: true
      )
      try throwIfCancelled()

      let currentRange = try inspectPlaylist(sourceURL, trackForCancellation: true)
      try throwIfCancelled()
      let effectiveStart = request.startAtDVRBeginning
        ? currentRange["start"] as? String
        : request.start
      let effectiveEnd = request.endAtDVREnd
        ? currentRange["end"] as? String
        : request.end

      guard
        let effectiveStart,
        let effectiveEnd,
        let startDate = parseISODate(effectiveStart),
        let endDate = parseISODate(effectiveEnd)
      else {
        throw DailymotionDVRRecordingError.message("The selected time range is invalid.")
      }
      let duration = endDate.timeIntervalSince(startDate)
      let measuredBitrate = selectedBitrate(
        metadata: metadata,
        qualityHeight: request.qualityHeight
      )
      let fallbackHeight = request.qualityHeight
        ?? (availableQualities(metadata: metadata).first?["height"] as? Int)
      let bitrate = measuredBitrate ?? fallbackBitrate(for: fallbackHeight)
      let estimatedBytes = Int64(max(0, duration) * bitrate * 1_000 / 8 * 1.15)
      let outputURL = uniqueOutputURL(URL(fileURLWithPath: request.outputPath))
      let freeBytes = availableCapacity(at: outputURL.deletingLastPathComponent())
      let safetyMargin = Int64(256 * 1_024 * 1_024)
      guard freeBytes > 0 else {
        throw DailymotionDVRRecordingError.message(
          "Sol could not verify free space at the selected destination."
        )
      }
      if estimatedBytes + safetyMargin > freeBytes {
        throw DailymotionDVRRecordingError.message(
          "Not enough disk space for this recording and its safety margin."
        )
      }

      updateState([
        "status": "recording",
        "message": "Downloading DVR segments…",
        "outputPath": outputURL.path,
        "estimatedBytes": estimatedBytes,
        "availableBytes": freeBytes,
      ])

      let python = try executable(named: "python3")
      _ = try executable(named: "ffmpeg")
      let script = try dvrWorkerURL()
      try throwIfCancelled()
      let result = try runStreamingProcess(
        executable: python,
        arguments: [
          "-u",
          script.path,
          "cut",
          sourceURL,
          request.startAtDVRBeginning ? "dvr-start" : effectiveStart,
          request.endAtDVREnd ? "dvr-end" : effectiveEnd,
          outputURL.path,
        ],
        jobID: jobID
      )

      if isCancellationRequested() || result == 130 {
        publish([
          "id": jobID,
          "status": "cancelled",
          "progress": stateProgress(),
          "message": "Recording cancelled",
          "outputPath": outputURL.path,
        ])
      } else if result != 0 {
        throw DailymotionDVRRecordingError.message(lastStateError() ?? "Recording failed.")
      }
    } catch {
      if isCancellationRequested() {
        publish([
          "id": jobID,
          "status": "cancelled",
          "progress": stateProgress(),
          "message": "Recording cancelled",
        ])
      } else {
        publish([
          "id": jobID,
          "status": "error",
          "progress": stateProgress(),
          "message": error.localizedDescription,
          "error": error.localizedDescription,
        ])
      }
    }
  }

  private func validateDailymotionPageURL(_ value: String) throws {
    guard
      let components = URLComponents(string: value),
      components.scheme?.lowercased() == "https",
      components.user == nil,
      components.password == nil,
      components.port == nil,
      let host = components.host?.lowercased(),
      host == "dai.ly" || host == "dailymotion.com"
        || host.hasSuffix(".dailymotion.com")
    else {
      throw DailymotionDVRRecordingError.message("Choose a valid HTTPS Dailymotion URL.")
    }
  }

  private func parseISODate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    return ISO8601DateFormatter().date(from: value)
  }

  private func dailymotionMetadata(
    pageURL: String,
    trackForCancellation: Bool = false
  ) throws -> [String: Any] {
    let ytDLP = try executable(named: "yt-dlp")
    let output = try runProcess(
      executable: ytDLP,
      arguments: [
        "--ignore-config",
        "--dump-single-json",
        "--skip-download",
        "--no-playlist",
        "--no-warnings",
        pageURL,
      ],
      trackForCancellation: trackForCancellation
    )
    guard
      let data = output.data(using: .utf8),
      let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw DailymotionDVRRecordingError.message("yt-dlp returned invalid metadata.")
    }
    return metadata
  }

  private func resolveMediaPlaylist(
    pageURL: String,
    qualityHeight: Int?,
    trackForCancellation: Bool = false
  ) throws -> String {
    let ytDLP = try executable(named: "yt-dlp")
    var arguments = ["--ignore-config", "--get-url", "--no-playlist", "--no-warnings"]
    if let qualityHeight {
      arguments += [
        "--format",
        "best[height<=\(qualityHeight)]",
      ]
    } else {
      arguments += ["--format", "best"]
    }
    arguments.append(pageURL)
    let output = try runProcess(
      executable: ytDLP,
      arguments: arguments,
      trackForCancellation: trackForCancellation
    )
    let candidates = output
      .split(whereSeparator: \.isNewline)
      .map(String.init)
      .filter { $0.contains(".m3u8") }
    guard let sourceURL = candidates.first, let url = URL(string: sourceURL), url.scheme == "https" else {
      throw DailymotionDVRRecordingError.message(
        "yt-dlp did not return a secure HLS media playlist."
      )
    }
    return sourceURL
  }

  private func inspectPlaylist(
    _ sourceURL: String,
    trackForCancellation: Bool = false
  ) throws -> [String: Any] {
    let python = try executable(named: "python3")
    let script = try dvrWorkerURL()
    let output = try runProcess(
      executable: python,
      arguments: ["-u", script.path, "inspect", sourceURL],
      trackForCancellation: trackForCancellation
    )
    guard let payload = jsonObjects(in: output).last else {
      throw DailymotionDVRRecordingError.message("Could not read the DVR time range.")
    }
    if payload["event"] as? String == "error" {
      throw DailymotionDVRRecordingError.message(
        payload["message"] as? String ?? "Could not inspect the DVR."
      )
    }
    return payload
  }

  private func availableQualities(metadata: [String: Any]) -> [[String: Any]] {
    guard let formats = metadata["formats"] as? [[String: Any]] else { return [] }
    var bestByHeight: [Int: [String: Any]] = [:]
    for format in formats {
      guard
        let height = (format["height"] as? NSNumber)?.intValue,
        height > 0,
        (format["vcodec"] as? String) != "none"
      else { continue }
      let protocolName = (format["protocol"] as? String)?.lowercased() ?? ""
      let formatURL = (format["url"] as? String)?.lowercased() ?? ""
      guard protocolName.contains("m3u8") || formatURL.contains(".m3u8") else { continue }
      let fps = (format["fps"] as? NSNumber)?.intValue
      let bitrate = (format["tbr"] as? NSNumber)?.doubleValue ?? 0
      let previousBitrate = (bestByHeight[height]?["bitrateKbps"] as? NSNumber)?.doubleValue ?? -1
      if bitrate >= previousBitrate {
        var item: [String: Any] = [
          "height": height,
          "label": fps.map { "\(height)p · \($0) fps" } ?? "\(height)p",
          "bitrateKbps": bitrate,
        ]
        if let fps {
          item["fps"] = fps
        }
        bestByHeight[height] = item
      }
    }
    return bestByHeight.values.sorted {
      (($0["height"] as? Int) ?? 0) > (($1["height"] as? Int) ?? 0)
    }
  }

  private func selectedBitrate(
    metadata: [String: Any],
    qualityHeight: Int?
  ) -> Double? {
    let qualities = availableQualities(metadata: metadata)
    let candidate: Double?
    if let qualityHeight {
      candidate = qualities
        .first { (($0["height"] as? Int) ?? .max) <= qualityHeight }?["bitrateKbps"] as? Double
    } else {
      candidate = qualities.first?["bitrateKbps"] as? Double
        ?? (metadata["tbr"] as? NSNumber)?.doubleValue
    }
    guard let candidate, candidate.isFinite, candidate > 0 else { return nil }
    return candidate
  }

  private func fallbackBitrate(for height: Int?) -> Double {
    switch height ?? 1080 {
    case 0...360: return 900
    case 361...480: return 1_500
    case 481...720: return 3_500
    case 721...1080: return 6_500
    default: return 12_000
    }
  }

  private func executable(named name: String) throws -> URL {
    let candidates = [
      "/opt/homebrew/bin/\(name)",
      "/usr/local/bin/\(name)",
      "/usr/bin/\(name)",
      "/bin/\(name)",
    ]
    for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
      return URL(fileURLWithPath: candidate)
    }
    throw DailymotionDVRRecordingError.message(
      "\(name) is required. Install it with Homebrew and try again."
    )
  }

  private func dvrWorkerURL() throws -> URL {
    guard let script = Bundle.main.url(forResource: "dvr_cut", withExtension: "py") else {
      throw DailymotionDVRRecordingError.message("The DVR worker is missing from Sol.app.")
    }
    return script
  }

  private func processEnvironment() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    let existingPath = environment["PATH"] ?? ""
    environment["PATH"] = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
      existingPath,
    ].filter { !$0.isEmpty }.joined(separator: ":")
    environment["PYTHONUNBUFFERED"] = "1"
    return environment
  }

  private func runProcess(
    executable: URL,
    arguments: [String],
    trackForCancellation: Bool = false
  ) throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = processEnvironment()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      throw DailymotionDVRRecordingError.message(error.localizedDescription)
    }
    if trackForCancellation {
      lock.lock()
      activeProcess = process
      let shouldCancel = cancelRequested
      lock.unlock()
      if shouldCancel, process.isRunning {
        process.interrupt()
      }
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if trackForCancellation {
      lock.lock()
      if activeProcess === process {
        activeProcess = nil
      }
      lock.unlock()
    }
    let output = String(data: data, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
      let payload = jsonObjects(in: output).last
      let message = payload?["message"] as? String
        ?? output.trimmingCharacters(in: .whitespacesAndNewlines)
      throw DailymotionDVRRecordingError.message(
        message.isEmpty ? "The command failed." : message
      )
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func runStreamingProcess(
    executable: URL,
    arguments: [String],
    jobID: String
  ) throws -> Int32 {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = processEnvironment()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
      try process.run()
    } catch {
      throw DailymotionDVRRecordingError.message(error.localizedDescription)
    }
    lock.lock()
    activeProcess = process
    lock.unlock()
    if isCancellationRequested(), process.isRunning {
      process.interrupt()
    }

    var bufferedData = Data()
    var logTail = ""
    while true {
      let data = pipe.fileHandleForReading.availableData
      if data.isEmpty { break }
      bufferedData.append(data)
      while let newline = bufferedData.firstIndex(of: 0x0A) {
        let lineData = bufferedData.prefix(upTo: newline)
        bufferedData.removeSubrange(...newline)
        let line = String(data: lineData, encoding: .utf8) ?? ""
        if let payload = jsonObject(from: line) {
          handleWorkerEvent(payload, jobID: jobID)
        } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          logTail = String(line.suffix(500))
        }
      }
    }
    process.waitUntilExit()
    if !bufferedData.isEmpty {
      let line = String(data: bufferedData, encoding: .utf8) ?? ""
      if let payload = jsonObject(from: line) {
        handleWorkerEvent(payload, jobID: jobID)
      } else if !line.isEmpty {
        logTail = String(line.suffix(500))
      }
    }
    lock.lock()
    if activeProcess === process {
      activeProcess = nil
    }
    if !logTail.isEmpty, state["error"] == nil {
      state["lastLog"] = logTail
    }
    lock.unlock()
    return process.terminationStatus
  }

  private func handleWorkerEvent(_ payload: [String: Any], jobID: String) {
    guard let event = payload["event"] as? String else { return }
    switch event {
    case "selection":
      updateState([
        "status": "recording",
        "message": "Downloading \((payload["segmentCount"] as? NSNumber)?.intValue ?? 0) DVR segments…",
        "duration": payload["duration"] ?? 0,
        "actualStart": payload["start"] ?? "",
        "actualEnd": payload["end"] ?? "",
      ])
    case "recording", "progress":
      updateState([
        "status": "recording",
        "message": "Downloading DVR segments…",
        "progress": payload["progress"] ?? 0,
        "elapsed": payload["elapsed"] ?? 0,
        "duration": payload["duration"] ?? 0,
      ])
    case "finalizing":
      updateState([
        "status": "finalizing",
        "message": "Finalizing the MP4…",
        "progress": 1.0,
      ])
    case "completed":
      publish([
        "id": jobID,
        "status": "completed",
        "message": "Recording completed",
        "progress": 1.0,
        "outputPath": payload["path"] ?? "",
        "bytes": payload["bytes"] ?? 0,
      ])
    case "cancelled":
      updateState(status: "cancelled", message: "Recording cancelled")
    case "error":
      let message = payload["message"] as? String ?? "Recording failed."
      updateState([
        "status": "error",
        "message": message,
        "error": message,
      ])
    default:
      break
    }
  }

  private func availableCapacity(at url: URL) -> Int64 {
    do {
      let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      return values.volumeAvailableCapacityForImportantUsage ?? 0
    } catch {
      return 0
    }
  }

  private func uniqueOutputURL(_ requested: URL) -> URL {
    if !FileManager.default.fileExists(atPath: requested.path) { return requested }
    let directory = requested.deletingLastPathComponent()
    let name = requested.deletingPathExtension().lastPathComponent
    let extensionName = requested.pathExtension
    for suffix in 2...999 {
      let candidate = directory
        .appendingPathComponent("\(name) \(suffix)")
        .appendingPathExtension(extensionName)
      if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    }
    return directory
      .appendingPathComponent("\(name) \(UUID().uuidString.prefix(6))")
      .appendingPathExtension(extensionName)
  }

  private func jsonObjects(in output: String) -> [[String: Any]] {
    return output.split(whereSeparator: \.isNewline).compactMap {
      jsonObject(from: String($0))
    }
  }

  private func jsonObject(from line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8) else { return nil }
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else { return nil }
    return dictionary
  }

  private func throwIfCancelled() throws {
    if isCancellationRequested() {
      throw DailymotionDVRRecordingError.message("Recording cancelled")
    }
  }

  private func isCancellationRequested() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelRequested
  }

  private func stateProgress() -> Double {
    lock.lock()
    defer { lock.unlock() }
    return (state["progress"] as? NSNumber)?.doubleValue ?? 0
  }

  private func lastStateError() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return state["error"] as? String ?? state["lastLog"] as? String
  }

  private func updateState(status: String, message: String) {
    updateState(["status": status, "message": message])
  }

  private func updateState(_ patch: [String: Any]) {
    lock.lock()
    var next = state
    for (key, value) in patch {
      next[key] = value
    }
    state = next
    let snapshot = state
    lock.unlock()
    dispatch(snapshot)
  }

  private func publish(_ next: [String: Any]) {
    lock.lock()
    state = next
    let snapshot = state
    lock.unlock()
    dispatch(snapshot)
  }

  private func dispatch(_ snapshot: [String: Any]) {
    DispatchQueue.main.async {
      SolEmitter.sharedInstance.dispatch(
        name: "dailymotionDVRRecordingChanged",
        body: snapshot
      )
    }
  }
}
