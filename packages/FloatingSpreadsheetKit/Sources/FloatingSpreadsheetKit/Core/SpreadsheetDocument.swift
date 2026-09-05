import Foundation

extension Notification.Name {
  static let floatingSpreadsheetDidChange = Notification.Name(
    "FloatingSpreadsheetKit.documentDidChange"
  )
}

enum SpreadsheetNavigationDirection {
  case left
  case right
  case up
  case down
}

final class SpreadsheetDocument {
  static let historyLimit = 50

  let id: UUID
  let createdAt: Date
  private(set) var name: String
  private(set) var updatedAt: Date
  private(set) var charts: [SpreadsheetChartDefinition]
  private(set) var history: [SpreadsheetAction]
  private(set) var historyCursor: Int
  private(set) var columnWidths: [Int: Double]
  private(set) var settings: SpreadsheetSettings
  private(set) var archivedAt: Date?

  var onChange: ((SpreadsheetDocument) -> Void)?

  private var cells: [CellAddress: CellRecord]
  private let formulaEngine = SpreadsheetFormulaEngine()
  private var inferredDateYearsByColumn: [Int: [Int: Int]] = [:]

  init(payload: SpreadsheetPayload) {
    id = payload.id
    name = payload.name
    createdAt = payload.createdAt
    updatedAt = payload.updatedAt
    cells = Dictionary(
      uniqueKeysWithValues: payload.cells.map { ($0.address, $0.record) }
    )
    charts = payload.charts
    history = Array(payload.history.suffix(Self.historyLimit))
    historyCursor = min(max(0, payload.historyCursor), history.count)
    columnWidths = payload.columnWidths.filter { column, width in
      column >= 0 && width.isFinite && width > 0
    }
    settings = payload.settings
    archivedAt = payload.archivedAt
    formulaEngine.literalValueProvider = { [weak self] address, record in
      self?.literalValue(for: record, at: address) ?? .text(record.rawInput)
    }
  }

  convenience init(id: UUID = UUID(), name: String, now: Date = Date()) {
    self.init(
      payload: SpreadsheetPayload(
        id: id,
        name: name,
        createdAt: now,
        updatedAt: now,
        cells: [],
        charts: [],
        history: [],
        historyCursor: 0
      )
    )
  }

  var canUndo: Bool { historyCursor > 0 }
  var canRedo: Bool { historyCursor < history.count }

  var summary: FloatingSpreadsheetSummary {
    FloatingSpreadsheetSummary(payload: payload)
  }

  var payload: SpreadsheetPayload {
    SpreadsheetPayload(
      id: id,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      cells: cells
        .filter { $0.value.shouldPersist }
        .map { PersistedCell(address: $0.key, record: $0.value) }
        .sorted { $0.address < $1.address },
      charts: charts,
      history: history,
      historyCursor: historyCursor,
      columnWidths: columnWidths,
      settings: settings,
      archivedAt: archivedAt
    )
  }

  func record(at address: CellAddress) -> CellRecord? {
    cells[address]
  }

  func rawInput(at address: CellAddress) -> String {
    cells[address]?.rawInput ?? ""
  }

  func value(at address: CellAddress) -> SpreadsheetValue {
    formulaEngine.value(at: address, cells: cells)
  }

  func columnType(at column: Int) -> SpreadsheetColumnType {
    settings.columnType(at: column)
  }

  func referenceRanges(at address: CellAddress) -> [CellRange] {
    formulaEngine.referenceRanges(in: rawInput(at: address))
  }

  func isEmpty(_ range: CellRange) -> Bool {
    !cells.contains { range.contains($0.key) && !$0.value.rawInput.isEmpty }
  }

