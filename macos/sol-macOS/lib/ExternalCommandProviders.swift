import AppKit
import CryptoKit
import Darwin
import Foundation

private enum ExternalCommandArgumentMode: String, Codable {
  case raw
  case shlex
}

private struct ExternalCommandIcon: Codable {
  let type: String
  let name: String?
  let value: String?

  var publicObject: [String: Any] {
    switch type {
    case "sf-symbol":
      return ["type": type, "name": name ?? "command"]
    case "emoji":
      return ["type": type, "value": value ?? "⌘"]
    default:
      return ["type": "sf-symbol", "name": "command"]
    }
  }
}

private struct ExternalCommandDefinition: Codable {
  let name: String
  let label: String
  let detail: String?
  let icon: ExternalCommandIcon?
  let endpoint: String
  let argumentMode: ExternalCommandArgumentMode

  var publicObject: [String: Any] {
    var object: [String: Any] = [
      "name": name,
      "label": label,
      "endpoint": endpoint,
      "argumentMode": argumentMode.rawValue,
    ]
    if let detail {
      object["detail"] = detail
    }
    if let icon {
      object["icon"] = icon.publicObject
    }
    return object
  }
}

private struct ExternalCommandProviderRecord: Codable {
  let providerID: String
  let providerName: String
  let pid: Int32
  let processFingerprint: String
  let commands: [ExternalCommandDefinition]
  var isActive: Bool

  var publicObject: [String: Any] {
    [
      "providerId": providerID,
      "provider": [
        "name": providerName,
        "pid": Int(pid),
      ],
      "state": isActive ? "active" : "suspended",
      "commands": commands.map(\.publicObject),
    ]
  }
}

private struct ExternalCommandProviderFile: Codable {
  let version: Int
  let providers: [ExternalCommandProviderRecord]
}

private enum ExternalProcessInspection {
  case alive(fingerprint: String)
  case missing
  case uninspectable
}

private func externalCallbackURL(_ value: String) -> URL? {
  guard let components = URLComponents(string: value),
    components.scheme == "http",
    components.host == "127.0.0.1",
    components.user == nil,
    components.password == nil,
    components.fragment == nil,
    let port = components.port,
    (1...Int(UInt16.max)).contains(port),
    let url = components.url
  else {
    return nil
  }
  return url
}

private enum ExternalProviderJSON {
  static func error(_ message: String, field: String?) -> SolHTTPAPIError {
    SolHTTPAPIError(status: 422, code: "invalid_field", message: message, field: field)
  }

  static func required(
    _ object: [String: Any],
    key: String,
    parent: String? = nil
  ) throws -> Any {
    guard let value = object[key], !(value is NSNull) else {
      let field = parent.map { "\($0).\(key)" } ?? key
      throw error("\(field) is required.", field: field)
    }
    return value
  }

  static func object(_ value: Any, field: String?) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
      throw error("Expected a JSON object.", field: field)
    }
    return object
  }

  static func allowOnly(_ object: [String: Any], keys: Set<String>, field: String?) throws {
    if let unknown = object.keys.first(where: { !keys.contains($0) }) {
      let path = field.map { "\($0).\(unknown)" } ?? unknown
      throw error("Unknown field \(path).", field: path)
    }
  }

  static func string(
    _ value: Any,
    field: String,
    minimum: Int,
    maximum: Int
  ) throws -> String {
    guard let string = value as? String else {
      throw error("Expected a string.", field: field)
    }
    guard string.count >= minimum, string.count <= maximum else {
      throw error(
        "Length must be between \(minimum) and \(maximum) characters.",
        field: field
      )
    }
    return string
  }

  static func optionalString(_ value: Any?, field: String, maximum: Int) throws -> String? {
    guard let value, !(value is NSNull) else { return nil }
    return try string(value, field: field, minimum: 0, maximum: maximum)
  }

  static func integer(_ value: Any, field: String, minimum: Int, maximum: Int) throws -> Int {
    guard let number = value as? NSNumber,
      CFGetTypeID(number as CFTypeRef) != CFBooleanGetTypeID()
    else {
      throw error("Expected an integer.", field: field)
    }
    let double = number.doubleValue
    guard double.isFinite, double.rounded() == double,
      double >= Double(minimum), double <= Double(maximum)
    else {
      throw error(
        "Expected an integer between \(minimum) and \(maximum).",
        field: field
      )
    }
    return Int(double)
  }
}

