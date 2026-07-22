import AppKit
import Foundation
import Network
import Security

struct SolAPIConfiguration {
  let endpoint: URL
  let port: NWEndpoint.Port
  let token: String
}

private enum SolAPIConfigurationError: LocalizedError {
  case invalid(String)
  case randomTokenGeneration(OSStatus)

  var errorDescription: String? {
    switch self {
    case let .invalid(message):
      return message
    case let .randomTokenGeneration(status):
      return "Could not generate the Sol API token (Security status \(status))."
    }
  }
}

enum SolAPIConfigurationLoader {
  static let defaultEndpoint = "http://127.0.0.1:17321"
  static let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".sol.yml", isDirectory: false)

  private struct ParsedConfiguration {
    var version: String?
    var api: [String: String]
  }

  static func loadOrCreate() throws -> SolAPIConfiguration? {
    let fileManager = FileManager.default
    var contents: String

    if fileManager.fileExists(atPath: configURL.path) {
      contents = try String(contentsOf: configURL, encoding: .utf8)
    } else {
      contents = canonicalConfiguration(token: try generateToken())
      try write(contents)
    }

    var parsed = try parse(contents)
    var lines = contents.components(separatedBy: .newlines)
    var changed = false

    if parsed.version == nil {
      lines.insert(contentsOf: ["version: 1", ""], at: 0)
      changed = true
    }

    if parsed.api.isEmpty && !containsAPISection(lines) {
      if lines.last?.isEmpty == false {
        lines.append("")
      }
      lines.append(contentsOf: [
        "api:",
        "  enabled: true",
        "  endpoint: \"\(defaultEndpoint)\"",
        "  token: \"\(try generateToken())\"",
      ])
      changed = true
    } else {
      var additions: [String] = []
      if parsed.api["enabled"] == nil {
        additions.append("  enabled: true")
      }
      if parsed.api["endpoint"] == nil {
        additions.append("  endpoint: \"\(defaultEndpoint)\"")
      }
      if parsed.api["token"] == nil {
        additions.append("  token: \"\(try generateToken())\"")
      }
      if !additions.isEmpty {
        try insertAPIAdditions(additions, into: &lines)
        changed = true
      }
    }

    if changed {
      contents = lines.joined(separator: "\n")
      if !contents.hasSuffix("\n") {
        contents.append("\n")
      }
      try write(contents)
      parsed = try parse(contents)
    } else {
      try enforcePrivatePermissions()
    }

    guard parsed.version == "1" else {
      throw SolAPIConfigurationError.invalid(
        "~/.sol.yml: version must be 1."
      )
    }

    let enabledValue = parsed.api["enabled"] ?? "true"
    guard enabledValue == "true" || enabledValue == "false" else {
      throw SolAPIConfigurationError.invalid(
        "~/.sol.yml: api.enabled must be true or false."
      )
    }
    guard enabledValue == "true" else { return nil }

    guard let endpointValue = parsed.api["endpoint"],
      let components = URLComponents(string: endpointValue),
      components.scheme == "http",
      components.host == "127.0.0.1",
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      components.path.isEmpty || components.path == "/",
      let portValue = components.port,
      (1 ... Int(UInt16.max)).contains(portValue),
      let port = NWEndpoint.Port(rawValue: UInt16(portValue)),
      let endpoint = components.url
    else {
      throw SolAPIConfigurationError.invalid(
        "~/.sol.yml: api.endpoint must be http://127.0.0.1:<port>."
      )
    }

    guard let token = parsed.api["token"],
      token.count == 64,
      token.unicodeScalars.allSatisfy({ scalar in
        (48 ... 57).contains(scalar.value) || (97 ... 102).contains(scalar.value)
          || (65 ... 70).contains(scalar.value)
      })
    else {
      throw SolAPIConfigurationError.invalid(
        "~/.sol.yml: api.token must contain exactly 64 hexadecimal characters."
      )
    }

    return SolAPIConfiguration(endpoint: endpoint, port: port, token: token)
  }

  private static func canonicalConfiguration(token: String) -> String {
    """
    version: 1

    api:
      enabled: true
      endpoint: "\(defaultEndpoint)"
      token: "\(token)"
    """ + "\n"
  }

  private static func write(_ contents: String) throws {
    try contents.write(to: configURL, atomically: true, encoding: .utf8)
    try enforcePrivatePermissions()
  }

  private static func enforcePrivatePermissions() throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o600))],
      ofItemAtPath: configURL.path
    )
  }

  private static func generateToken() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      throw SolAPIConfigurationError.randomTokenGeneration(status)
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }

  private static func containsAPISection(_ lines: [String]) -> Bool {
    lines.contains { line in
      let trimmed = stripComment(from: line).trimmingCharacters(in: .whitespaces)
      return trimmed == "api:" && line.prefix { $0 == " " }.isEmpty
    }
  }

  private static func insertAPIAdditions(_ additions: [String], into lines: inout [String]) throws {
    guard let apiIndex = lines.firstIndex(where: { line in
      let trimmed = stripComment(from: line).trimmingCharacters(in: .whitespaces)
      return trimmed == "api:" && line.prefix { $0 == " " }.isEmpty
    }) else {
      throw SolAPIConfigurationError.invalid("~/.sol.yml: invalid api section.")
    }

    var insertionIndex = lines.count
    if apiIndex + 1 < lines.count {
      for index in (apiIndex + 1) ..< lines.count {
        let line = lines[index]
        let uncommented = stripComment(from: line)
        if uncommented.trimmingCharacters(in: .whitespaces).isEmpty {
          continue
        }
        if !line.hasPrefix(" ") {
          insertionIndex = index
          break
        }
      }
    }
    lines.insert(contentsOf: additions, at: insertionIndex)
  }

  private static func parse(_ contents: String) throws -> ParsedConfiguration {
    var version: String?
    var api: [String: String] = [:]
    var inAPISection = false

    for (lineNumber, originalLine) in contents.components(separatedBy: .newlines).enumerated() {
      let line = stripComment(from: originalLine)
      if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        continue
      }
      if line.contains("\t") {
        throw SolAPIConfigurationError.invalid(
          "~/.sol.yml:\(lineNumber + 1): tabs are not supported."
        )
      }

      let indentation = line.prefix { $0 == " " }.count
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard let separator = trimmed.firstIndex(of: ":") else {
        throw SolAPIConfigurationError.invalid(
          "~/.sol.yml:\(lineNumber + 1): expected key: value."
        )
      }
      let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
      let rawValue = String(trimmed[trimmed.index(after: separator)...])
        .trimmingCharacters(in: .whitespaces)

      if indentation == 0 {
        inAPISection = key == "api" && rawValue.isEmpty
        if key == "version" {
          guard version == nil else {
            throw SolAPIConfigurationError.invalid(
              "~/.sol.yml:\(lineNumber + 1): duplicate version."
            )
          }
          version = unquote(rawValue)
        }
        continue
      }

      guard inAPISection else { continue }
      guard indentation >= 2, !rawValue.isEmpty else {
        throw SolAPIConfigurationError.invalid(
          "~/.sol.yml:\(lineNumber + 1): invalid api value."
        )
      }
      guard api[key] == nil else {
        throw SolAPIConfigurationError.invalid(
          "~/.sol.yml:\(lineNumber + 1): duplicate api.\(key)."
        )
      }
      api[key] = unquote(rawValue)
    }

    return ParsedConfiguration(version: version, api: api)
  }

  private static func unquote(_ value: String) -> String {
    guard value.count >= 2 else { return value }
    if (value.hasPrefix("\"") && value.hasSuffix("\""))
      || (value.hasPrefix("'") && value.hasSuffix("'"))
    {
      return String(value.dropFirst().dropLast())
    }
    return value
  }

  private static func stripComment(from line: String) -> String {
    var quote: Character?
    var escaped = false
    for index in line.indices {
      let character = line[index]
      if escaped {
        escaped = false
        continue
      }
      if character == "\\", quote == "\"" {
        escaped = true
        continue
      }
      if character == "\"" || character == "'" {
        if quote == character {
          quote = nil
        } else if quote == nil {
          quote = character
        }
        continue
      }
      if character == "#", quote == nil {
        return String(line[..<index])
      }
    }
    return line
  }
}