  func navigationDestination(
    from origin: CellAddress,
    direction: SpreadsheetNavigationDirection,
    maximumRow: Int,
    maximumColumn: Int
  ) -> CellAddress {
    let boundedOrigin = CellAddress(
      row: min(maximumRow, origin.row),
      column: min(maximumColumn, origin.column)
    )
    let delta: (row: Int, column: Int)
    let sheetBoundary: CellAddress
    switch direction {
    case .left:
      delta = (0, -1)
      sheetBoundary = CellAddress(row: boundedOrigin.row, column: 0)
    case .right:
      delta = (0, 1)
      sheetBoundary = CellAddress(row: boundedOrigin.row, column: maximumColumn)
    case .up:
      delta = (-1, 0)
      sheetBoundary = CellAddress(row: 0, column: boundedOrigin.column)
    case .down:
      delta = (1, 0)
      sheetBoundary = CellAddress(row: maximumRow, column: boundedOrigin.column)
    }

    func advanced(from address: CellAddress) -> CellAddress? {
      let row = address.row + delta.row
      let column = address.column + delta.column
      guard row >= 0, row <= maximumRow,
        column >= 0, column <= maximumColumn
      else {
        return nil
      }
      return CellAddress(row: row, column: column)
    }

    if let adjacent = advanced(from: boundedOrigin), isPopulated(adjacent) {
      var destination = adjacent
      while let next = advanced(from: destination), isPopulated(next) {
        destination = next
      }
      return destination
    }

    let nearestPopulated = cells.keys.compactMap { address -> (Int, CellAddress)? in
      let distance: Int
      if delta.row == 0, address.row == boundedOrigin.row {
        distance = (address.column - boundedOrigin.column) * delta.column
      } else if delta.column == 0, address.column == boundedOrigin.column {
        distance = (address.row - boundedOrigin.row) * delta.row
      } else {
        return nil
      }
      guard distance > 0, isPopulated(address) else { return nil }
      return (distance, address)
    }.min { $0.0 < $1.0 }?.1

    return nearestPopulated ?? sheetBoundary
  }

  func connectedDataRange(containing origin: CellAddress) -> CellRange? {
    var remaining = Set(cells.compactMap { address, record in
      record.rawInput.isEmpty ? nil : address
    })
    guard remaining.remove(origin) != nil else { return nil }

    var queue = [origin]
    var cursor = 0
    var minimumRow = origin.row
    var maximumRow = origin.row
    var minimumColumn = origin.column
    var maximumColumn = origin.column
    while cursor < queue.count {
      let address = queue[cursor]
      cursor += 1
      let neighbours = [
        address.row > 0
          ? CellAddress(row: address.row - 1, column: address.column)
          : nil,
        CellAddress(row: address.row + 1, column: address.column),
        address.column > 0
          ? CellAddress(row: address.row, column: address.column - 1)
          : nil,
        CellAddress(row: address.row, column: address.column + 1),
      ]
      for neighbour in neighbours.compactMap({ $0 })
      where remaining.remove(neighbour) != nil {
        queue.append(neighbour)
        minimumRow = min(minimumRow, neighbour.row)
        maximumRow = max(maximumRow, neighbour.row)
        minimumColumn = min(minimumColumn, neighbour.column)
        maximumColumn = max(maximumColumn, neighbour.column)
      }
    }

    return CellRange(
      start: CellAddress(row: minimumRow, column: minimumColumn),
      end: CellAddress(row: maximumRow, column: maximumColumn)
    )
  }

  func displayText(at address: CellAddress) -> String {
    let value = value(at: address)
    let record = cells[address]
    let format = effectiveFormat(record: record, value: value)
    switch value {
    case .blank:
      return ""
    case .text(let text):
      return text
    case .boolean(let boolean):
      return boolean ? "TRUE" : "FALSE"
    case .error(let error):
      return error.rawValue
    case .date(let date):
      if let rawInput = record?.rawInput, SpreadsheetDate.isTimestamp(rawInput) {
        return rawInput
      }
      let includesTime = record.flatMap {
        SpreadsheetDate.components(
          $0.rawInput,
          displayLocale: settings.displayLocale
        )?.includesTime
      }
      return SpreadsheetDate.format(
        date,
        locale: settings.displayLocale.locale,
        timeZone: settings.timeZone,
        includesTime: includesTime
      )
    case .time(let fractionOfDay):
      return SpreadsheetTime.format(fractionOfDay)
    case .number(let number):
      return formatNumber(number, as: format)
    }
  }

  private func isPopulated(_ address: CellAddress) -> Bool {
    cells[address].map { !$0.rawInput.isEmpty } ?? false
  }

  func setRawInput(_ rawInput: String, at address: CellAddress, label: String = "Edit cell") {
    let old = cells[address]
    var new = old ?? CellRecord(rawInput: "")
    new.rawInput = materializedInput(rawInput)
    commitCellChanges(
      [SpreadsheetCellChange(address: address, before: old, after: normalized(new))],
      label: label
    )
  }

