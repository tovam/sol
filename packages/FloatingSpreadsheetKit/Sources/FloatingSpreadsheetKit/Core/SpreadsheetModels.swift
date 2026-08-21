import Foundation

struct CellAddress: Codable, Hashable, Comparable, CustomStringConvertible {
  var row: Int
  var column: Int

  init(row: Int, column: Int) {
    self.row = max(0, row)
    self.column = max(0, column)
  }

  init?(_ a1Reference: String) {
    let normalized = a1Reference
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "$", with: "")
      .uppercased()
    guard !normalized.isEmpty else { return nil }

    var letters = ""
    var digits = ""
    var reachedDigits = false
    for character in normalized {
      if character.isASCIIUppercaseLetter && !reachedDigits {
        letters.append(character)
      } else if character.isNumber && !letters.isEmpty {
        reachedDigits = true
        digits.append(character)
      } else {
        return nil
      }
    }

    guard !letters.isEmpty, let rowNumber = Int(digits), rowNumber > 0 else {
      return nil
    }

    var columnNumber = 0
    for scalar in letters.unicodeScalars {
      columnNumber = columnNumber * 26 + Int(scalar.value - 64)
    }
    self.init(row: rowNumber - 1, column: columnNumber - 1)
  }

  static func < (lhs: CellAddress, rhs: CellAddress) -> Bool {
    lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
  }

  var description: String {
    "\(Self.columnName(column))\(row + 1)"
  }

  static func columnName(_ zeroBasedColumn: Int) -> String {
    var value = max(0, zeroBasedColumn) + 1
    var result = ""
    while value > 0 {
      let remainder = (value - 1) % 26
      result.insert(
        Character(UnicodeScalar(65 + remainder)!),
        at: result.startIndex
      )
      value = (value - 1) / 26
    }
    return result
  }
}

private extension Character {
  var isASCIIUppercaseLetter: Bool {
    guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else {
      return false
    }
    return scalar.value >= 65 && scalar.value <= 90
  }
}

struct CellRange: Codable, Hashable, CustomStringConvertible {
  var start: CellAddress
  var end: CellAddress

  init(start: CellAddress, end: CellAddress) {
    self.start = CellAddress(
      row: min(start.row, end.row),
      column: min(start.column, end.column)
    )
    self.end = CellAddress(
      row: max(start.row, end.row),
      column: max(start.column, end.column)
    )
  }

  init(_ address: CellAddress) {
    self.init(start: address, end: address)
  }

  init?(_ a1Range: String) {
    let components = a1Range.split(separator: ":", omittingEmptySubsequences: false)
    guard components.count == 1 || components.count == 2,
      let first = CellAddress(String(components[0]))
    else {
      return nil
    }
    let last = components.count == 2
      ? CellAddress(String(components[1]))
      : first
    guard let last else { return nil }
    self.init(start: first, end: last)
  }

  var description: String {
    start == end ? start.description : "\(start):\(end)"
  }

  var rowCount: Int { end.row - start.row + 1 }
  var columnCount: Int { end.column - start.column + 1 }

  func contains(_ address: CellAddress) -> Bool {
    address.row >= start.row && address.row <= end.row
      && address.column >= start.column && address.column <= end.column
  }

  func addresses(limit: Int = 250_000) -> [CellAddress] {
    guard rowCount > 0, columnCount > 0, rowCount * columnCount <= limit else {
      return []
    }
    var result: [CellAddress] = []
    result.reserveCapacity(rowCount * columnCount)
    for row in start.row...end.row {
      for column in start.column...end.column {
        result.append(CellAddress(row: row, column: column))
      }
    }
    return result
  }

  func shiftedForInsertedRows(at index: Int, count: Int) -> CellRange {
    guard count > 0 else { return self }
    if index <= start.row {
      return CellRange(
        start: CellAddress(row: start.row + count, column: start.column),
        end: CellAddress(row: end.row + count, column: end.column)
      )
    }
    if index <= end.row {
      return CellRange(
        start: start,
        end: CellAddress(row: end.row + count, column: end.column)
      )
    }
    return self
  }

  func shiftedForInsertedColumns(at index: Int, count: Int) -> CellRange {
    guard count > 0 else { return self }
    if index <= start.column {
      return CellRange(
        start: CellAddress(row: start.row, column: start.column + count),
        end: CellAddress(row: end.row, column: end.column + count)
      )
    }
    if index <= end.column {
      return CellRange(
        start: start,
        end: CellAddress(row: end.row, column: end.column + count)
      )
    }
    return self
  }