struct SolHTTPRequest {
  let method: String
  let target: String
  let path: String
  let headers: [String: String]
  let body: Data

  func jsonObject() throws -> Any {
    guard !body.isEmpty else {
      throw SolHTTPAPIError(
        status: 400,
        code: "invalid_json",
        message: "A JSON request body is required."
      )
    }
    do {
      return try JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])
    } catch {
      throw SolHTTPAPIError(
        status: 400,
        code: "invalid_json",
        message: "The request body is not valid JSON."
      )
    }
  }
}

struct SolHTTPAPIError: Error {
  let status: Int
  let code: String
  let message: String
  let field: String?

  init(status: Int, code: String, message: String, field: String? = nil) {
    self.status = status
    self.code = code
    self.message = message
    self.field = field
  }
}

struct SolHTTPResponse {
  let status: Int
  let body: Data

  static func json(status: Int = 200, _ object: Any) -> SolHTTPResponse {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
      ?? Data("{\"error\":{\"code\":\"api_unavailable\",\"message\":\"Could not encode the response.\"}}".utf8)
    return SolHTTPResponse(status: status, body: data)
  }

  static func error(_ error: SolHTTPAPIError) -> SolHTTPResponse {
    var payload: [String: Any] = [
      "code": error.code,
      "message": error.message,
    ]
    if let field = error.field {
      payload["field"] = field
    }
    return .json(status: error.status, ["error": payload])
  }
}