  func replaceCells(
    startingAt origin: CellAddress,
    rows: [[String]],
    firstRowIsHeader: Bool,
    label: String = "Paste cells"
  ) {
    let now = Date()
    var changes: [SpreadsheetCellChange] = []
    for (rowOffset, row) in rows.enumerated() {
      for (columnOffset, rawInput) in row.enumerated() {
        let address = CellAddress(
          row: origin.row + rowOffset,
          column: origin.column + columnOffset
        )
        let before = cells[address]
        var after = before ?? CellRecord(rawInput: "")
        after.rawInput = materializedInput(rawInput, now: now)
        if firstRowIsHeader && rowOffset == 0 {
          after.style.isBold = true
        }
        let normalizedAfter = normalized(after)
        if before != normalizedAfter {
          changes.append(
            SpreadsheetCellChange(
              address: address,
              before: before,
              after: normalizedAfter
            )
          )
        }
      }
    }
    commitCellChanges(changes, label: label)
  }

  func clear(_ range: CellRange, label: String = "Clear cells") {
    let changes = cells
      .filter { range.contains($0.key) }
      .map {
        SpreadsheetCellChange(address: $0.key, before: $0.value, after: nil)
      }
      .sorted { $0.address < $1.address }
    commitCellChanges(changes, label: label)
  }

  func clear(_ addresses: [CellAddress], label: String = "Clear cells") {
    let changes = Set(addresses).compactMap { address -> SpreadsheetCellChange? in
      guard let record = cells[address] else { return nil }
      return SpreadsheetCellChange(address: address, before: record, after: nil)
    }.sorted { $0.address < $1.address }
    commitCellChanges(changes, label: label)
  }

  func setBold(_ enabled: Bool, in range: CellRange) {
    updateStyle(in: range, label: enabled ? "Bold" : "Remove bold") {
      $0.isBold = enabled
    }
  }

  func setBold(_ enabled: Bool, at addresses: [CellAddress]) {
    updateStyle(at: addresses, label: enabled ? "Bold" : "Remove bold") {
      $0.isBold = enabled
    }
  }

  func setItalic(_ enabled: Bool, in range: CellRange) {
    updateStyle(in: range, label: enabled ? "Italic" : "Remove italic") {
      $0.isItalic = enabled
    }
  }

  func setItalic(_ enabled: Bool, at addresses: [CellAddress]) {
    updateStyle(at: addresses, label: enabled ? "Italic" : "Remove italic") {
      $0.isItalic = enabled
    }
  }

  func setDisplayFormat(_ format: CellDisplayFormat, in range: CellRange) {
    updateStyle(in: range, label: "Format cells") {
      $0.displayFormat = format
    }
  }

  func setDisplayFormat(_ format: CellDisplayFormat, at addresses: [CellAddress]) {
    updateStyle(at: addresses, label: "Format cells") {
      $0.displayFormat = format
    }
  }

  func canNormalizeDates(at addresses: [CellAddress]) -> Bool {
    normalizedDates(at: addresses) != nil
  }

  @discardableResult
  func normalizeDates(at addresses: [CellAddress]) -> Bool {
    guard let normalized = normalizedDates(at: addresses) else { return false }
    let changes = normalized.compactMap { address, timestamp -> SpreadsheetCellChange? in
      guard let before = cells[address], before.rawInput != timestamp else { return nil }
      var after = before
      after.rawInput = timestamp
      return SpreadsheetCellChange(address: address, before: before, after: after)
    }
    commitCellChanges(changes, label: "Normalize dates")
    return true
  }

  func setColumnWidth(_ width: Double, at column: Int) {
    guard column >= 0, width.isFinite else { return }
    let clampedWidth = min(600, max(40, width))
    var updated = columnWidths
    updated[column] = clampedWidth
    guard updated != columnWidths else { return }
    commit(
      SpreadsheetAction(
        label: "Resize column \(CellAddress.columnName(column))",
        kind: .layout,
        columnWidthsBefore: columnWidths,
        columnWidthsAfter: updated
      )
    )
  }

  func updateSettings(_ updated: SpreadsheetSettings) {
    var normalized = updated
    normalized.currencyCode = updated.currencyCode
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
    if normalized.currencyCode.isEmpty {
      normalized.currencyCode = "EUR"
    }
    guard normalized != settings else { return }
    commit(
      SpreadsheetAction(
        label: "Change spreadsheet settings",
        kind: .layout,
        settingsBefore: settings,
        settingsAfter: normalized
      )
    )
  }