  func shiftedForDeletedRows(at index: Int, count: Int) -> CellRange? {
    guard count > 0 else { return self }
    let deletionEnd = index + count - 1
    if deletionEnd < start.row {
      return CellRange(
        start: CellAddress(row: max(0, start.row - count), column: start.column),
        end: CellAddress(row: max(0, end.row - count), column: end.column)
      )
    }
    if index > end.row { return self }

    let remainingBefore = max(0, min(end.row, index - 1) - start.row + 1)
    let remainingAfter = max(0, end.row - max(start.row, deletionEnd + 1) + 1)
    let remainingCount = remainingBefore + remainingAfter
    guard remainingCount > 0 else { return nil }
    let newStartRow = start.row < index ? start.row : index
    return CellRange(
      start: CellAddress(row: newStartRow, column: start.column),
      end: CellAddress(row: newStartRow + remainingCount - 1, column: end.column)
    )
  }

  func shiftedForDeletedColumns(at index: Int, count: Int) -> CellRange? {
    guard count > 0 else { return self }
    let deletionEnd = index + count - 1
    if deletionEnd < start.column {
      return CellRange(
        start: CellAddress(row: start.row, column: max(0, start.column - count)),
        end: CellAddress(row: end.row, column: max(0, end.column - count))
      )
    }
    if index > end.column { return self }

    let remainingBefore = max(0, min(end.column, index - 1) - start.column + 1)
    let remainingAfter = max(0, end.column - max(start.column, deletionEnd + 1) + 1)
    let remainingCount = remainingBefore + remainingAfter
    guard remainingCount > 0 else { return nil }
    let newStartColumn = start.column < index ? start.column : index
    return CellRange(
      start: CellAddress(row: start.row, column: newStartColumn),
      end: CellAddress(row: end.row, column: newStartColumn + remainingCount - 1)
    )
  }
}

enum CellDisplayFormat: Codable, Equatable {
  case automatic
  case number
  case date
  case time
  case percent
  case currency(code: String)
}

struct CellStyle: Codable, Equatable {
  var isBold = false
  var isItalic = false
  var displayFormat: CellDisplayFormat = .automatic

  static let plain = CellStyle()
}

enum SpreadsheetDisplayLocale: String, Codable, CaseIterable {
  case french
  case english

  var locale: Locale {
    switch self {
    case .french: return Locale(identifier: "fr_FR")
    case .english: return Locale(identifier: "en_US")
    }
  }

  var shortLabel: String {
    switch self {
    case .french: return "FR"
    case .english: return "EN"
    }
  }
}

struct SpreadsheetSettings: Codable, Equatable {
  var displayLocale: SpreadsheetDisplayLocale = .french
  var currencyCode = "EUR"
  var scheduledArchiveAt: Date?

  static let standard = SpreadsheetSettings()
}

struct CellRecord: Codable, Equatable {
  var rawInput: String
  var style: CellStyle = .plain

  var shouldPersist: Bool {
    !rawInput.isEmpty || style != .plain
  }
}

struct PersistedCell: Codable, Equatable {
  var address: CellAddress
  var record: CellRecord
}

enum SpreadsheetFormulaError: String, Codable, Error {
  case divisionByZero = "#DIV/0!"
  case invalidReference = "#REF!"
  case invalidValue = "#VALUE!"
  case unknownName = "#NAME?"
  case cycle = "#CYCLE!"
  case parse = "#ERROR!"
}

enum SpreadsheetValue: Equatable {
  case blank
  case number(Double)
  case text(String)
  case date(Date)
  case time(Double)
  case boolean(Bool)
  case error(SpreadsheetFormulaError)

  var numericValue: Double? {
    switch self {
    case .number(let value):
      return value
    case .time(let fractionOfDay):
      return fractionOfDay
    case .boolean(let value):
      return value ? 1 : 0
    default:
      return nil
    }
  }

  var isBlank: Bool {
    if case .blank = self { return true }
    return false
  }

  var isTime: Bool {
    if case .time = self { return true }
    return false
  }

  var dateValue: Date? {
    if case .date(let date) = self { return date }
    return nil
  }
}

enum SpreadsheetTime {
  static let minutesPerDay = 24 * 60