final class SolHTTPRequestContext {
  private let lock = NSLock()
  private weak var connection: SolHTTPConnection?
  private var disconnectHandler: (() -> Void)?
  private var completed = false
  private var disconnected = false

  fileprivate init(connection: SolHTTPConnection) {
    self.connection = connection
  }

  func respond(_ response: SolHTTPResponse) {
    lock.lock()
    guard !completed, !disconnected else {
      lock.unlock()
      return
    }
    completed = true
    let connection = connection
    lock.unlock()
    connection?.send(response)
  }

  func onDisconnect(_ handler: @escaping () -> Void) {
    lock.lock()
    if disconnected {
      lock.unlock()
      handler()
      return
    }
    disconnectHandler = handler
    lock.unlock()
  }

  fileprivate func notifyDisconnected() {
    lock.lock()
    guard !completed, !disconnected else {
      lock.unlock()
      return
    }
    disconnected = true
    let handler = disconnectHandler
    disconnectHandler = nil
    lock.unlock()
    handler?()
  }
}

protocol SolHTTPRouteHandler: AnyObject {
  func handle(_ request: SolHTTPRequest, context: SolHTTPRequestContext) -> Bool
}

final class ExternalIntegrationServer {
  static let shared = ExternalIntegrationServer()

  private let queue = DispatchQueue(label: "com.ospfranco.sol.external-api")
  private var listener: NWListener?
  private var connections: [ObjectIdentifier: SolHTTPConnection] = [:]
  private var handlers: [SolHTTPRouteHandler] = []
  private var configuration: SolAPIConfiguration?

  private init() {}

  func register(_ handler: SolHTTPRouteHandler) {
    handlers.append(handler)
  }