  func setColumnType(_ type: SpreadsheetColumnType, at column: Int) {
    guard column >= 0 else { return }
    var updated = settings
    var types = updated.columnTypes ?? [:]
    if type == .automatic {
      types.removeValue(forKey: column)
    } else {
      types[column] = type
    }
    updated.columnTypes = types.isEmpty ? nil : types
    guard updated != settings else { return }
    commit(
      SpreadsheetAction(
        label: "Set column \(CellAddress.columnName(column)) type",
        kind: .layout,
        settingsBefore: settings,
        settingsAfter: updated
      )
    )
  }

  func rename(to newName: String) {
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != name else { return }
    commit(
      SpreadsheetAction(
        label: "Rename spreadsheet",
        kind: .rename,
        nameBefore: name,
        nameAfter: trimmed
      )
    )
  }

  func archive(at date: Date = Date()) {
    guard archivedAt == nil else { return }
    archivedAt = date
    settings.scheduledArchiveAt = nil
    finishChange(at: date)
  }

  func restoreFromArchive(at date: Date = Date()) {
    guard archivedAt != nil else { return }
    archivedAt = nil
    settings.scheduledArchiveAt = nil
    finishChange(at: date)
  }

  func isDueForArchive(at date: Date) -> Bool {
    archivedAt == nil && settings.scheduledArchiveAt.map { $0 <= date } == true
  }

  @discardableResult
  func undo() -> Bool {
    guard canUndo else { return false }
    let action = history[historyCursor - 1]
    apply(action, forward: false)
    historyCursor -= 1
    finishChange()
    return true
  }

  @discardableResult
  func redo() -> Bool {
    guard canRedo else { return false }
    let action = history[historyCursor]
    apply(action, forward: true)
    historyCursor += 1
    finishChange()
    return true
  }

  func insertRows(at index: Int, count: Int = 1) {
    guard count > 0 else { return }
    let before = cells
    var after: [CellAddress: CellRecord] = [:]
    after.reserveCapacity(before.count)
    for (address, record) in before {
      let destination = address.row >= index
        ? CellAddress(row: address.row + count, column: address.column)
        : address
      after[destination] = record
    }
    let chartsAfter = charts.map { chart -> SpreadsheetChartDefinition in
      var changed = chart
      changed.sourceRange = chart.sourceRange.shiftedForInsertedRows(at: index, count: count)
      return changed
    }
    commitStructure(
      before: before,
      after: after,
      chartsAfter: chartsAfter,
      columnWidthsAfter: columnWidths,
      label: "Insert rows"
    )
  }

  func deleteRows(at index: Int, count: Int = 1) {
    guard count > 0 else { return }
    let before = cells
    let deletionEnd = index + count - 1
    var after: [CellAddress: CellRecord] = [:]
    after.reserveCapacity(before.count)
    for (address, record) in before {
      if address.row >= index && address.row <= deletionEnd { continue }
      let destination = address.row > deletionEnd
        ? CellAddress(row: address.row - count, column: address.column)
        : address
      after[destination] = record
    }
    let chartsAfter = charts.map { chart -> SpreadsheetChartDefinition in
      var changed = chart
      changed.sourceRange = chart.sourceRange.shiftedForDeletedRows(at: index, count: count)
        ?? CellRange(
          CellAddress(row: max(0, index), column: chart.sourceRange.start.column)
        )
      return changed
    }
    commitStructure(
      before: before,
      after: after,
      chartsAfter: chartsAfter,
      columnWidthsAfter: columnWidths,
      label: "Delete rows"
    )
  }

  func insertColumns(at index: Int, count: Int = 1) {
    guard count > 0 else { return }
    let before = cells
    var after: [CellAddress: CellRecord] = [:]
    after.reserveCapacity(before.count)
    for (address, record) in before {
      let destination = address.column >= index
        ? CellAddress(row: address.row, column: address.column + count)
        : address
      after[destination] = record
    }
    let chartsAfter = charts.map { chart -> SpreadsheetChartDefinition in
      var changed = chart
      changed.sourceRange = chart.sourceRange.shiftedForInsertedColumns(at: index, count: count)
      return changed
    }
    let columnWidthsAfter = Dictionary(
      uniqueKeysWithValues: columnWidths.map { column, width in
        (column >= index ? column + count : column, width)
      }
    )
    commitStructure(
      before: before,
      after: after,
      chartsAfter: chartsAfter,
      columnWidthsAfter: columnWidthsAfter,
      label: "Insert columns"
    )
  }