private struct ParsedExternalProviderRegistration {
  let providerName: String
  let pid: Int32
  let commands: [ExternalCommandDefinition]

  static func parse(providerID: String, object: Any) throws -> ParsedExternalProviderRegistration {
    guard
      providerID.range(
        of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#,
        options: .regularExpression
      ) != nil
    else {
      throw ExternalProviderJSON.error(
        "providerId must match [A-Za-z0-9][A-Za-z0-9._-]* and contain at most 128 characters.",
        field: "providerId"
      )
    }

    let root = try ExternalProviderJSON.object(object, field: nil)
    try ExternalProviderJSON.allowOnly(root, keys: ["provider", "commands"], field: nil)

    let provider = try ExternalProviderJSON.object(
      ExternalProviderJSON.required(root, key: "provider"),
      field: "provider"
    )
    try ExternalProviderJSON.allowOnly(provider, keys: ["name", "pid"], field: "provider")
    let providerName = try ExternalProviderJSON.string(
      ExternalProviderJSON.required(provider, key: "name", parent: "provider"),
      field: "provider.name",
      minimum: 1,
      maximum: 200
    )
    let pidValue = try ExternalProviderJSON.integer(
      ExternalProviderJSON.required(provider, key: "pid", parent: "provider"),
      field: "provider.pid",
      minimum: 1,
      maximum: Int(Int32.max)
    )

    guard let rawCommands = root["commands"] as? [Any], !rawCommands.isEmpty else {
      throw ExternalProviderJSON.error(
        "commands must contain at least one command.",
        field: "commands"
      )
    }
    guard rawCommands.count <= 1_000 else {
      throw ExternalProviderJSON.error(
        "commands cannot contain more than 1000 entries.",
        field: "commands"
      )
    }

    var commandNames = Set<String>()
    let commands = try rawCommands.enumerated().map { index, rawCommand in
      let field = "commands[\(index)]"
      let command = try ExternalProviderJSON.object(rawCommand, field: field)
      try ExternalProviderJSON.allowOnly(
        command,
        keys: ["name", "label", "detail", "icon", "endpoint", "argumentMode"],
        field: field
      )
      let name = try ExternalProviderJSON.string(
        ExternalProviderJSON.required(command, key: "name", parent: field),
        field: "\(field).name",
        minimum: 1,
        maximum: 100
      )
      guard
        name.range(
          of: #"^[a-z0-9][a-z0-9._-]*$"#,
          options: .regularExpression
        ) != nil
      else {
        throw ExternalProviderJSON.error(
          "name must match [a-z0-9][a-z0-9._-]*.",
          field: "\(field).name"
        )
      }
      guard commandNames.insert(name.lowercased()).inserted else {
        throw SolHTTPAPIError(
          status: 409,
          code: "command_conflict",
          message: "Command \(name) appears more than once in this registration.",
          field: "\(field).name"
        )
      }

      let label = try ExternalProviderJSON.string(
        ExternalProviderJSON.required(command, key: "label", parent: field),
        field: "\(field).label",
        minimum: 1,
        maximum: 500
      )
      let detail = try ExternalProviderJSON.optionalString(
        command["detail"],
        field: "\(field).detail",
        maximum: 2_000
      )
      let icon = try parseIcon(command["icon"], field: "\(field).icon")
      let endpoint = try ExternalProviderJSON.string(
        ExternalProviderJSON.required(command, key: "endpoint", parent: field),
        field: "\(field).endpoint",
        minimum: 1,
        maximum: 4_096
      )
      try validateEndpoint(endpoint, field: "\(field).endpoint")
      let modeValue = try ExternalProviderJSON.string(
        ExternalProviderJSON.required(command, key: "argumentMode", parent: field),
        field: "\(field).argumentMode",
        minimum: 1,
        maximum: 20
      )
      guard let argumentMode = ExternalCommandArgumentMode(rawValue: modeValue) else {
        throw ExternalProviderJSON.error(
          "argumentMode must be raw or shlex.",
          field: "\(field).argumentMode"
        )
      }

      return ExternalCommandDefinition(
        name: name,
        label: label,
        detail: detail,
        icon: icon,
        endpoint: endpoint,
        argumentMode: argumentMode
      )
    }

    return ParsedExternalProviderRegistration(
      providerName: providerName,
      pid: Int32(pidValue),
      commands: commands
    )
  }