  func start() {
    guard listener == nil else { return }
    do {
      guard let configuration = try SolAPIConfigurationLoader.loadOrCreate() else {
        NSLog("Sol external API is disabled in ~/.sol.yml")
        return
      }
      self.configuration = configuration

      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = .hostPort(
        host: NWEndpoint.Host("127.0.0.1"),
        port: configuration.port
      )
      let listener = try NWListener(using: parameters)
      self.listener = listener
      listener.newConnectionHandler = { [weak self] connection in
        self?.accept(connection)
      }
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          NSLog("Sol external API listening on \(configuration.endpoint.absoluteString)")
        case let .failed(error):
          NSLog("Sol external API failed: \(error.localizedDescription)")
          DispatchQueue.main.async {
            ToastManager.shared.showToast(
              "Sol API could not start on \(configuration.endpoint.absoluteString)",
              variant: "error",
              timeout: 6,
              image: nil
            )
          }
        default:
          break
        }
      }
      listener.start(queue: queue)
    } catch {
      NSLog("Sol external API configuration error: \(error.localizedDescription)")
      DispatchQueue.main.async {
        ToastManager.shared.showToast(
          error.localizedDescription,
          variant: "error",
          timeout: 7,
          image: nil
        )
      }
    }
  }

  func stop() {
    queue.async { [weak self] in
      guard let self else { return }
      listener?.cancel()
      listener = nil
      for connection in connections.values {
        connection.cancel()
      }
      connections.removeAll()
    }
  }

  private func accept(_ networkConnection: NWConnection) {
    let client = SolHTTPConnection(
      connection: networkConnection,
      queue: queue,
      requestHandler: { [weak self] request, context in
        self?.route(request, context: context)
      },
      finishHandler: { [weak self] identifier in
        self?.connections.removeValue(forKey: identifier)
      }
    )
    connections[client.identifier] = client
    client.start()
  }

  private func route(_ request: SolHTTPRequest, context: SolHTTPRequestContext) {
    guard let configuration else {
      context.respond(.error(SolHTTPAPIError(
        status: 503,
        code: "api_unavailable",
        message: "The Sol API is unavailable."
      )))
      return
    }

    if request.headers["origin"] != nil {
      context.respond(.error(SolHTTPAPIError(
        status: 401,
        code: "unauthorized",
        message: "Browser-originated requests are not accepted."
      )))
      return
    }

    let expectedAuthorization = "Bearer \(configuration.token)"
    guard let authorization = request.headers["authorization"],
      constantTimeEqual(authorization, expectedAuthorization)
    else {
      context.respond(.error(SolHTTPAPIError(
        status: 401,
        code: "unauthorized",
        message: "The Bearer token is missing or invalid."
      )))
      return
    }

    if request.method == "GET", request.path == "/v1/health" {
      context.respond(.json(["status": "ok", "apiVersion": 1]))
      return
    }

    if !request.body.isEmpty {
      let contentType = request.headers["content-type"]?.lowercased() ?? ""
      guard contentType.hasPrefix("application/json") else {
        context.respond(.error(SolHTTPAPIError(
          status: 422,
          code: "invalid_field",
          message: "Content-Type must be application/json.",
          field: "Content-Type"
        )))
        return
      }
    }

    for handler in handlers where handler.handle(request, context: context) {
      return
    }

    context.respond(.error(SolHTTPAPIError(
      status: 404,
      code: "not_found",
      message: "No Sol API route matches this request."
    )))
  }

  private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    guard left.count == right.count else { return false }
    var difference: UInt8 = 0
    for index in left.indices {
      difference |= left[index] ^ right[index]
    }
    return difference == 0
  }
}

final class SolHTTPConnection {
  private static let maximumHeaderBytes = 64 * 1024
  private static let maximumBodyBytes = 1_048_576

  let identifier: ObjectIdentifier
  private let connection: NWConnection
  private let queue: DispatchQueue
  private let requestHandler: (SolHTTPRequest, SolHTTPRequestContext) -> Void
  private let finishHandler: (ObjectIdentifier) -> Void
  private var buffer = Data()
  private var didDispatchRequest = false
  private var didFinish = false
  private var didStartResponse = false
  private var context: SolHTTPRequestContext?

  init(
    connection: NWConnection,
    queue: DispatchQueue,
    requestHandler: @escaping (SolHTTPRequest, SolHTTPRequestContext) -> Void,
    finishHandler: @escaping (ObjectIdentifier) -> Void
  ) {
    self.connection = connection
    self.queue = queue
    self.requestHandler = requestHandler
    self.finishHandler = finishHandler
    identifier = ObjectIdentifier(connection)
  }

  func start() {
    connection.stateUpdateHandler = { [weak self] state in
      switch state {
      case .failed, .cancelled:
        self?.finish(notifyDisconnect: true)
      default:
        break
      }
    }
    connection.start(queue: queue)
    receiveNext()
  }

  func cancel() {
    queue.async { [weak self] in
      self?.finish(notifyDisconnect: true)
    }
  }