  func deleteColumns(at index: Int, count: Int = 1) {
    guard count > 0 else { return }
    let before = cells
    let deletionEnd = index + count - 1
    var after: [CellAddress: CellRecord] = [:]
    after.reserveCapacity(before.count)
    for (address, record) in before {
      if address.column >= index && address.column <= deletionEnd { continue }
      let destination = address.column > deletionEnd
        ? CellAddress(row: address.row, column: address.column - count)
        : address
      after[destination] = record
    }
    let chartsAfter = charts.map { chart -> SpreadsheetChartDefinition in
      var changed = chart
      changed.sourceRange = chart.sourceRange.shiftedForDeletedColumns(at: index, count: count)
        ?? CellRange(
          CellAddress(row: chart.sourceRange.start.row, column: max(0, index))
        )
      return changed
    }
    let shiftedColumnWidths: [(Int, Double)] = columnWidths.compactMap {
      column, width -> (Int, Double)? in
        if column >= index && column <= deletionEnd { return nil }
        return (column > deletionEnd ? column - count : column, width)
      }
    let columnWidthsAfter = Dictionary(
      uniqueKeysWithValues: shiftedColumnWidths
    )
    commitStructure(
      before: before,
      after: after,
      chartsAfter: chartsAfter,
      columnWidthsAfter: columnWidthsAfter,
      label: "Delete columns"
    )
  }

  func addChart(_ chart: SpreadsheetChartDefinition) {
    commitCharts(charts + [chart], label: "Create chart")
  }

  func updateChart(_ chart: SpreadsheetChartDefinition, label: String = "Update chart") {
    guard let index = charts.firstIndex(where: { $0.id == chart.id }) else { return }
    var updated = charts
    updated[index] = chart
    commitCharts(updated, label: label)
  }

  func removeChart(id: UUID) {
    let updated = charts.filter { $0.id != id }
    guard updated.count != charts.count else { return }
    commitCharts(updated, label: "Delete chart")
  }

  func setChartFrozen(id: UUID, frozen: Bool) {
    guard let chart = charts.first(where: { $0.id == id }) else { return }
    var changed = chart
    changed.isFrozen = frozen
    changed.frozenSeries = frozen ? chartSnapshotSeries(for: chart) : []
    updateChart(changed, label: frozen ? "Freeze chart" : "Unfreeze chart")
  }

  func chartSnapshotSeries(
    for chart: SpreadsheetChartDefinition
  ) -> [SpreadsheetChartSeries] {
    guard chart.type == .histogram else {
      return chartSeries(for: chart, ignoringFrozenState: true)
    }
    let points = histogramSamples(for: chart, ignoringFrozenState: true)
      .enumerated()
      .map { index, sample in
        SpreadsheetChartPoint(
          category: String(index + 1),
          x: nil,
          value: sample.value,
          valueIsTime: sample.isDuration
        )
      }
    return points.isEmpty
      ? []
      : [SpreadsheetChartSeries(id: "histogram", name: "Values", points: points)]
  }

  func histogramSamples(
    for chart: SpreadsheetChartDefinition,
    ignoringFrozenState: Bool = false
  ) -> [SpreadsheetHistogramSample] {
    if chart.isFrozen && !ignoringFrozenState {
      return chart.frozenSeries.flatMap { series in
        series.points.compactMap { point in
          guard point.value.isFinite else { return nil }
          return SpreadsheetHistogramSample(
            value: point.value,
            isDuration: point.valueIsTime == true
          )
        }
      }
    }

    let range = chart.sourceRange
    let startRow = range.start.row + (chart.firstRowContainsHeaders ? 1 : 0)
    guard startRow <= range.end.row else { return [] }
    var samples: [SpreadsheetHistogramSample] = []
    for row in startRow...range.end.row {
      for column in range.start.column...range.end.column {
        switch value(at: CellAddress(row: row, column: column)) {
        case .number(let number) where number.isFinite:
          samples.append(SpreadsheetHistogramSample(value: number, isDuration: false))
        case .time(let duration) where duration.isFinite:
          samples.append(SpreadsheetHistogramSample(value: duration, isDuration: true))
        default:
          continue
        }
      }
    }
    return samples
  }

  func chartSeries(
    for chart: SpreadsheetChartDefinition,
    ignoringFrozenState: Bool = false
  ) -> [SpreadsheetChartSeries] {
    if chart.isFrozen && !ignoringFrozenState { return chart.frozenSeries }
    let range = chart.sourceRange
    guard range.rowCount > 0, range.columnCount > 0 else { return [] }
    // `seriesOrientation` remains decodable for old saved charts, but Sol now
    // consistently treats spreadsheet columns as data series.
    return columnSeries(for: chart)
  }