  static func parse(_ input: String) -> Double? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
      (parts[0].count == 1 || parts[0].count == 2),
      parts[1].count == 2,
      parts[0].allSatisfy(\.isNumber),
      parts[1].allSatisfy(\.isNumber),
      let hour = Int(parts[0]),
      let minute = Int(parts[1]),
      (0...23).contains(hour),
      (0...59).contains(minute)
    else {
      return nil
    }
    return Double(hour * 60 + minute) / Double(minutesPerDay)
  }

  static func format(_ fractionOfDay: Double) -> String {
    guard fractionOfDay.isFinite else { return "" }
    let roundedMinutes = Int((fractionOfDay * Double(minutesPerDay)).rounded())
    let wrappedMinutes = ((roundedMinutes % minutesPerDay) + minutesPerDay)
      % minutesPerDay
    return String(
      format: "%d:%02d",
      wrappedMinutes / 60,
      wrappedMinutes % 60
    )
  }
}

enum SpreadsheetDate {
  static func parse(_ input: String) -> Date? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let isoFormatter = ISO8601DateFormatter()
    if let date = isoFormatter.date(from: value) { return date }

    let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "dd-MM-yyyy"]
    for format in formats {
      let formatter = DateFormatter()
      formatter.locale = .current
      formatter.calendar = .current
      formatter.timeZone = .current
      formatter.dateFormat = format
      formatter.isLenient = false
      if let date = formatter.date(from: value) { return date }
    }
    return nil
  }

  static func format(_ date: Date, locale: Locale = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = .current
    formatter.timeZone = .current
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter.string(from: date)
  }
}

enum SpreadsheetChartType: String, Codable, CaseIterable {
  case line
  case bar
  case area
  case scatter
  case pie
}

enum SpreadsheetSeriesOrientation: String, Codable, CaseIterable {
  case columns
  case rows
}

enum SpreadsheetChartAxisScale: String, Codable, CaseIterable {
  case linear
  case logarithmic
}

struct SpreadsheetChartAxisConfiguration: Codable, Equatable {
  var title: String
  var minimum: Double?
  var maximum: Double?
  var scale: SpreadsheetChartAxisScale
  var showsGridLines: Bool
  var showsLabels: Bool

  static let standard = SpreadsheetChartAxisConfiguration()

  init(
    title: String = "",
    minimum: Double? = nil,
    maximum: Double? = nil,
    scale: SpreadsheetChartAxisScale = .linear,
    showsGridLines: Bool = true,
    showsLabels: Bool = true
  ) {
    self.title = title
    self.minimum = minimum
    self.maximum = maximum
    self.scale = scale
    self.showsGridLines = showsGridLines
    self.showsLabels = showsLabels
  }
}

struct SpreadsheetChartPoint: Codable, Equatable {
  var category: String
  var x: Double?
  var xDate: Date?
  var value: Double
  var xIsTime: Bool?
  var valueIsTime: Bool?

  init(
    category: String,
    x: Double?,
    xDate: Date? = nil,
    value: Double,
    xIsTime: Bool? = nil,
    valueIsTime: Bool? = nil
  ) {
    self.category = category
    self.x = x
    self.xDate = xDate
    self.value = value
    self.xIsTime = xIsTime
    self.valueIsTime = valueIsTime
  }
}

struct SpreadsheetChartSeries: Codable, Equatable {
  var name: String
  var points: [SpreadsheetChartPoint]
}

struct SpreadsheetChartDefinition: Codable, Equatable, Identifiable {
  var id: UUID
  var title: String
  var type: SpreadsheetChartType
  var sourceRange: CellRange
  var firstRowContainsHeaders: Bool
  var firstColumnContainsLabels: Bool
  var seriesOrientation: SpreadsheetSeriesOrientation
  var isFrozen: Bool
  var frozenSeries: [SpreadsheetChartSeries]
  var xAxis: SpreadsheetChartAxisConfiguration?
  var yAxis: SpreadsheetChartAxisConfiguration?

  var effectiveXAxis: SpreadsheetChartAxisConfiguration {
    xAxis ?? .standard
  }

  var effectiveYAxis: SpreadsheetChartAxisConfiguration {
    yAxis ?? .standard
  }

  init(
    id: UUID = UUID(),
    title: String = "Chart",
    type: SpreadsheetChartType = .line,
    sourceRange: CellRange,
    firstRowContainsHeaders: Bool = true,
    firstColumnContainsLabels: Bool = true,
    seriesOrientation: SpreadsheetSeriesOrientation = .columns,
    isFrozen: Bool = false,
    frozenSeries: [SpreadsheetChartSeries] = [],
    xAxis: SpreadsheetChartAxisConfiguration? = nil,
    yAxis: SpreadsheetChartAxisConfiguration? = nil
  ) {
    self.id = id
    self.title = title
    self.type = type
    self.sourceRange = sourceRange
    self.firstRowContainsHeaders = firstRowContainsHeaders
    self.firstColumnContainsLabels = firstColumnContainsLabels
    self.seriesOrientation = seriesOrientation
    self.isFrozen = isFrozen
    self.frozenSeries = frozenSeries
    self.xAxis = xAxis
    self.yAxis = yAxis
  }
}

