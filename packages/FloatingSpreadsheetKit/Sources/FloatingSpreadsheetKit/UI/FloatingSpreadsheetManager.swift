import AppKit

public final class FloatingSpreadsheetManager {
  public static let shared = FloatingSpreadsheetManager()

  private let repository = SpreadsheetRepository()
  private var documents: [UUID: SpreadsheetDocument] = [:]
  private var spreadsheetWindows: [UUID: SpreadsheetWindowController] = [:]
  private var chartWindows: [UUID: SpreadsheetChartWindowController] = [:]
  private var terminationObserver: NSObjectProtocol?

  private init() {
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.repository.flush(Array(self.documents.values))
    }
  }

  deinit {
    if let terminationObserver {
      NotificationCenter.default.removeObserver(terminationObserver)
    }
  }

  @discardableResult
  public func createSpreadsheet() throws -> FloatingSpreadsheetSummary {
    try onMain {
      let document = try repository.createDocument()
      documents[document.id] = document
      presentSpreadsheet(document)
      return document.summary
    }
  }

  public func savedSpreadsheets() throws -> [FloatingSpreadsheetSummary] {
    try repository.loadSummaries()
  }

  @discardableResult
  public func reopenSpreadsheet(id identifier: String) throws -> FloatingSpreadsheetSummary {
    try onMain {
      guard let id = UUID(uuidString: identifier) else {
        throw SpreadsheetRepositoryError.invalidIdentifier
      }
      let document = try loadedDocument(id: id)
      presentSpreadsheet(document)
      return document.summary
    }
  }

  @discardableResult
  public func renameSpreadsheet(
    id identifier: String,
    name: String
  ) throws -> FloatingSpreadsheetSummary {
    try onMain {
      guard let id = UUID(uuidString: identifier) else {
        throw SpreadsheetRepositoryError.invalidIdentifier
      }
      let wasLoaded = documents[id] != nil
      let document = try loadedDocument(id: id)
      document.rename(to: name)
      try repository.saveImmediately(document)
      releaseDocumentIfUnused(id: id, wasLoadedBeforeOperation: wasLoaded)
      return document.summary
    }
  }

  public func deleteSpreadsheet(id identifier: String) throws {
    try onMain {
      guard let id = UUID(uuidString: identifier) else {
        throw SpreadsheetRepositoryError.invalidIdentifier
      }

      if let sheetWindow = spreadsheetWindows[id] {
        sheetWindow.closeWindow()
      }
      let relatedCharts = chartWindows.values.filter { $0.documentID == id }
      for chartWindow in relatedCharts {
        chartWindow.closeWindow()
      }
      documents.removeValue(forKey: id)
      try repository.deleteDocument(id: id)
    }
  }

  private func loadedDocument(id: UUID) throws -> SpreadsheetDocument {
    if let document = documents[id] { return document }
    let document = try repository.loadDocument(id: id)
    documents[id] = document
    return document
  }

  private func presentSpreadsheet(_ document: SpreadsheetDocument) {
    if let existing = spreadsheetWindows[document.id] {
      existing.bringToFront()
      return
    }

    let controller = SpreadsheetWindowController(document: document)
    controller.onClose = { [weak self, weak controller] in
      guard let self else { return }
      try? self.repository.saveImmediately(document)
      if self.spreadsheetWindows[document.id] === controller {
        self.spreadsheetWindows.removeValue(forKey: document.id)
      }
      self.releaseDocumentIfUnused(id: document.id)
    }
    controller.onOpenChart = { [weak self] chart in
      self?.presentChart(chart, document: document)
    }
    spreadsheetWindows[document.id] = controller
    controller.presentCentered()
  }

  private func presentChart(
    _ chart: SpreadsheetChartDefinition,
    document: SpreadsheetDocument
  ) {
    if let existing = chartWindows[chart.id] {
      existing.bringToFront()
      return
    }

    let controller = SpreadsheetChartWindowController(
      document: document,
      chartID: chart.id
    )
    controller.onReturnToSpreadsheet = { [weak self] in
      self?.presentSpreadsheet(document)
    }
    controller.onClose = { [weak self, weak controller] in
      guard let self else { return }
      try? self.repository.saveImmediately(document)
      if self.chartWindows[chart.id] === controller {
        self.chartWindows.removeValue(forKey: chart.id)
      }
      self.releaseDocumentIfUnused(id: document.id)
    }
    chartWindows[chart.id] = controller
    controller.presentCentered()
  }

  private func releaseDocumentIfUnused(
    id: UUID,
    wasLoadedBeforeOperation: Bool = true
  ) {
    guard spreadsheetWindows[id] == nil else { return }
    guard !chartWindows.values.contains(where: { $0.documentID == id }) else {
      return
    }
    if wasLoadedBeforeOperation || documents[id] != nil {
      documents.removeValue(forKey: id)
    }
  }

  private func onMain<T>(_ body: () throws -> T) rethrows -> T {
    if Thread.isMainThread { return try body() }
    return try DispatchQueue.main.sync(execute: body)
  }
}