  private func columnSeries(
    for chart: SpreadsheetChartDefinition
  ) -> [SpreadsheetChartSeries] {
    let range = chart.sourceRange
    let dataStartRow = range.start.row + (chart.firstRowContainsHeaders ? 1 : 0)
    let dataStartColumn = range.start.column + (chart.firstColumnContainsLabels ? 1 : 0)
    guard dataStartRow <= range.end.row, dataStartColumn <= range.end.column else {
      return []
    }

    return (dataStartColumn...range.end.column).map { column in
      let headerAddress = CellAddress(row: range.start.row, column: column)
      let fallbackName = CellAddress.columnName(column)
      let seriesName = chart.firstRowContainsHeaders
        ? nonEmptyDisplayText(at: headerAddress, fallback: fallbackName)
        : fallbackName
      let points = (dataStartRow...range.end.row).compactMap { row -> SpreadsheetChartPoint? in
        let valueAddress = CellAddress(row: row, column: column)
        let pointValue = value(at: valueAddress)
        guard let number = pointValue.numericValue else { return nil }
        let labelAddress = CellAddress(row: row, column: range.start.column)
        let labelValue = value(at: labelAddress)
        let category = chart.firstColumnContainsLabels
          ? nonEmptyDisplayText(at: labelAddress, fallback: String(row + 1))
          : String(row + 1)
        let x = chart.firstColumnContainsLabels
          ? labelValue.numericValue
          : Double(row - dataStartRow)
        return SpreadsheetChartPoint(
          category: category,
          x: x,
          xDate: chart.firstColumnContainsLabels ? labelValue.dateValue : nil,
          value: number,
          xIsTime: chart.firstColumnContainsLabels ? labelValue.isTime : false,
          valueIsTime: pointValue.isTime
        )
      }
      return SpreadsheetChartSeries(
        id: "column:\(column - range.start.column)",
        name: seriesName,
        points: points
      )
    }
  }

  private func nonEmptyDisplayText(at address: CellAddress, fallback: String) -> String {
    let text = displayText(at: address).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? fallback : text
  }

  private func updateStyle(
    in range: CellRange,
    label: String,
    transform: (inout CellStyle) -> Void
  ) {
    var changes: [SpreadsheetCellChange] = []
    for address in range.addresses() {
      let before = cells[address]
      var after = before ?? CellRecord(rawInput: "")
      transform(&after.style)
      let normalizedAfter = normalized(after)
      if before != normalizedAfter {
        changes.append(
          SpreadsheetCellChange(address: address, before: before, after: normalizedAfter)
        )
      }
    }
    commitCellChanges(changes, label: label)
  }

  private func updateStyle(
    at addresses: [CellAddress],
    label: String,
    transform: (inout CellStyle) -> Void
  ) {
    let changes = Set(addresses).compactMap { address -> SpreadsheetCellChange? in
      let before = cells[address]
      var after = before ?? CellRecord(rawInput: "")
      transform(&after.style)
      let normalizedAfter = normalized(after)
      guard before != normalizedAfter else { return nil }
      return SpreadsheetCellChange(
        address: address,
        before: before,
        after: normalizedAfter
      )
    }.sorted { $0.address < $1.address }
    commitCellChanges(changes, label: label)
  }

  private func commitCellChanges(_ changes: [SpreadsheetCellChange], label: String) {
    guard !changes.isEmpty else { return }
    commit(
      SpreadsheetAction(
        label: label,
        kind: .cells,
        cellChanges: changes
      )
    )
  }

  private func commitStructure(
    before: [CellAddress: CellRecord],
    after: [CellAddress: CellRecord],
    chartsAfter: [SpreadsheetChartDefinition],
    columnWidthsAfter: [Int: Double],
    label: String
  ) {
    let addresses = Set(before.keys).union(after.keys)
    let changes = addresses.compactMap { address -> SpreadsheetCellChange? in
      guard before[address] != after[address] else { return nil }
      return SpreadsheetCellChange(
        address: address,
        before: before[address],
        after: after[address]
      )
    }.sorted { $0.address < $1.address }
    guard !changes.isEmpty || chartsAfter != charts || columnWidthsAfter != columnWidths else {
      return
    }
    commit(
      SpreadsheetAction(
        label: label,
        kind: .structure,
        cellChanges: changes,
        chartsBefore: charts,
        chartsAfter: chartsAfter,
        columnWidthsBefore: columnWidths,
        columnWidthsAfter: columnWidthsAfter
      )
    )
  }

