import Foundation

extension Notification.Name {
  static let floatingSpreadsheetDidChange = Notification.Name(
    "FloatingSpreadsheetKit.documentDidChange"
  )
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

  func referenceRanges(at address: CellAddress) -> [CellRange] {
    formulaEngine.referenceRanges(in: rawInput(at: address))
  }

  func isEmpty(_ range: CellRange) -> Bool {
    !cells.contains { range.contains($0.key) && !$0.value.rawInput.isEmpty }
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
      let formatter = DateFormatter()
      formatter.locale = settings.displayLocale.locale
      formatter.dateStyle = .short
      formatter.timeStyle = .none
      return formatter.string(from: date)
    case .time(let fractionOfDay):
      return SpreadsheetTime.format(fractionOfDay)
    case .number(let number):
      return formatNumber(number, as: format)
    }
  }

  func setRawInput(_ rawInput: String, at address: CellAddress, label: String = "Edit cell") {
    let old = cells[address]
    var new = old ?? CellRecord(rawInput: "")
    new.rawInput = rawInput
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
    var changes: [SpreadsheetCellChange] = []
    for (rowOffset, row) in rows.enumerated() {
      for (columnOffset, rawInput) in row.enumerated() {
        let address = CellAddress(
          row: origin.row + rowOffset,
          column: origin.column + columnOffset
        )
        let before = cells[address]
        var after = before ?? CellRecord(rawInput: "")
        after.rawInput = rawInput
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

  func setBold(_ enabled: Bool, in range: CellRange) {
    updateStyle(in: range, label: enabled ? "Bold" : "Remove bold") {
      $0.isBold = enabled
    }
  }

  func setItalic(_ enabled: Bool, in range: CellRange) {
    updateStyle(in: range, label: enabled ? "Italic" : "Remove italic") {
      $0.isItalic = enabled
    }
  }

  func setDisplayFormat(_ format: CellDisplayFormat, in range: CellRange) {
    updateStyle(in: range, label: "Format cells") {
      $0.displayFormat = format
    }
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
    return points.isEmpty ? [] : [SpreadsheetChartSeries(name: "Values", points: points)]
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
    switch chart.seriesOrientation {
    case .columns:
      return columnSeries(for: chart)
    case .rows:
      return rowSeries(for: chart)
    }
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
      return SpreadsheetChartSeries(name: seriesName, points: points)
    }
  }

  private func rowSeries(
    for chart: SpreadsheetChartDefinition
  ) -> [SpreadsheetChartSeries] {
    let range = chart.sourceRange
    let dataStartRow = range.start.row + (chart.firstRowContainsHeaders ? 1 : 0)
    let dataStartColumn = range.start.column + (chart.firstColumnContainsLabels ? 1 : 0)
    guard dataStartRow <= range.end.row, dataStartColumn <= range.end.column else {
      return []
    }

    return (dataStartRow...range.end.row).map { row in
      let labelAddress = CellAddress(row: row, column: range.start.column)
      let seriesName = chart.firstColumnContainsLabels
        ? nonEmptyDisplayText(at: labelAddress, fallback: "Row \(row + 1)")
        : "Row \(row + 1)"
      let points = (dataStartColumn...range.end.column).compactMap {
        column -> SpreadsheetChartPoint? in
        let valueAddress = CellAddress(row: row, column: column)
        let pointValue = value(at: valueAddress)
        guard let number = pointValue.numericValue else { return nil }
        let headerAddress = CellAddress(row: range.start.row, column: column)
        let headerValue = value(at: headerAddress)
        let category = chart.firstRowContainsHeaders
          ? nonEmptyDisplayText(
            at: headerAddress,
            fallback: CellAddress.columnName(column)
          )
          : CellAddress.columnName(column)
        let x = chart.firstRowContainsHeaders
          ? headerValue.numericValue
          : Double(column - dataStartColumn)
        return SpreadsheetChartPoint(
          category: category,
          x: x,
          xDate: chart.firstRowContainsHeaders ? headerValue.dateValue : nil,
          value: number,
          xIsTime: chart.firstRowContainsHeaders ? headerValue.isTime : false,
          valueIsTime: pointValue.isTime
        )
      }
      return SpreadsheetChartSeries(name: seriesName, points: points)
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
    formulaEngine.invalidate()
    onChange?(self)
    NotificationCenter.default.post(name: .floatingSpreadsheetDidChange, object: self)
  }

  private func normalized(_ record: CellRecord) -> CellRecord? {
    record.shouldPersist ? record : nil
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
