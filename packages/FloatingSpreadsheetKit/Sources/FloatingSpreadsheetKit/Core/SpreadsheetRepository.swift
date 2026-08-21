import Foundation

enum SpreadsheetRepositoryError: LocalizedError {
  case invalidIdentifier
  case documentNotFound

  var errorDescription: String? {
    switch self {
    case .invalidIdentifier: return "The spreadsheet identifier is invalid."
    case .documentNotFound: return "The saved spreadsheet could not be found."
    }
  }
}

final class SpreadsheetRepository {
  private let fileManager: FileManager
  private let rootDirectory: URL
  private let queue = DispatchQueue(
    label: "com.ospfranco.sol.floating-spreadsheets.persistence",
    qos: .utility
  )
  private let pendingLock = NSLock()
  private var pendingSaves: [UUID: DispatchWorkItem] = [:]

  init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
    self.fileManager = fileManager
    if let rootDirectory {
      self.rootDirectory = rootDirectory
    } else {
      let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? fileManager.homeDirectoryForCurrentUser
      self.rootDirectory = applicationSupport
        .appendingPathComponent("Sol", isDirectory: true)
        .appendingPathComponent("FloatingSpreadsheets", isDirectory: true)
    }

  }

  func createDocument(now: Date = Date()) throws -> SpreadsheetDocument {
    try prepareDirectory()
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    let document = SpreadsheetDocument(
      name: "Sheet — \(formatter.string(from: now))",
      now: now
    )
    attach(document)
    try saveImmediately(document)
    return document
  }

  func loadDocument(id: UUID) throws -> SpreadsheetDocument {
    let url = try documentURL(id: id)
    guard fileManager.fileExists(atPath: url.path) else {
      throw SpreadsheetRepositoryError.documentNotFound
    }
    let payload = try makeDecoder().decode(
      SpreadsheetPayload.self,
      from: Data(contentsOf: url)
    )
    let document = SpreadsheetDocument(payload: payload)
    attach(document)
    return document
  }

  func loadSummaries() throws -> [FloatingSpreadsheetSummary] {
    try prepareDirectory()
    let urls = try fileManager.contentsOfDirectory(
      at: rootDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    return urls
      .filter { $0.pathExtension.lowercased() == "json" }
      .compactMap { url in
        guard let data = try? Data(contentsOf: url),
          let payload = try? makeDecoder().decode(SpreadsheetPayload.self, from: data)
        else {
          return nil
        }
        return FloatingSpreadsheetSummary(payload: payload)
      }
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  func deleteDocument(id: UUID) throws {
    cancelPendingSave(id: id)
    let url = try documentURL(id: id)
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  func scheduleSave(_ document: SpreadsheetDocument, delay: TimeInterval = 0.35) {
    let payload = document.payload
    pendingLock.lock()
    pendingSaves[id: document.id]?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      try? self.write(payload)
    }
    pendingSaves[document.id] = work
    pendingLock.unlock()
    queue.asyncAfter(deadline: .now() + delay, execute: work)
  }

  func saveImmediately(_ document: SpreadsheetDocument) throws {
    cancelPendingSave(id: document.id)
    let payload = document.payload
    try queue.sync {
      try write(payload)
    }
  }

  func flush(_ documents: [SpreadsheetDocument]) {
    for document in documents {
      try? saveImmediately(document)
    }
  }

  private func attach(_ document: SpreadsheetDocument) {
    document.onChange = { [weak self] changedDocument in
      self?.scheduleSave(changedDocument)
    }
  }

  private func cancelPendingSave(id: UUID) {
    pendingLock.lock()
    pendingSaves[id]?.cancel()
    pendingSaves.removeValue(forKey: id)
    pendingLock.unlock()
  }

  private func prepareDirectory() throws {
    try fileManager.createDirectory(
      at: rootDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try? fileManager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: rootDirectory.path
    )
  }

  private func documentURL(id: UUID) throws -> URL {
    guard UUID(uuidString: id.uuidString) != nil else {
      throw SpreadsheetRepositoryError.invalidIdentifier
    }
    return rootDirectory.appendingPathComponent("\(id.uuidString.lowercased()).json")
  }

  private func write(_ payload: SpreadsheetPayload) throws {
    try prepareDirectory()
    let data = try makeEncoder().encode(payload)
    let url = try documentURL(id: payload.id)
    try data.write(to: url, options: .atomic)
    try? fileManager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
  }

  private func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .millisecondsSince1970
    return encoder
  }

  private func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }
}