  func send(_ response: SolHTTPResponse) {
    queue.async { [weak self] in
      guard let self, !didFinish, !didStartResponse else { return }
      didStartResponse = true
      let statusText = Self.statusText(response.status)
      let headers = """
      HTTP/1.1 \(response.status) \(statusText)\r
      Content-Type: application/json; charset=utf-8\r
      Content-Length: \(response.body.count)\r
      Cache-Control: no-store\r
      Connection: close\r
      \r
      """
      var payload = Data(headers.utf8)
      payload.append(response.body)
      connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
        self?.queue.async {
          self?.finish(notifyDisconnect: false)
        }
      })
    }
  }

  private func receiveNext() {
    guard !didFinish else { return }
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      [weak self] data, _, complete, error in
      guard let self else { return }
      if let data, !data.isEmpty, !didDispatchRequest {
        buffer.append(data)
        parseIfComplete()
      }
      if error != nil || complete {
        finish(notifyDisconnect: true)
        return
      }
      receiveNext()
    }
  }

  private func parseIfComplete() {
    let delimiter = Data("\r\n\r\n".utf8)
    guard let headerRange = buffer.range(of: delimiter) else {
      if buffer.count > Self.maximumHeaderBytes {
        send(.error(SolHTTPAPIError(
          status: 400,
          code: "invalid_json",
          message: "HTTP headers are too large."
        )))
      }
      return
    }

    guard headerRange.lowerBound <= Self.maximumHeaderBytes,
      let headerString = String(
        data: buffer.subdata(in: 0 ..< headerRange.lowerBound),
        encoding: .utf8
      )
    else {
      send(.error(SolHTTPAPIError(
        status: 400,
        code: "invalid_json",
        message: "HTTP headers are invalid."
      )))
      return
    }

    let lines = headerString.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else { return }
    let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
    guard requestParts.count == 3, requestParts[2].hasPrefix("HTTP/1.") else {
      send(.error(SolHTTPAPIError(
        status: 400,
        code: "invalid_json",
        message: "The HTTP request line is invalid."
      )))
      return
    }

    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let separator = line.firstIndex(of: ":") else {
        send(.error(SolHTTPAPIError(
          status: 400,
          code: "invalid_json",
          message: "An HTTP header is invalid."
        )))
        return
      }
      let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
      let value = line[line.index(after: separator)...]
        .trimmingCharacters(in: .whitespaces)
      headers[name] = value
    }

    if headers["transfer-encoding"] != nil {
      send(.error(SolHTTPAPIError(
        status: 400,
        code: "invalid_json",
        message: "Chunked request bodies are not supported."
      )))
      return
    }

    let contentLength: Int
    if let rawLength = headers["content-length"] {
      guard let parsedLength = Int(rawLength), parsedLength >= 0 else {
        send(.error(SolHTTPAPIError(
          status: 400,
          code: "invalid_json",
          message: "Content-Length is invalid."
        )))
        return
      }
      contentLength = parsedLength
    } else {
      contentLength = 0
    }

    guard contentLength <= Self.maximumBodyBytes else {
      send(.error(SolHTTPAPIError(
        status: 413,
        code: "content_too_large",
        message: "The request body exceeds 1048576 bytes."
      )))
      return
    }

    let bodyStart = headerRange.upperBound
    guard buffer.count >= bodyStart + contentLength else { return }
    let body = buffer.subdata(in: bodyStart ..< bodyStart + contentLength)
    let target = requestParts[1]
    let path = URLComponents(string: "http://127.0.0.1\(target)")?.path ?? target
    let request = SolHTTPRequest(
      method: requestParts[0].uppercased(),
      target: target,
      path: path,
      headers: headers,
      body: body
    )

    didDispatchRequest = true
    let requestContext = SolHTTPRequestContext(connection: self)
    context = requestContext
    requestHandler(request, requestContext)
  }

  private func finish(notifyDisconnect: Bool) {
    guard !didFinish else { return }
    didFinish = true
    if notifyDisconnect, !didStartResponse {
      context?.notifyDisconnected()
    }
    connection.stateUpdateHandler = nil
    connection.cancel()
    finishHandler(identifier)
  }

  private static func statusText(_ status: Int) -> String {
    switch status {
    case 200: return "OK"
    case 201: return "Created"
    case 204: return "No Content"
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 404: return "Not Found"
    case 409: return "Conflict"
    case 413: return "Content Too Large"
    case 422: return "Unprocessable Content"
    case 503: return "Service Unavailable"
    default: return "Response"
    }
  }
}