  private func commitCharts(_ updated: [SpreadsheetChartDefinition], label: String) {
    guard updated != charts else { return }
    commit(
      SpreadsheetAction(
        label: label,
        kind: .charts,
        chartsBefore: charts,
        chartsAfter: updated
      )
    )
  }

  private func commit(_ action: SpreadsheetAction) {
    if historyCursor < history.count {
      history.removeSubrange(historyCursor...)
    }
    apply(action, forward: true)
    history.append(action)
    historyCursor = history.count
    if history.count > Self.historyLimit {
      let overflow = history.count - Self.historyLimit
      history.removeFirst(overflow)
      historyCursor = max(0, historyCursor - overflow)
    }
    finishChange()
  }

  private func apply(_ action: SpreadsheetAction, forward: Bool) {
    for change in action.cellChanges {
      let record = forward ? change.after : change.before
      if let record, record.shouldPersist {
        cells[change.address] = record
      } else {
        cells.removeValue(forKey: change.address)
      }
    }
    if action.kind == .rename {
      name = (forward ? action.nameAfter : action.nameBefore) ?? name
    }
    if let changedCharts = forward ? action.chartsAfter : action.chartsBefore {
      charts = changedCharts
    }
    if let changedWidths = forward ? action.columnWidthsAfter : action.columnWidthsBefore {
      columnWidths = changedWidths
    }
    if let changedSettings = forward ? action.settingsAfter : action.settingsBefore {
      settings = changedSettings
    }
  }

  private func finishChange(at date: Date = Date()) {
    updatedAt = date
    inferredDateYearsByColumn.removeAll(keepingCapacity: true)
    formulaEngine.invalidate()
    onChange?(self)
    NotificationCenter.default.post(name: .floatingSpreadsheetDidChange, object: self)
  }

  private func normalized(_ record: CellRecord) -> CellRecord? {
    record.shouldPersist ? record : nil
  }

  private func materializedInput(_ rawInput: String, now: Date = Date()) -> String {
    let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.caseInsensitiveCompare("=now") == .orderedSame else {
      return rawInput
    }
    return SpreadsheetDate.timestamp(now, timeZone: settings.timeZone)
  }

  private func literalValue(
    for record: CellRecord,
    at address: CellAddress
  ) -> SpreadsheetValue {
    switch columnType(at: address.column) {
    case .text:
      return record.rawInput.isEmpty ? .blank : .text(record.rawInput)
    case .number:
      let trimmed = record.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasSuffix("%"),
        let number = FlexibleNumberParser.parse(
          String(trimmed.dropLast()),
          locale: settings.displayLocale.locale
        )
      {
        return .number(number / 100)
      }
      return FlexibleNumberParser.parse(
        trimmed,
        locale: settings.displayLocale.locale
      ).map(SpreadsheetValue.number) ?? .text(record.rawInput)
    case .dateTime:
      return contextualDateValue(for: record.rawInput, at: address)
        ?? .text(record.rawInput)
    case .automatic:
      if let date = contextualDateValue(for: record.rawInput, at: address) {
        return date
      }
      return formulaEngine.literalValue(for: record)
    }
  }

  private func contextualDateValue(
    for rawInput: String,
    at address: CellAddress
  ) -> SpreadsheetValue? {
    let parsedComponents = SpreadsheetDate.components(
      rawInput,
      displayLocale: settings.displayLocale
    )
    if let parsedComponents {
      let inferredYear = parsedComponents.year
        ?? inferredDateYears(for: address.column)[address.row]
      guard let inferredYear,
        let date = SpreadsheetDate.date(
          from: parsedComponents,
          year: inferredYear,
          timeZone: settings.timeZone
        )
      else {
        return nil
      }
      return .date(date)
    }
    return SpreadsheetDate.parse(
      rawInput,
      displayLocale: settings.displayLocale,
      timeZone: settings.timeZone
    ).map(SpreadsheetValue.date)
  }

