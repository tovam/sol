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
}
