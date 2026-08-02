import Foundation

private enum AIStreamingTransportError: LocalizedError {
  case message(String)

  var errorDescription: String? {
    switch self {
    case .message(let message):
      return message
    }
  }
}

private enum AIStreamOutcome {
  case completed(cancelled: Bool)
  case failed(message: String, status: Int?, body: String?)
}

private final class AIStreamConnection: NSObject, URLSessionDataDelegate {
  private let request: URLRequest
  private let onPayload: (String) -> Void
  private let onFinish: (AIStreamOutcome) -> Void
  private let delegateQueue: OperationQueue

  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var statusCode: Int?
  private var errorBody = Data()
  private var lineBuffer = Data()
  private var eventDataLines: [String] = []
  private var previousByteWasCR = false
  private var finished = false

  init(
    requestID: String,
    request: URLRequest,
    onPayload: @escaping (String) -> Void,
    onFinish: @escaping (AIStreamOutcome) -> Void
  ) {
    self.request = request
    self.onPayload = onPayload
    self.onFinish = onFinish
    delegateQueue = OperationQueue()
    delegateQueue.name = "com.ospfranco.sol.ai-stream.\(requestID)"
    delegateQueue.maxConcurrentOperationCount = 1
    super.init()
  }

  func start() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 600
    configuration.timeoutIntervalForResource = 3600

    let session = URLSession(
      configuration: configuration,
      delegate: self,
      delegateQueue: delegateQueue
    )
    self.session = session
    let task = session.dataTask(with: request)
    self.task = task
    task.resume()
  }

  func cancel() {
    task?.cancel()
  }

  func urlSession(
    _: URLSession,
    dataTask _: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    statusCode = (response as? HTTPURLResponse)?.statusCode
    completionHandler(.allow)
  }

  func urlSession(
    _: URLSession,
    dataTask _: URLSessionDataTask,
    didReceive data: Data
  ) {
    guard let statusCode, (200 ... 299).contains(statusCode) else {
      let remainingCapacity = max(0, 131_072 - errorBody.count)
      if remainingCapacity > 0 {
        errorBody.append(contentsOf: data.prefix(remainingCapacity))
      }
      return
    }

    consumeSSEBytes(data)
  }

  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard !finished else { return }
    finished = true

    if let urlError = error as? URLError, urlError.code == .cancelled {
      finish(.completed(cancelled: true))
      return
    }

    if let error {
      finish(.failed(message: error.localizedDescription, status: statusCode, body: nil))
      return
    }

    guard let statusCode else {
      finish(.failed(message: "The AI server returned no HTTP response.", status: nil, body: nil))
      return
    }

    guard (200 ... 299).contains(statusCode) else {
      let body = errorBody.isEmpty ? nil : String(data: errorBody, encoding: .utf8)
      finish(
        .failed(
          message: "The AI server returned HTTP \(statusCode).",
          status: statusCode,
          body: body
        )
      )
      return
    }

    flushSSEBuffer()
    finish(.completed(cancelled: false))
  }

  private func consumeSSEBytes(_ data: Data) {
    for byte in data {
      switch byte {
      case 13:
        consumeSSELine()
        previousByteWasCR = true
      case 10:
        if previousByteWasCR {
          previousByteWasCR = false
        } else {
          consumeSSELine()
        }
      default:
        previousByteWasCR = false
        lineBuffer.append(byte)
      }
    }
  }

  private func consumeSSELine() {
    guard !lineBuffer.isEmpty else {
      emitCurrentEvent()
      return
    }

    defer { lineBuffer.removeAll(keepingCapacity: true) }
    guard let line = String(data: lineBuffer, encoding: .utf8) else { return }
    if line == "data" {
      eventDataLines.append("")
      return
    }
    guard line.hasPrefix("data:") else { return }

    var value = String(line.dropFirst(5))
    if value.first == " " {
      value.removeFirst()
    }
    eventDataLines.append(value)
  }

  private func emitCurrentEvent() {
    guard !eventDataLines.isEmpty else { return }
    let payload = eventDataLines.joined(separator: "\n")
    eventDataLines.removeAll(keepingCapacity: true)
    onPayload(payload)
  }

  private func flushSSEBuffer() {
    if !lineBuffer.isEmpty {
      consumeSSELine()
    }
    emitCurrentEvent()
  }

  private func finish(_ outcome: AIStreamOutcome) {
    session?.finishTasksAndInvalidate()
    task = nil
    session = nil
    onFinish(outcome)
  }
}

final class AIStreamingManager {
  static let shared = AIStreamingManager()

  private let lock = NSLock()
  private var connections: [String: AIStreamConnection] = [:]

  private init() {}

  func start(options: [String: Any]) throws -> String {
    guard
      let requestID = options["requestID"] as? String,
      !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw AIStreamingTransportError.message("The AI stream request has no identifier.")
    }
    guard
      let endpoint = options["endpoint"] as? String,
      let url = URL(string: endpoint),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else {
      throw AIStreamingTransportError.message("The AI stream endpoint is invalid.")
    }
    guard let body = options["body"], JSONSerialization.isValidJSONObject(body) else {
      throw AIStreamingTransportError.message("The AI stream body is invalid.")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    request.timeoutInterval = 600

    if let headers = options["headers"] as? [String: Any] {
      for (name, value) in headers {
        guard let stringValue = value as? String else { continue }
        request.setValue(stringValue, forHTTPHeaderField: name)
      }
    }
    if request.value(forHTTPHeaderField: "Content-Type") == nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if request.value(forHTTPHeaderField: "Accept") == nil {
      request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    }

    let connection = AIStreamConnection(
      requestID: requestID,
      request: request,
      onPayload: { payload in
        self.emit(
          name: "aiStreamData",
          body: ["requestID": requestID, "data": payload]
        )
      },
      onFinish: { outcome in
        self.finish(requestID: requestID, outcome: outcome)
      }
    )

    lock.lock()
    guard connections[requestID] == nil else {
      lock.unlock()
      throw AIStreamingTransportError.message("The AI stream identifier is already active.")
    }
    connections[requestID] = connection
    lock.unlock()

    connection.start()
    return requestID
  }

  func cancel(requestID: String) {
    lock.lock()
    let connection = connections[requestID]
    lock.unlock()
    connection?.cancel()
  }

  private func finish(requestID: String, outcome: AIStreamOutcome) {
    lock.lock()
    connections.removeValue(forKey: requestID)
    lock.unlock()

    switch outcome {
    case .completed(let cancelled):
      emit(
        name: "aiStreamCompleted",
        body: ["requestID": requestID, "cancelled": cancelled]
      )
    case .failed(let message, let status, let body):
      var event: [String: Any] = [
        "requestID": requestID,
        "message": message,
      ]
      if let status {
        event["status"] = status
      }
      if let body {
        event["body"] = body
      }
      emit(name: "aiStreamFailed", body: event)
    }
  }

  private func emit(name: String, body: [String: Any]) {
    DispatchQueue.main.async {
      SolEmitter.sharedInstance.dispatch(name: name, body: body)
    }
  }
}