  private func normalizedDates(
    at addresses: [CellAddress]
  ) -> [(CellAddress, String)]? {
    let uniqueAddresses = Set(addresses).sorted()
    guard !uniqueAddresses.isEmpty else { return nil }
    var result: [(CellAddress, String)] = []
    result.reserveCapacity(uniqueAddresses.count)
    for address in uniqueAddresses {
      guard let record = cells[address],
        !record.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        case .date(let date) = contextualDateValue(
          for: record.rawInput,
          at: address
        )
      else {
        return nil
      }
      result.append((
        address,
        SpreadsheetDate.timestamp(date, timeZone: settings.timeZone)
      ))
    }
    return result
  }

  private func inferredDateYears(for column: Int) -> [Int: Int] {
    if let cached = inferredDateYearsByColumn[column] { return cached }
    let entries = cells.compactMap { address, record -> (
      row: Int,
      components: SpreadsheetDateComponents
    )? in
      guard address.column == column,
        !record.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("="),
        let components = SpreadsheetDate.components(
          record.rawInput,
          displayLocale: settings.displayLocale
        )
      else {
        return nil
      }
      return (address.row, components)
    }.sorted { $0.row < $1.row }

    guard !entries.isEmpty else {
      inferredDateYearsByColumn[column] = [:]
      return [:]
    }

    let currentYear = Calendar(identifier: .gregorian).dateComponents(
      in: settings.timeZone,
      from: Date()
    ).year ?? 1970
    var result: [Int: Int] = [:]

    if let firstAnchor = entries.firstIndex(where: { $0.components.year != nil }),
      let anchorYear = entries[firstAnchor].components.year
    {
      result[entries[firstAnchor].row] = anchorYear
      var year = anchorYear
      if firstAnchor > 0 {
        for index in stride(from: firstAnchor - 1, through: 0, by: -1) {
          let newer = entries[index + 1].components
          let older = entries[index].components
          year += yearChange(from: newer, to: older)
          if let explicitYear = older.year { year = explicitYear }
          result[entries[index].row] = year
        }
      }

      year = anchorYear
      if firstAnchor + 1 < entries.count {
        for index in (firstAnchor + 1)..<entries.count {
          let previous = entries[index - 1].components
          let current = entries[index].components
          year += yearChange(from: previous, to: current)
          if let explicitYear = current.year { year = explicitYear }
          result[entries[index].row] = year
        }
      }
    } else {
      var year = currentYear
      result[entries[0].row] = year
      if entries.count > 1 {
        for index in 1..<entries.count {
          year += yearChange(
            from: entries[index - 1].components,
            to: entries[index].components
          )
          result[entries[index].row] = year
        }
      }
    }

    inferredDateYearsByColumn[column] = result
    return result
  }

  private func yearChange(
    from previous: SpreadsheetDateComponents,
    to current: SpreadsheetDateComponents
  ) -> Int {
    if previous.month >= 10, current.month <= 3 { return 1 }
    if previous.month <= 3, current.month >= 10 { return -1 }
    return 0
  }

  private func effectiveFormat(
    record: CellRecord?,
    value: SpreadsheetValue
  ) -> CellDisplayFormat {
    guard let record else { return .automatic }
    if record.style.displayFormat != .automatic { return record.style.displayFormat }
    if record.rawInput.trimmingCharacters(in: .whitespaces).hasSuffix("%") {
      return .percent
    }
    if case .date = value { return .date }
    if case .time = value { return .time }
    return .automatic
  }

  private func formatNumber(_ number: Double, as format: CellDisplayFormat) -> String {
    if format == .time {
      return SpreadsheetTime.format(number)
    }
    if format == .date {
      var components = DateComponents()
      components.calendar = Calendar(identifier: .gregorian)
      components.timeZone = TimeZone(secondsFromGMT: 0)
      components.year = 1899
      components.month = 12
      components.day = 30
      if let epoch = components.date {
        let date = epoch.addingTimeInterval(number * 86_400)
        let formatter = DateFormatter()
        formatter.locale = settings.displayLocale.locale
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
      }
    }

    let formatter = NumberFormatter()
    formatter.locale = settings.displayLocale.locale
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 10
    formatter.usesGroupingSeparator = true
    switch format {
    case .percent:
      formatter.numberStyle = .percent
      formatter.maximumFractionDigits = 4
    case .currency:
      formatter.numberStyle = .currency
      formatter.currencyCode = settings.currencyCode
      formatter.maximumFractionDigits = 4
    default:
      formatter.numberStyle = .decimal
    }
    return formatter.string(from: NSNumber(value: number)) ?? String(number)
  }
}