  private static func parseIcon(_ value: Any?, field: String) throws -> ExternalCommandIcon? {
    guard let value, !(value is NSNull) else { return nil }
    let icon = try ExternalProviderJSON.object(value, field: field)
    let type = try ExternalProviderJSON.string(
      ExternalProviderJSON.required(icon, key: "type", parent: field),
      field: "\(field).type",
      minimum: 1,
      maximum: 30
    )
    switch type {
    case "sf-symbol":
      try ExternalProviderJSON.allowOnly(icon, keys: ["type", "name"], field: field)
      let name = try ExternalProviderJSON.string(
        ExternalProviderJSON.required(icon, key: "name", parent: field),
        field: "\(field).name",
        minimum: 1,
        maximum: 200
      )
      return ExternalCommandIcon(type: type, name: name, value: nil)
    case "emoji":
      try ExternalProviderJSON.allowOnly(icon, keys: ["type", "value"], field: field)
      let emoji = try ExternalProviderJSON.string(
        ExternalProviderJSON.required(icon, key: "value", parent: field),
        field: "\(field).value",
        minimum: 1,
        maximum: 16
      )
      guard emoji.count == 1 else {
        throw ExternalProviderJSON.error(
          "value must contain one extended grapheme cluster.",
          field: "\(field).value"
        )
      }
      return ExternalCommandIcon(type: type, name: nil, value: emoji)
    default:
      throw ExternalProviderJSON.error(
        "type must be sf-symbol or emoji.",
        field: "\(field).type"
      )
    }
  }

  private static func validateEndpoint(_ value: String, field: String) throws {
    guard externalCallbackURL(value) != nil else {
      throw ExternalProviderJSON.error(
        "endpoint must be an absolute http://127.0.0.1:<port>/... URL without credentials or a fragment.",
        field: field
      )
    }
  }
}

private final class ExternalCommandNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    willPerformHTTPRedirection _: HTTPURLResponse,
    newRequest _: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

final class ExternalCommandProviderRegistry: NSObject, SolHTTPRouteHandler {
  static let shared = ExternalCommandProviderRegistry()

  private static let route = "/v1/command-providers"
  private static let defaultReservedCommands: Set<String> = ["ai", "ia", "dm"]
  private static let processCheckInterval: TimeInterval = 60

