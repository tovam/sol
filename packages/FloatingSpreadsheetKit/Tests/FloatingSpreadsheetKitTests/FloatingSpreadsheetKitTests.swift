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

  func testOneAndTwoDigitHoursAreRecognizedAsTimes() {
    let document = SpreadsheetDocument(name: "Times")
    let oneDigit = CellAddress(row: 0, column: 0)
    let twoDigits = CellAddress(row: 1, column: 0)
    let malformed = CellAddress(row: 2, column: 0)
    document.setRawInput("9:05", at: oneDigit)
    document.setRawInput("09:05", at: twoDigits)
    document.setRawInput("9:5", at: malformed)

    let expected = Double(9 * 60 + 5) / Double(24 * 60)
    XCTAssertEqual(document.value(at: oneDigit), .time(expected))
    XCTAssertEqual(document.value(at: twoDigits), .time(expected))
    XCTAssertEqual(document.displayText(at: oneDigit), "9:05")
    XCTAssertEqual(document.displayText(at: twoDigits), "9:05")
    XCTAssertEqual(document.value(at: malformed), .text("9:5"))
  }

  func testInvalidClockTimesRemainText() {
    let document = SpreadsheetDocument(name: "Invalid times")
    let values = ["24:00", "12:60", "123:45", "-1:30"]
    for (row, rawValue) in values.enumerated() {
      let address = CellAddress(row: row, column: 0)
      document.setRawInput(rawValue, at: address)
      XCTAssertEqual(document.value(at: address), .text(rawValue))
    }
  }

  func testChartPointsKeepTimeAxisAndValueMetadata() {
    let document = SpreadsheetDocument(name: "Time chart")
    document.setRawInput("Time", at: CellAddress(row: 0, column: 0))
    document.setRawInput("End", at: CellAddress(row: 0, column: 1))
    document.setRawInput("9:00", at: CellAddress(row: 1, column: 0))
    document.setRawInput("10:30", at: CellAddress(row: 1, column: 1))
    let chart = SpreadsheetChartDefinition(
      sourceRange: CellRange(
        start: CellAddress(row: 0, column: 0),
        end: CellAddress(row: 1, column: 1)
      )
    )

    let point = document.chartSeries(for: chart).first?.points.first
    XCTAssertEqual(point?.category, "9:00")
    XCTAssertEqual(point?.xIsTime, true)
    XCTAssertEqual(point?.valueIsTime, true)
    XCTAssertEqual(point?.value, Double(10 * 60 + 30) / Double(24 * 60))
  }

  func testChartPointsRecognizeDatesOnTheXAxis() throws {
    let document = SpreadsheetDocument(name: "Date chart")
    document.setRawInput("Date", at: CellAddress(row: 0, column: 0))
    document.setRawInput("Sales", at: CellAddress(row: 0, column: 1))
    document.setRawInput("2026-08-21", at: CellAddress(row: 1, column: 0))
    document.setRawInput("42", at: CellAddress(row: 1, column: 1))
    let chart = SpreadsheetChartDefinition(
      sourceRange: CellRange(
        start: CellAddress(row: 0, column: 0),
        end: CellAddress(row: 1, column: 1)
      )
    )

    let point = try XCTUnwrap(document.chartSeries(for: chart).first?.points.first)
    XCTAssertEqual(
      point.category,
      document.displayText(at: CellAddress(row: 1, column: 0))
    )
    XCTAssertEqual(
      point.xDate,
      try XCTUnwrap(SpreadsheetDate.parse("2026-08-21"))
    )
    XCTAssertNil(point.x)
  }

  func testHistogramUsesOptimalBinsAndPreservesEverySample() throws {
    let samples = (1...100).map {
      SpreadsheetHistogramSample(value: Double($0), isDuration: false)
    }
    let result = try XCTUnwrap(
      SpreadsheetHistogramCalculator.calculate(samples: samples)
    )

    XCTAssertEqual(result.method, .freedmanDiaconis)
    XCTAssertEqual(result.bins.reduce(0) { $0 + $1.count }, samples.count)
    XCTAssertTrue((1...80).contains(result.bins.count))
    XCTAssertEqual(
      try XCTUnwrap(result.bins.last).cumulativePercentage,
      1,
      accuracy: 0.000_001
    )
  }

  func testDurationHistogramUsesReadableDurationBoundariesAndBinStatistics() throws {
    let minutes = [5, 10, 10, 15, 25, 30, 45, 60]
    let samples = minutes.map {
      SpreadsheetHistogramSample(
        value: Double($0) / Double(24 * 60),
        isDuration: true
      )
    }
    let result = try XCTUnwrap(
      SpreadsheetHistogramCalculator.calculate(samples: samples)
    )

    XCTAssertTrue(result.isDuration)
    XCTAssertEqual(result.bins.reduce(0) { $0 + $1.count }, samples.count)
    XCTAssertGreaterThan(result.binWidth, 0)
    XCTAssertTrue(result.bins.contains { $0.count > 0 && $0.mean != nil })
    XCTAssertEqual(
      try XCTUnwrap(result.bins.last).cumulativePercentage,
      1,
      accuracy: 0.000_001
    )
  }

  func testHistogramReadsSingleNumericColumnEvenWhenLabelOptionIsEnabled() {
    let document = SpreadsheetDocument(name: "Histogram")
    document.setRawInput("Duration", at: CellAddress(row: 0, column: 0))
    document.setRawInput("0:05", at: CellAddress(row: 1, column: 0))
    document.setRawInput("0:15", at: CellAddress(row: 2, column: 0))
    let chart = SpreadsheetChartDefinition(
      type: .histogram,
      sourceRange: CellRange(
        start: CellAddress(row: 0, column: 0),
        end: CellAddress(row: 2, column: 0)
      )
    )

    let samples = document.histogramSamples(for: chart)
    XCTAssertEqual(samples.count, 2)
    XCTAssertTrue(samples.allSatisfy(\.isDuration))
  }

  func testChartAxisSettingsPersistAndLegacyChartsKeepAutomaticAxes() throws {
    let chart = SpreadsheetChartDefinition(
      sourceRange: CellRange(CellAddress(row: 0, column: 0)),
      xAxis: SpreadsheetChartAxisConfiguration(
        title: "Elapsed time",
        minimum: 1,
        maximum: 100,
        scale: .logarithmic,
        showsGridLines: false
      ),
      yAxis: SpreadsheetChartAxisConfiguration(
        title: "Price",
        minimum: 0,
        maximum: 250,
        showsLabels: false
      )
    )

    let encoded = try JSONEncoder().encode(chart)
    let restored = try JSONDecoder().decode(SpreadsheetChartDefinition.self, from: encoded)
    XCTAssertEqual(restored.effectiveXAxis.title, "Elapsed time")
    XCTAssertEqual(restored.effectiveXAxis.scale, .logarithmic)
    XCTAssertEqual(restored.effectiveXAxis.minimum, 1)
    XCTAssertEqual(restored.effectiveXAxis.maximum, 100)
    XCTAssertFalse(restored.effectiveXAxis.showsGridLines)
    XCTAssertEqual(restored.effectiveYAxis.title, "Price")
    XCTAssertFalse(restored.effectiveYAxis.showsLabels)

    var legacyObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    legacyObject.removeValue(forKey: "xAxis")
    legacyObject.removeValue(forKey: "yAxis")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacy = try JSONDecoder().decode(SpreadsheetChartDefinition.self, from: legacyData)
    XCTAssertEqual(legacy.effectiveXAxis, .standard)
    XCTAssertEqual(legacy.effectiveYAxis, .standard)
  }

  func testChartReferenceLinePersistsAndIsOptionalForLegacyCharts() throws {
    let chart = SpreadsheetChartDefinition(
      sourceRange: CellRange(CellAddress(row: 0, column: 0)),
      referenceLine: SpreadsheetChartReferenceLine(value: 120, label: "Target")
    )
    let encoded = try JSONEncoder().encode(chart)
    let restored = try JSONDecoder().decode(SpreadsheetChartDefinition.self, from: encoded)
    XCTAssertEqual(
      restored.referenceLine,
      SpreadsheetChartReferenceLine(value: 120, label: "Target")
    )

    var legacyObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    legacyObject.removeValue(forKey: "referenceLine")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacy = try JSONDecoder().decode(SpreadsheetChartDefinition.self, from: legacyData)
    XCTAssertNil(legacy.referenceLine)
  }

  func testLastValueLabelsPersistAndDefaultToHidden() throws {
    let chart = SpreadsheetChartDefinition(
      sourceRange: CellRange(CellAddress(row: 0, column: 0)),
      showsLastValueLabels: true
    )
    let encoded = try JSONEncoder().encode(chart)
    let restored = try JSONDecoder().decode(SpreadsheetChartDefinition.self, from: encoded)
    XCTAssertTrue(restored.displaysLastValueLabels)

    var legacyObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    legacyObject.removeValue(forKey: "showsLastValueLabels")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacy = try JSONDecoder().decode(SpreadsheetChartDefinition.self, from: legacyData)
    XCTAssertFalse(legacy.displaysLastValueLabels)
  }
}