struct SpreadsheetCellChange: Codable, Equatable {
  var address: CellAddress
  var before: CellRecord?
  var after: CellRecord?
}

enum SpreadsheetActionKind: String, Codable {
  case cells
  case rename
  case structure
  case charts
  case layout
}

struct SpreadsheetAction: Codable, Equatable, Identifiable {
  var id = UUID()
  var timestamp = Date()
  var label: String
  var kind: SpreadsheetActionKind
  var cellChanges: [SpreadsheetCellChange] = []
  var nameBefore: String?
  var nameAfter: String?
  var chartsBefore: [SpreadsheetChartDefinition]?
  var chartsAfter: [SpreadsheetChartDefinition]?
  var columnWidthsBefore: [Int: Double]?
  var columnWidthsAfter: [Int: Double]?
  var settingsBefore: SpreadsheetSettings?
  var settingsAfter: SpreadsheetSettings?
}

struct SpreadsheetPayload: Codable {
  var schemaVersion: Int
  var id: UUID
  var name: String
  var createdAt: Date
  var updatedAt: Date
  var cells: [PersistedCell]
  var charts: [SpreadsheetChartDefinition]
  var history: [SpreadsheetAction]
  var historyCursor: Int
  var columnWidths: [Int: Double]
  var settings: SpreadsheetSettings
  var archivedAt: Date?

  init(
    schemaVersion: Int = 4,
    id: UUID,
    name: String,
    createdAt: Date,
    updatedAt: Date,
    cells: [PersistedCell],
    charts: [SpreadsheetChartDefinition],
    history: [SpreadsheetAction],
    historyCursor: Int,
    columnWidths: [Int: Double] = [:],
    settings: SpreadsheetSettings = .standard,
    archivedAt: Date? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.cells = cells
    self.charts = charts
    self.history = history
    self.historyCursor = historyCursor
    self.columnWidths = columnWidths
    self.settings = settings
    self.archivedAt = archivedAt
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case id
    case name
    case createdAt
    case updatedAt
    case cells
    case charts
    case history
    case historyCursor
    case columnWidths
    case settings
    case archivedAt
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    id = try values.decode(UUID.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    createdAt = try values.decode(Date.self, forKey: .createdAt)
    updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    cells = try values.decodeIfPresent([PersistedCell].self, forKey: .cells) ?? []
    charts = try values.decodeIfPresent(
      [SpreadsheetChartDefinition].self,
      forKey: .charts
    ) ?? []
    history = try values.decodeIfPresent([SpreadsheetAction].self, forKey: .history) ?? []
    historyCursor = try values.decodeIfPresent(Int.self, forKey: .historyCursor)
      ?? history.count
    columnWidths = try values.decodeIfPresent([Int: Double].self, forKey: .columnWidths) ?? [:]
    settings = try values.decodeIfPresent(SpreadsheetSettings.self, forKey: .settings)
      ?? .standard
    archivedAt = try values.decodeIfPresent(Date.self, forKey: .archivedAt)
  }
}

public struct FloatingSpreadsheetSummary: Codable, Equatable, Identifiable {
  public var id: UUID
  public var name: String
  public var updatedAt: Date
  public var cellCount: Int
  public var chartCount: Int
  public var scheduledArchiveAt: Date?
  public var archivedAt: Date?

  init(payload: SpreadsheetPayload) {
    id = payload.id
    name = payload.name
    updatedAt = payload.updatedAt
    cellCount = payload.cells.count
    chartCount = payload.charts.count
    scheduledArchiveAt = payload.settings.scheduledArchiveAt
    archivedAt = payload.archivedAt
  }

  public var bridgeDictionary: [String: Any] {
    var result: [String: Any] = [
      "id": id.uuidString,
      "name": name,
      "updatedAt": updatedAt.timeIntervalSince1970 * 1000,
      "cellCount": cellCount,
      "chartCount": chartCount,
    ]
    if let scheduledArchiveAt {
      result["scheduledArchiveAt"] = scheduledArchiveAt.timeIntervalSince1970 * 1000
    }
    if let archivedAt {
      result["archivedAt"] = archivedAt.timeIntervalSince1970 * 1000
    }
    return result
  }
}
