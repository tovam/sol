import XCTest
@testable import FloatingSpreadsheetKit

final class FloatingSpreadsheetKitTests: XCTestCase {
  func testA1AddressesAndRanges() {
    XCTAssertEqual(CellAddress("A1"), CellAddress(row: 0, column: 0))
    XCTAssertEqual(CellAddress("$AA$42"), CellAddress(row: 41, column: 26))
    XCTAssertEqual(CellAddress.columnName(701), "ZZ")
    XCTAssertEqual(CellRange("B2:D4")?.rowCount, 3)
  }

  func testEnglishAndFrenchFormulaInput() {
    let document = SpreadsheetDocument(name: "Formulas")
    document.setRawInput("1,5", at: CellAddress(row: 0, column: 0))
    document.setRawInput("2.5", at: CellAddress(row: 1, column: 0))
    document.setRawInput("=SUM(A1:A2)", at: CellAddress(row: 2, column: 0))
    XCTAssertEqual(document.value(at: CellAddress(row: 2, column: 0)), .number(4))
  }

  func testUndoRedoSurvivesSerialization() throws {
    let address = CellAddress(row: 0, column: 0)
    let document = SpreadsheetDocument(name: "History")
    document.setRawInput("before", at: address)
    document.setRawInput("after", at: address)

    let data = try JSONEncoder().encode(document.payload)
    let restoredPayload = try JSONDecoder().decode(SpreadsheetPayload.self, from: data)
    let restored = SpreadsheetDocument(payload: restoredPayload)

    XCTAssertTrue(restored.undo())
    XCTAssertEqual(restored.rawInput(at: address), "before")
    XCTAssertTrue(restored.redo())
    XCTAssertEqual(restored.rawInput(at: address), "after")
  }

  func testDelimitedPasteIsOneLogicalAction() throws {
    let parser = DelimitedTextParser()
    let rows = try parser.parse(
      "Name\tValue\nA\t1\nB\t2",
      options: DelimitedTextOptions(separator: .tab, firstRowIsHeader: true)
    )
    let document = SpreadsheetDocument(name: "Paste")
    document.replaceCells(
      startingAt: CellAddress(row: 0, column: 0),
      rows: rows,
      firstRowIsHeader: true
    )

    XCTAssertEqual(document.history.count, 1)
    XCTAssertTrue(document.undo())
    XCTAssertEqual(document.rawInput(at: CellAddress(row: 1, column: 1)), "")
  }

  func testColumnWidthPersistsAndParticipatesInUndoRedo() throws {
    let document = SpreadsheetDocument(name: "Widths")
    document.setColumnWidth(174, at: 2)

    let data = try JSONEncoder().encode(document.payload)
    let restoredPayload = try JSONDecoder().decode(SpreadsheetPayload.self, from: data)
    let restored = SpreadsheetDocument(payload: restoredPayload)

    XCTAssertEqual(restored.columnWidths[2], 174)
    XCTAssertTrue(restored.undo())
    XCTAssertNil(restored.columnWidths[2])
    XCTAssertTrue(restored.redo())
    XCTAssertEqual(restored.columnWidths[2], 174)
  }

  func testLegacyPayloadDefaultsToNoCustomColumnWidths() throws {
    let document = SpreadsheetDocument(name: "Legacy")
    let encoded = try JSONEncoder().encode(document.payload)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "columnWidths")
    object.removeValue(forKey: "settings")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(SpreadsheetPayload.self, from: legacyData)
    XCTAssertEqual(decoded.columnWidths, [:])
    XCTAssertEqual(decoded.settings, .standard)
  }

  func testSpreadsheetLocaleAndCurrencySettingsPersistAndUndo() throws {
    let address = CellAddress(row: 0, column: 0)
    let document = SpreadsheetDocument(name: "Formatting")
    document.setRawInput("1234.5", at: address)
    document.setDisplayFormat(.currency(code: "EUR"), in: CellRange(address))
    XCTAssertTrue(document.displayText(at: address).contains("€"))

    document.updateSettings(
      SpreadsheetSettings(displayLocale: .english, currencyCode: "USD")
    )
    XCTAssertTrue(document.displayText(at: address).contains("$"))

    let data = try JSONEncoder().encode(document.payload)
    let payload = try JSONDecoder().decode(SpreadsheetPayload.self, from: data)
    let restored = SpreadsheetDocument(payload: payload)
    XCTAssertEqual(restored.settings.displayLocale, .english)
    XCTAssertEqual(restored.settings.currencyCode, "USD")
    XCTAssertTrue(restored.undo())
    XCTAssertEqual(restored.settings, .standard)
  }

  func testScheduledArchivePersistsAndCanBeRestored() throws {
    let deadline = Date(timeIntervalSince1970: 2_000_000_000)
    let archivedAt = deadline.addingTimeInterval(10)
    let document = SpreadsheetDocument(name: "Temporary")
    var settings = document.settings
    settings.scheduledArchiveAt = deadline
    document.updateSettings(settings)

    XCTAssertTrue(document.isDueForArchive(at: deadline))
    document.archive(at: archivedAt)
    XCTAssertEqual(document.archivedAt, archivedAt)
    XCTAssertNil(document.settings.scheduledArchiveAt)

    let data = try JSONEncoder().encode(document.payload)
    let payload = try JSONDecoder().decode(SpreadsheetPayload.self, from: data)
    let restored = SpreadsheetDocument(payload: payload)
    XCTAssertEqual(restored.archivedAt, archivedAt)

    restored.restoreFromArchive(at: archivedAt.addingTimeInterval(10))
    XCTAssertNil(restored.archivedAt)
    XCTAssertNil(restored.settings.scheduledArchiveAt)
  }

  func testRepositorySeparatesActiveAndArchivedSpreadsheets() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FloatingSpreadsheetKitTests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = SpreadsheetRepository(rootDirectory: root)
    let document = try repository.createDocument()

    XCTAssertEqual(try repository.loadSummaries().map(\.id), [document.id])
    XCTAssertTrue(try repository.loadSummaries(archived: true).isEmpty)

    document.archive()
    try repository.saveImmediately(document)
    XCTAssertTrue(try repository.loadSummaries().isEmpty)
    XCTAssertEqual(
      try repository.loadSummaries(archived: true).map(\.id),
      [document.id]
    )
  }
}