  private let queue = DispatchQueue(label: "com.ospfranco.sol.external-command-providers")
  private let noRedirectDelegate = ExternalCommandNoRedirectDelegate()
  private lazy var callbackSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 5
    configuration.timeoutIntervalForResource = 10
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.connectionProxyDictionary = [:]
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(
      configuration: configuration,
      delegate: noRedirectDelegate,
      delegateQueue: nil
    )
  }()

  private var providers: [String: ExternalCommandProviderRecord] = [:]
  private var javascriptReservedCommands = Set<String>()
  private var symbolImageCache: [String: String] = [:]
  private var unavailableSymbolNames = Set<String>()
  private var timer: DispatchSourceTimer?
  private var started = false

  private override init() {
    super.init()
  }

  func start() {
    queue.async { [weak self] in
      guard let self, !started else { return }
      started = true
      loadPersistedProviders()
      revalidateAllProviders()

      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(
        deadline: .now() + Self.processCheckInterval,
        repeating: Self.processCheckInterval,
        leeway: .seconds(2)
      )
      timer.setEventHandler { [weak self] in
        self?.revalidateAllProviders()
      }
      self.timer = timer
      timer.resume()
    }
  }

  func stop() {
    queue.async { [weak self] in
      guard let self else { return }
      timer?.setEventHandler {}
      timer?.cancel()
      timer = nil
      started = false
      callbackSession.invalidateAndCancel()
    }
  }

  func handle(_ request: SolHTTPRequest, context: SolHTTPRequestContext) -> Bool {
    guard request.path == Self.route || request.path.hasPrefix("\(Self.route)/") else {
      return false
    }

    queue.async { [weak self] in
      self?.handleOnQueue(request, context: context)
    }
    return true
  }

  func setReservedCommandNames(_ names: [String]) {
    queue.async { [weak self] in
      guard let self else { return }
      javascriptReservedCommands = Set(names.map { $0.lowercased() })
    }
  }

  func bridgeSnapshot(_ completion: @escaping ([[String: Any]]) -> Void) {
    queue.async { [weak self] in
      guard let self else {
        completion([])
        return
      }
      let snapshot = providers.values
        .sorted { $0.providerID.localizedStandardCompare($1.providerID) == .orderedAscending }
        .map(bridgeObject)
      completion(snapshot)
    }
  }

  func invoke(
    providerID: String,
    commandName: String,
    raw: String,
    arguments: [String],
    completion: @escaping (Bool) -> Void
  ) {
    queue.async { [weak self] in
      guard let self,
        var provider = providers[providerID],
        let command = provider.commands.first(where: {
          $0.name.caseInsensitiveCompare(commandName) == .orderedSame
        }),
        !currentReservedCommandNames().contains(command.name.lowercased())
      else {
        completion(false)
        return
      }

      switch inspectProcess(pid: provider.pid) {
      case .missing:
        removeProvider(providerID)
        completion(false)
      case .alive(let fingerprint) where fingerprint != provider.processFingerprint:
        removeProvider(providerID)
        completion(false)
      case .uninspectable:
        if provider.isActive {
          provider.isActive = false
          providers[providerID] = provider
          persistBestEffort()
          emitChange()
        }
        completion(false)
      case .alive:
        if !provider.isActive {
          provider.isActive = true
          providers[providerID] = provider
          persistBestEffort()
          emitChange()
        }
        sendInvocation(
          provider: provider,
          command: command,
          raw: raw,
          arguments: arguments
        )
        completion(true)
      }
    }
  }

  private func handleOnQueue(_ request: SolHTTPRequest, context: SolHTTPRequestContext) {
    if request.path == Self.route {
      guard request.method == "GET" else {
        context.respond(methodNotFound("GET", path: Self.route))
        return
      }
      let list = providers.values
        .sorted { $0.providerID.localizedStandardCompare($1.providerID) == .orderedAscending }
        .map(\.publicObject)
      context.respond(.json(["providers": list]))
      return
    }

    let providerID = String(request.path.dropFirst(Self.route.count + 1))
    guard !providerID.isEmpty, !providerID.contains("/") else {
      context.respond(
        .error(
          SolHTTPAPIError(
            status: 404,
            code: "not_found",
            message: "The command provider route is invalid."
          )))
      return
    }

    switch request.method {
    case "PUT":
      register(providerID: providerID, request: request, context: context)
    case "DELETE":
      unregister(providerID: providerID, context: context)
    default:
      context.respond(methodNotFound("PUT or DELETE", path: request.path))
    }
  }

  private func register(
    providerID: String,
    request: SolHTTPRequest,
    context: SolHTTPRequestContext
  ) {
    do {
      let registration = try ParsedExternalProviderRegistration.parse(
        providerID: providerID,
        object: request.jsonObject()
      )

      let reserved = currentReservedCommandNames()
      let namesFromOtherProviders = Set(
        providers.values
          .filter { $0.providerID != providerID }
          .flatMap { $0.commands.map { $0.name.lowercased() } }
      )
      for (index, command) in registration.commands.enumerated() {
        let normalizedName = command.name.lowercased()
        if reserved.contains(normalizedName) || namesFromOtherProviders.contains(normalizedName) {
          throw SolHTTPAPIError(
            status: 409,
            code: "command_conflict",
            message: "Command \(command.name) is already registered in Sol.",
            field: "commands[\(index)].name"
          )
        }
      }

      let fingerprint: String
      switch inspectProcess(pid: registration.pid) {
      case .alive(let value):
        fingerprint = value
      case .missing:
        throw SolHTTPAPIError(
          status: 422,
          code: "pid_not_found",
          message: "provider.pid does not identify a running process.",
          field: "provider.pid"
        )
      case .uninspectable:
        throw SolHTTPAPIError(
          status: 422,
          code: "process_uninspectable",
          message: "Sol could not inspect the executable and arguments for provider.pid.",
          field: "provider.pid"
        )
      }

      var updatedProviders = providers
      updatedProviders[providerID] = ExternalCommandProviderRecord(
        providerID: providerID,
        providerName: registration.providerName,
        pid: registration.pid,
        processFingerprint: fingerprint,
        commands: registration.commands,
        isActive: true
      )
      try persist(updatedProviders)
      providers = updatedProviders
      emitChange()
      context.respond(
        .json([
          "status": "registered",
          "providerId": providerID,
          "commands": registration.commands.map(\.name),
          "processCheckIntervalSeconds": Int(Self.processCheckInterval),
        ]))
    } catch let error as SolHTTPAPIError {
      context.respond(.error(error))
    } catch {
      context.respond(
        .error(
          SolHTTPAPIError(
            status: 503,
            code: "api_unavailable",
            message: "The command provider could not be persisted."
          )))
    }
  }

  private func unregister(providerID: String, context: SolHTTPRequestContext) {
    guard providers[providerID] != nil else {
      context.respond(
        .error(
          SolHTTPAPIError(
            status: 404,
            code: "not_found",
            message: "No command provider has id \(providerID)."
          )))
      return
    }

    var updatedProviders = providers
    updatedProviders.removeValue(forKey: providerID)
    do {
      try persist(updatedProviders)
      providers = updatedProviders
      emitChange()
      context.respond(.json(["status": "unregistered"]))
    } catch {
      context.respond(
        .error(
          SolHTTPAPIError(
            status: 503,
            code: "api_unavailable",
            message: "The command provider could not be removed from persistent storage."
          )))
    }
  }

  private func methodNotFound(_ method: String, path: String) -> SolHTTPResponse {
    .error(
      SolHTTPAPIError(
        status: 404,
        code: "not_found",
        message: "\(method) is required for \(path)."
      ))
  }

  private func revalidateAllProviders() {
    guard !providers.isEmpty else { return }
    var changed = false
    var updatedProviders = providers

    for provider in providers.values {
      switch inspectProcess(pid: provider.pid) {
      case .missing:
        updatedProviders.removeValue(forKey: provider.providerID)
        changed = true
      case .alive(let fingerprint) where fingerprint != provider.processFingerprint:
        updatedProviders.removeValue(forKey: provider.providerID)
        changed = true
      case .uninspectable:
        if provider.isActive {
          var suspended = provider
          suspended.isActive = false
          updatedProviders[provider.providerID] = suspended
          changed = true
        }
      case .alive:
        if !provider.isActive {
          var active = provider
          active.isActive = true
          updatedProviders[provider.providerID] = active
          changed = true
        }
      }
    }

    guard changed else { return }
    providers = updatedProviders
    persistBestEffort()
    emitChange()
  }

  private func removeProvider(_ providerID: String) {
    guard providers.removeValue(forKey: providerID) != nil else { return }
    persistBestEffort()
    emitChange()
  }

  private func currentReservedCommandNames() -> Set<String> {
    Self.defaultReservedCommands
      .union(javascriptReservedCommands)
      .union(scriptCommandNames())
      .union(configuredDirectCommandNames())
  }

  private func configuredDirectCommandNames() -> Set<String> {
    let configuration = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("sol", isDirectory: true)
      .appendingPathComponent("config.json", isDirectory: false)
    guard let data = try? Data(contentsOf: configuration),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let streams = root["dailymotionStreams"] as? [[String: Any]]
    else {
      return []
    }
    return Set(
      streams.compactMap { stream in
        guard let command = stream["command"] as? String else { return nil }
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased()
        return normalized.isEmpty ? nil : normalized
      }
    )
  }

  private func scriptCommandNames() -> Set<String> {
    let directory = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("sol", isDirectory: true)
      .appendingPathComponent("scripts", isDirectory: true)
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    var names = Set<String>()
    for file in files where file.pathExtension.lowercased() == "sh" {
      guard let source = try? String(contentsOf: file, encoding: .utf8),
        scriptArgumentHeaderIsValid(source),
        let command = metadataValue(named: "command", in: source),
        command.range(
          of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#,
          options: .regularExpression
        ) != nil
      else {
        continue
      }
      names.insert(command.lowercased())
    }
    return names
  }

  private func scriptArgumentHeaderIsValid(_ source: String) -> Bool {
    guard let value = metadataValue(named: "arguments", in: source) else { return true }
    return value.caseInsensitiveCompare("raw") == .orderedSame
      || value.caseInsensitiveCompare("shlex") == .orderedSame
  }

  private func metadataValue(named name: String, in source: String) -> String? {
    let escapedName = NSRegularExpression.escapedPattern(for: name)
    guard
      let expression = try? NSRegularExpression(
        pattern: "(?im)^#\\s*\(escapedName):\\s*(.+)$"
      )
    else {
      return nil
    }
    let range = NSRange(source.startIndex..., in: source)
    guard let match = expression.firstMatch(in: source, range: range),
      let valueRange = Range(match.range(at: 1), in: source)
    else {
      return nil
    }
    return source[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func inspectProcess(pid: Int32) -> ExternalProcessInspection {
    guard processExists(pid) else { return .missing }
    guard let executablePath = processExecutablePath(pid),
      let arguments = processArgumentBytes(pid)
    else {
      return processExists(pid) ? .uninspectable : .missing
    }

    let canonicalPath = URL(fileURLWithPath: executablePath)
      .standardizedFileURL
      .resolvingSymlinksInPath()
      .path
    var fingerprintInput = Data()
    appendFingerprintComponent(Data(canonicalPath.utf8), to: &fingerprintInput)
    for argument in arguments {
      appendFingerprintComponent(argument, to: &fingerprintInput)
    }
    let digest = SHA256.hash(data: fingerprintInput)
    return .alive(fingerprint: digest.map { String(format: "%02x", $0) }.joined())
  }

  private func processExists(_ pid: Int32) -> Bool {
    if Darwin.kill(pid, 0) == 0 { return true }
    return errno == EPERM
  }

  private func processExecutablePath(_ pid: Int32) -> String? {
    var bytes = [UInt8](repeating: 0, count: 4_096)
    let length = bytes.withUnsafeMutableBytes { buffer -> Int32 in
      proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
    }
    guard length > 0 else { return nil }
    let data = Data(bytes.prefix(Int(length)).prefix { $0 != 0 })
    return String(data: data, encoding: .utf8)
  }

  private func processArgumentBytes(_ pid: Int32) -> [Data]? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
      return nil
    }

    for _ in 0..<2 {
      var bytes = [UInt8](repeating: 0, count: size)
      var actualSize = size
      let result = bytes.withUnsafeMutableBytes { buffer in
        sysctl(&mib, UInt32(mib.count), buffer.baseAddress, &actualSize, nil, 0)
      }
      if result == 0 {
        return parseProcessArguments(Array(bytes.prefix(actualSize)))
      }
      guard errno == ENOMEM,
        sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0,
        size > 0
      else {
        return nil
      }
    }
    return nil
  }

  private func parseProcessArguments(_ bytes: [UInt8]) -> [Data]? {
    guard bytes.count >= MemoryLayout<Int32>.size else { return nil }
    let argumentCount: Int32 = bytes.withUnsafeBytes { buffer in
      buffer.loadUnaligned(as: Int32.self)
    }
    guard argumentCount >= 0, argumentCount <= 100_000 else { return nil }

    var cursor = MemoryLayout<Int32>.size
    guard let executableEnd = bytes[cursor...].firstIndex(of: 0) else { return nil }
    cursor = executableEnd + 1
    while cursor < bytes.count, bytes[cursor] == 0 {
      cursor += 1
    }

    var arguments: [Data] = []
    arguments.reserveCapacity(Int(argumentCount))
    for _ in 0..<Int(argumentCount) {
      guard cursor <= bytes.count else { return nil }
      let end = bytes[cursor...].firstIndex(of: 0) ?? bytes.endIndex
      arguments.append(Data(bytes[cursor..<end]))
      guard end < bytes.endIndex else {
        return arguments.count == Int(argumentCount) ? arguments : nil
      }
      cursor = end + 1
    }
    return arguments
  }

  private func appendFingerprintComponent(_ component: Data, to data: inout Data) {
    var length = UInt64(component.count).bigEndian
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
    data.append(component)
  }

  private func sendInvocation(
    provider: ExternalCommandProviderRecord,
    command: ExternalCommandDefinition,
    raw: String,
    arguments: [String]
  ) {
    guard let endpoint = externalCallbackURL(command.endpoint) else { return }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = .current
    let payload: [String: Any] = [
      "version": 1,
      "provider": [
        "id": provider.providerID,
        "name": provider.providerName,
      ],
      "command": [
        "name": command.name,
        "label": command.label,
      ],
      "argumentMode": command.argumentMode.rawValue,
      "raw": raw,
      "args": arguments,
      "context": [
        "invocationId": UUID().uuidString.lowercased(),
        "timestamp": formatter.string(from: Date()),
      ],
    ]
    guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
      return
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    callbackSession.dataTask(with: request).resume()
  }

  private func bridgeObject(_ provider: ExternalCommandProviderRecord) -> [String: Any] {
    var object = provider.publicObject
    object["commands"] = provider.commands.map { command in
      var commandObject = command.publicObject
      if command.icon?.type == "sf-symbol",
        let name = command.icon?.name,
        let image = symbolDataURL(name)
      {
        commandObject["symbolImageDataURL"] = image
      }
      return commandObject
    }
    return object
  }

  private func symbolDataURL(_ name: String) -> String? {
    if let cached = symbolImageCache[name] { return cached }
    if unavailableSymbolNames.contains(name) { return nil }

    let create = {
      guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
        let configured = symbol.withSymbolConfiguration(
          NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        )
      else {
        return nil as String?
      }
      configured.size = NSSize(width: 24, height: 24)
      guard let tiff = configured.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
      else {
        return nil
      }
      return "data:image/png;base64,\(png.base64EncodedString())"
    }
    let result = Thread.isMainThread ? create() : DispatchQueue.main.sync(execute: create)
    if let result {
      symbolImageCache[name] = result
    } else {
      unavailableSymbolNames.insert(name)
    }
    return result
  }

  private var persistenceURL: URL {
    let base =
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support", isDirectory: true)
    return
      base
      .appendingPathComponent(
        Bundle.main.bundleIdentifier ?? "com.ospfranco.sol", isDirectory: true
      )
      .appendingPathComponent("external-command-providers-v1.json", isDirectory: false)
  }

  private func loadPersistedProviders() {
    let url = persistenceURL
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
      let data = try Data(contentsOf: url)
      let file = try JSONDecoder().decode(ExternalCommandProviderFile.self, from: data)
      guard file.version == 1 else {
        NSLog("Unsupported external command provider file version: \(file.version)")
        return
      }
      providers = file.providers.reduce(into: [:]) { result, provider in
        guard persistedProviderIsValid(provider) else { return }
        result[provider.providerID] = provider
      }
    } catch {
      NSLog("Could not load external command providers: \(error.localizedDescription)")
    }
  }

  private func persist(_ records: [String: ExternalCommandProviderRecord]) throws {
    let url = persistenceURL
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil
    )
    let file = ExternalCommandProviderFile(
      version: 1,
      providers: records.values.sorted {
        $0.providerID.localizedStandardCompare($1.providerID) == .orderedAscending
      }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(file)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o600))],
      ofItemAtPath: url.path
    )
  }

  private func persistedProviderIsValid(_ provider: ExternalCommandProviderRecord) -> Bool {
    guard
      provider.providerID.range(
        of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#,
        options: .regularExpression
      ) != nil,
      !provider.providerName.isEmpty,
      provider.providerName.count <= 200,
      provider.pid > 0,
      provider.processFingerprint.count == 64,
      provider.processFingerprint.allSatisfy({ $0.isHexDigit }),
      !provider.commands.isEmpty,
      provider.commands.count <= 1_000
    else {
      return false
    }

    var names = Set<String>()
    for command in provider.commands {
      guard command.name.count <= 100,
        command.name.range(
          of: #"^[a-z0-9][a-z0-9._-]*$"#,
          options: .regularExpression
        ) != nil,
        names.insert(command.name.lowercased()).inserted,
        !command.label.isEmpty,
        command.label.count <= 500,
        (command.detail?.count ?? 0) <= 2_000,
        externalCallbackURL(command.endpoint) != nil
      else {
        return false
      }
      if let icon = command.icon {
        switch icon.type {
        case "sf-symbol":
          guard let name = icon.name, !name.isEmpty, name.count <= 200,
            icon.value == nil
          else { return false }
        case "emoji":
          guard let value = icon.value, value.count == 1, icon.name == nil else {
            return false
          }
        default:
          return false
        }
      }
    }
    return true
  }

  private func persistBestEffort() {
    do {
      try persist(providers)
    } catch {
      NSLog("Could not persist external command providers: \(error.localizedDescription)")
    }
  }

  private func emitChange() {
    DispatchQueue.main.async {
      SolEmitter.sharedInstance.dispatch(
        name: "externalCommandProvidersChanged",
        body: []
      )
    }
  }
}
