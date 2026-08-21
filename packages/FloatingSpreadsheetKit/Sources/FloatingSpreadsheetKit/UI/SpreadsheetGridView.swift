import AppKit

protocol SpreadsheetGridViewDelegate: AnyObject {
  func spreadsheetGridView(
    _ gridView: SpreadsheetGridView,
    selectionDidChange range: CellRange
  )
  func spreadsheetGridView(
    _ gridView: SpreadsheetGridView,
    pasteText text: String,
    at origin: CellAddress
  )
  func spreadsheetGridViewDidRequestBold(_ gridView: SpreadsheetGridView)
  func spreadsheetGridViewDidRequestItalic(_ gridView: SpreadsheetGridView)
}

final class SpreadsheetGridContainerView: NSView {
  static let rowHeaderWidth: CGFloat = 48
  static let columnHeaderHeight: CGFloat = 24

  let gridView: SpreadsheetGridView
  private let scrollView = NSScrollView()
  private let columnHeader: SpreadsheetColumnHeaderView
  private let rowHeader: SpreadsheetRowHeaderView
  private let cornerView = NSView()
  private var boundsObserver: NSObjectProtocol?

  init(document: SpreadsheetDocument) {
    gridView = SpreadsheetGridView(document: document)
    columnHeader = SpreadsheetColumnHeaderView(gridView: gridView)
    rowHeader = SpreadsheetRowHeaderView(gridView: gridView)
    super.init(frame: .zero)

    wantsLayer = true
    layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

    scrollView.documentView = gridView
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = true
    scrollView.backgroundColor = .textBackgroundColor
    scrollView.borderType = .noBorder
    scrollView.contentView.postsBoundsChangedNotifications = true

    cornerView.wantsLayer = true
    cornerView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

    addSubview(scrollView)
    addSubview(columnHeader)
    addSubview(rowHeader)
    addSubview(cornerView)

    boundsObserver = NotificationCenter.default.addObserver(
      forName: NSView.boundsDidChangeNotification,
      object: scrollView.contentView,
      queue: .main
    ) { [weak self] _ in
      self?.synchronizeHeaders()
    }

    gridView.onSelectionVisualChange = { [weak self] in
      self?.columnHeader.needsDisplay = true
      self?.rowHeader.needsDisplay = true
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    if let boundsObserver {
      NotificationCenter.default.removeObserver(boundsObserver)
    }
  }

  override func layout() {
    super.layout()
    let rowWidth = Self.rowHeaderWidth
    let columnHeight = Self.columnHeaderHeight
    scrollView.frame = NSRect(
      x: rowWidth,
      y: 0,
      width: max(0, bounds.width - rowWidth),
      height: max(0, bounds.height - columnHeight)
    )
    columnHeader.frame = NSRect(
      x: rowWidth,
      y: max(0, bounds.height - columnHeight),
      width: max(0, bounds.width - rowWidth),
      height: columnHeight
    )
    rowHeader.frame = NSRect(
      x: 0,
      y: 0,
      width: rowWidth,
      height: max(0, bounds.height - columnHeight)
    )
    cornerView.frame = NSRect(
      x: 0,
      y: max(0, bounds.height - columnHeight),
      width: rowWidth,
      height: columnHeight
    )
    synchronizeHeaders()
  }

  func reloadData() {
    gridView.reloadData()
    columnHeader.needsDisplay = true
    rowHeader.needsDisplay = true
  }

  private func synchronizeHeaders() {
    let origin = scrollView.contentView.bounds.origin
    columnHeader.scrollOffset = origin.x
    rowHeader.scrollOffset = origin.y
  }
}

final class SpreadsheetGridView: NSView, NSTextFieldDelegate {
  static let rowCount = 1_048_576
  static let columnCount = 16_384
  static let rowHeight: CGFloat = 25
  static let columnWidth: CGFloat = 112

  weak var delegate: SpreadsheetGridViewDelegate?
  var onSelectionVisualChange: (() -> Void)?

  let document: SpreadsheetDocument
  private(set) var selectedRange = CellRange(CellAddress(row: 0, column: 0))
  private(set) var activeCell = CellAddress(row: 0, column: 0)
  private var selectionAnchor = CellAddress(row: 0, column: 0)
  private var editor: NSTextField?
  private var editingOriginalValue = ""
  private var editingReferenceRanges: [CellRange] = []
  private var isFinishingEdit = false
  private let previewFormulaEngine = SpreadsheetFormulaEngine()

  init(document: SpreadsheetDocument) {
    self.document = document
    let size = NSSize(
      width: CGFloat(Self.columnCount) * Self.columnWidth,
      height: CGFloat(Self.rowCount) * Self.rowHeight
    )
    super.init(frame: NSRect(origin: .zero, size: size))
    setAccessibilityRole(.table)
    setAccessibilityLabel("Spreadsheet grid")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override var isOpaque: Bool { true }

  func reloadData() {
    needsDisplay = true
    if let editor {
      editor.frame = cellRect(activeCell).insetBy(dx: 1, dy: 1)
    }
  }

  func applyImportedRows(_ rows: [[String]], firstRowIsHeader: Bool) {
    document.replaceCells(
      startingAt: activeCell,
      rows: rows,
      firstRowIsHeader: firstRowIsHeader,
      label: "Import cells"
    )
    let rowCount = max(1, rows.count)
    let columnCount = max(1, rows.map { $0.count }.max() ?? 1)
    selectedRange = CellRange(
      start: activeCell,
      end: CellAddress(
        row: activeCell.row + rowCount - 1,
        column: activeCell.column + columnCount - 1
      )
    )
    selectionAnchor = activeCell
    notifySelectionChanged()
    reloadData()
  }

  override func draw(_ dirtyRect: NSRect) {
    let clippedDirtyRect = dirtyRect.intersection(bounds)
    guard !clippedDirtyRect.isEmpty else { return }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSBezierPath(rect: bounds).addClip()

    NSColor.textBackgroundColor.setFill()
    clippedDirtyRect.fill()

    let firstColumn = max(0, Int(floor(clippedDirtyRect.minX / Self.columnWidth)))
    let lastColumn = min(
      Self.columnCount - 1,
      Int(floor(max(0, clippedDirtyRect.maxX - 0.01) / Self.columnWidth))
    )
    let firstRow = max(0, Int(floor(clippedDirtyRect.minY / Self.rowHeight)))
    let lastRow = min(
      Self.rowCount - 1,
      Int(floor(max(0, clippedDirtyRect.maxY - 0.01) / Self.rowHeight))
    )
    guard firstColumn <= lastColumn, firstRow <= lastRow else { return }

    drawReferenceHighlights(
      firstRow: firstRow,
      lastRow: lastRow,
      firstColumn: firstColumn,
      lastColumn: lastColumn
    )
    drawSelection(in: clippedDirtyRect)

    for row in firstRow...lastRow {
      for column in firstColumn...lastColumn {
        drawCell(CellAddress(row: row, column: column))
      }
    }
    drawGrid(
      clippedDirtyRect,
      firstRow: firstRow,
      lastRow: lastRow,
      firstColumn: firstColumn,
      lastColumn: lastColumn
    )
    drawSelectionBorder()
  }

  private func drawCell(_ address: CellAddress) {
    let text = document.displayText(at: address)
    guard !text.isEmpty else { return }
    let record = document.record(at: address)
    let style = record?.style ?? .plain
    var traits: NSFontTraitMask = []
    if style.isBold { traits.insert(.boldFontMask) }
    if style.isItalic { traits.insert(.italicFontMask) }
    let baseFont = NSFont.systemFont(ofSize: 12)
    let font = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)

    let paragraph = NSMutableParagraphStyle()
    switch document.value(at: address) {
    case .number, .date:
      paragraph.alignment = .right
    default:
      paragraph.alignment = .left
    }
    paragraph.lineBreakMode = .byClipping

    let rect = cellRect(address).insetBy(dx: 5, dy: 4)
    (text as NSString).draw(
      in: rect,
      withAttributes: [
        .font: font,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: paragraph,
      ]
    )
  }

  private func drawReferenceHighlights(
    firstRow: Int,
    lastRow: Int,
    firstColumn: Int,
    lastColumn: Int
  ) {
    let colors: [NSColor] = [.systemOrange, .systemPurple, .systemTeal, .systemPink]
    for (index, range) in editingReferenceRanges.enumerated() {
      let visibleStart = CellAddress(
        row: max(firstRow, range.start.row),
        column: max(firstColumn, range.start.column)
      )
      let visibleEnd = CellAddress(
        row: min(lastRow, range.end.row),
        column: min(lastColumn, range.end.column)
      )
      guard visibleStart.row <= visibleEnd.row,
        visibleStart.column <= visibleEnd.column
      else {
        continue
      }
      let color = colors[index % colors.count]
      color.withAlphaComponent(0.12).setFill()
      rangeRect(CellRange(start: visibleStart, end: visibleEnd)).fill()
      color.withAlphaComponent(0.8).setStroke()
      let path = NSBezierPath(rect: rangeRect(range).insetBy(dx: 1, dy: 1))
      path.lineWidth = 1.5
      path.stroke()
    }
  }

  private func drawSelection(in dirtyRect: NSRect) {
    let rect = rangeRect(selectedRange)
    guard rect.intersects(dirtyRect) else { return }
    NSColor.controlAccentColor.withAlphaComponent(0.11).setFill()
    rect.intersection(dirtyRect).fill()
  }

  private func drawSelectionBorder() {
    NSColor.controlAccentColor.setStroke()
    let path = NSBezierPath(rect: rangeRect(selectedRange).insetBy(dx: 1, dy: 1))
    path.lineWidth = 2
    path.stroke()
  }

  private func drawGrid(
    _ dirtyRect: NSRect,
    firstRow: Int,
    lastRow: Int,
    firstColumn: Int,
    lastColumn: Int
  ) {
    let path = NSBezierPath()
    for column in firstColumn...(lastColumn + 1) {
      let x = CGFloat(column) * Self.columnWidth + 0.5
      path.move(to: NSPoint(x: x, y: dirtyRect.minY))
      path.line(to: NSPoint(x: x, y: dirtyRect.maxY))
    }
    for row in firstRow...(lastRow + 1) {
      let y = CGFloat(row) * Self.rowHeight + 0.5
      path.move(to: NSPoint(x: dirtyRect.minX, y: y))
      path.line(to: NSPoint(x: dirtyRect.maxX, y: y))
    }
    NSColor.gridColor.setStroke()
    path.lineWidth = 0.5
    path.stroke()
  }

  override func mouseDown(with event: NSEvent) {
    finishEditing(commit: true)
    let address = address(at: convert(event.locationInWindow, from: nil))
    if event.modifierFlags.contains(.shift) {
      activeCell = address
      selectedRange = CellRange(start: selectionAnchor, end: address)
    } else {
      activeCell = address
      selectionAnchor = address
      selectedRange = CellRange(address)
    }
    window?.makeFirstResponder(self)
    notifySelectionChanged()
    if event.clickCount >= 2 {
      beginEditing(replacingWith: nil)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    autoscroll(with: event)
    let address = address(at: convert(event.locationInWindow, from: nil))
    activeCell = address
    selectedRange = CellRange(start: selectionAnchor, end: address)
    notifySelectionChanged()
  }

  override func keyDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if modifiers.contains(.command) {
      switch event.charactersIgnoringModifiers?.lowercased() {
      case "c": copySelection()
      case "x": cutSelection()
      case "v": pasteSelection()
      case "z":
        if modifiers.contains(.shift) {
          _ = document.redo()
        } else {
          _ = document.undo()
        }
        reloadData()
      case "y":
        _ = document.redo()
        reloadData()
      case "b": delegate?.spreadsheetGridViewDidRequestBold(self)
      case "i": delegate?.spreadsheetGridViewDidRequestItalic(self)
      default: super.keyDown(with: event)
      }
      return
    }

    switch event.keyCode {
    case 123: moveSelection(rowDelta: 0, columnDelta: -1, extending: modifiers.contains(.shift))
    case 124: moveSelection(rowDelta: 0, columnDelta: 1, extending: modifiers.contains(.shift))
    case 125: moveSelection(rowDelta: 1, columnDelta: 0, extending: modifiers.contains(.shift))
    case 126: moveSelection(rowDelta: -1, columnDelta: 0, extending: modifiers.contains(.shift))
    case 48:
      moveSelection(
        rowDelta: 0,
        columnDelta: modifiers.contains(.shift) ? -1 : 1,
        extending: false
      )
    case 36, 76:
      moveSelection(rowDelta: 1, columnDelta: 0, extending: false)
    case 51, 117:
      document.clear(selectedRange)
      reloadData()
    default:
      if let characters = event.characters,
        !characters.isEmpty,
        characters.unicodeScalars.allSatisfy({
          !CharacterSet.controlCharacters.contains($0)
        })
      {
        beginEditing(replacingWith: characters)
      } else {
        super.keyDown(with: event)
      }
    }
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let address = address(at: convert(event.locationInWindow, from: nil))
    activeCell = address
    selectionAnchor = address
    selectedRange = CellRange(address)
    notifySelectionChanged()

    let menu = NSMenu()
    menu.addItem(withTitle: "Insert row above", action: #selector(insertRow), keyEquivalent: "")
    menu.addItem(withTitle: "Delete row", action: #selector(deleteRow), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Insert column before",
      action: #selector(insertColumn),
      keyEquivalent: ""
    )
    menu.addItem(withTitle: "Delete column", action: #selector(deleteColumn), keyEquivalent: "")
    for item in menu.items { item.target = self }
    return menu
  }

  @objc private func insertRow() {
    document.insertRows(at: activeCell.row)
    reloadData()
  }

  @objc private func deleteRow() {
    document.deleteRows(at: activeCell.row)
    reloadData()
  }

  @objc private func insertColumn() {
    document.insertColumns(at: activeCell.column)
    reloadData()
  }

  @objc private func deleteColumn() {
    document.deleteColumns(at: activeCell.column)
    reloadData()
  }

  private func moveSelection(rowDelta: Int, columnDelta: Int, extending: Bool) {
    let destination = CellAddress(
      row: min(Self.rowCount - 1, max(0, activeCell.row + rowDelta)),
      column: min(Self.columnCount - 1, max(0, activeCell.column + columnDelta))
    )
    activeCell = destination
    if extending {
      selectedRange = CellRange(start: selectionAnchor, end: destination)
    } else {
      selectionAnchor = destination
      selectedRange = CellRange(destination)
    }
    scrollToVisible(cellRect(destination))
    notifySelectionChanged()
  }

  private func beginEditing(replacingWith replacement: String?) {
    guard editor == nil else { return }
    let original = document.rawInput(at: activeCell)
    editingOriginalValue = original
    let field = NSTextField(frame: cellRect(activeCell).insetBy(dx: 1, dy: 1))
    field.stringValue = replacement ?? original
    field.font = .systemFont(ofSize: 12)
    field.isBordered = true
    field.isBezeled = true
    field.bezelStyle = .squareBezel
    field.drawsBackground = true
    field.backgroundColor = .textBackgroundColor
    field.focusRingType = .none
    field.cell?.usesSingleLineMode = true
    field.cell?.lineBreakMode = .byClipping
    field.delegate = self
    addSubview(field)
    editor = field
    updateEditingReferences(field.stringValue)
    window?.makeFirstResponder(field)
    field.currentEditor()?.selectedRange = NSRange(
      location: (field.stringValue as NSString).length,
      length: 0
    )
  }

  private func finishEditing(commit: Bool, movement: (Int, Int)? = nil) {
    guard let field = editor, !isFinishingEdit else { return }
    isFinishingEdit = true
    let value = field.stringValue
    field.delegate = nil
    field.removeFromSuperview()
    editor = nil
    editingReferenceRanges = []
    if commit, value != editingOriginalValue {
      document.setRawInput(value, at: activeCell)
    }
    isFinishingEdit = false
    window?.makeFirstResponder(self)
    reloadData()
    if let movement {
      moveSelection(rowDelta: movement.0, columnDelta: movement.1, extending: false)
    }
  }

  func controlTextDidChange(_ notification: Notification) {
    guard let field = notification.object as? NSTextField, field === editor else { return }
    updateEditingReferences(field.stringValue)
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    finishEditing(commit: true)
  }

  func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      finishEditing(commit: true, movement: (1, 0))
      return true
    case #selector(NSResponder.insertTab(_:)):
      finishEditing(commit: true, movement: (0, 1))
      return true
    case #selector(NSResponder.insertBacktab(_:)):
      finishEditing(commit: true, movement: (0, -1))
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      finishEditing(commit: false)
      return true
    default:
      return false
    }
  }

  private func updateEditingReferences(_ rawInput: String) {
    editingReferenceRanges = previewFormulaEngine.referenceRanges(in: rawInput)
    needsDisplay = true
  }

  private func copySelection() {
    let addresses = selectedRange.addresses()
    guard !addresses.isEmpty else {
      NSSound.beep()
      return
    }
    var rows: [String] = []
    for row in selectedRange.start.row...selectedRange.end.row {
      let values = (selectedRange.start.column...selectedRange.end.column).map { column in
        escapedClipboardValue(
          document.rawInput(at: CellAddress(row: row, column: column))
        )
      }
      rows.append(values.joined(separator: "\t"))
    }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(rows.joined(separator: "\n"), forType: .string)
  }

  private func cutSelection() {
    copySelection()
    document.clear(selectedRange, label: "Cut cells")
    reloadData()
  }

  private func pasteSelection() {
    guard let text = NSPasteboard.general.string(forType: .string) else { return }
    delegate?.spreadsheetGridView(self, pasteText: text, at: activeCell)
  }

  private func escapedClipboardValue(_ value: String) -> String {
    guard value.contains("\t") || value.contains("\n") || value.contains("\"") else {
      return value
    }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }

  private func notifySelectionChanged() {
    needsDisplay = true
    onSelectionVisualChange?()
    delegate?.spreadsheetGridView(self, selectionDidChange: selectedRange)
  }

  func cellRect(_ address: CellAddress) -> NSRect {
    NSRect(
      x: CGFloat(address.column) * Self.columnWidth,
      y: CGFloat(address.row) * Self.rowHeight,
      width: Self.columnWidth,
      height: Self.rowHeight
    )
  }

  func rangeRect(_ range: CellRange) -> NSRect {
    NSRect(
      x: CGFloat(range.start.column) * Self.columnWidth,
      y: CGFloat(range.start.row) * Self.rowHeight,
      width: CGFloat(range.columnCount) * Self.columnWidth,
      height: CGFloat(range.rowCount) * Self.rowHeight
    )
  }

  private func address(at point: NSPoint) -> CellAddress {
    CellAddress(
      row: min(Self.rowCount - 1, max(0, Int(floor(point.y / Self.rowHeight)))),
      column: min(Self.columnCount - 1, max(0, Int(floor(point.x / Self.columnWidth))))
    )
  }
}

private final class SpreadsheetColumnHeaderView: NSView {
  weak var gridView: SpreadsheetGridView?
  var scrollOffset: CGFloat = 0 {
    didSet { if oldValue != scrollOffset { needsDisplay = true } }
  }

  init(gridView: SpreadsheetGridView) {
    self.gridView = gridView
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    let clippedDirtyRect = dirtyRect.intersection(bounds)
    guard !clippedDirtyRect.isEmpty else { return }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSBezierPath(rect: bounds).addClip()

    NSColor.controlBackgroundColor.setFill()
    clippedDirtyRect.fill()
    guard let gridView else { return }
    let first = max(0, Int(floor(scrollOffset / SpreadsheetGridView.columnWidth)))
    let last = min(
      SpreadsheetGridView.columnCount - 1,
      Int(ceil((scrollOffset + bounds.width) / SpreadsheetGridView.columnWidth))
    )
    guard first <= last else { return }
    for column in first...last {
      let x = CGFloat(column) * SpreadsheetGridView.columnWidth - scrollOffset
      let rect = NSRect(
        x: x,
        y: 0,
        width: SpreadsheetGridView.columnWidth,
        height: bounds.height
      )
      if column >= gridView.selectedRange.start.column,
        column <= gridView.selectedRange.end.column
      {
        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        rect.fill()
      }
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      (CellAddress.columnName(column) as NSString).draw(
        in: rect.insetBy(dx: 2, dy: 4),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 11, weight: .medium),
          .foregroundColor: NSColor.secondaryLabelColor,
          .paragraphStyle: paragraph,
        ]
      )
      NSColor.gridColor.setStroke()
      NSBezierPath.strokeLine(
        from: NSPoint(x: rect.maxX - 0.5, y: 0),
        to: NSPoint(x: rect.maxX - 0.5, y: bounds.height)
      )
    }
    NSColor.gridColor.setStroke()
    NSBezierPath.strokeLine(
      from: NSPoint(x: 0, y: bounds.height - 0.5),
      to: NSPoint(x: bounds.width, y: bounds.height - 0.5)
    )
  }
}

private final class SpreadsheetRowHeaderView: NSView {
  weak var gridView: SpreadsheetGridView?
  var scrollOffset: CGFloat = 0 {
    didSet { if oldValue != scrollOffset { needsDisplay = true } }
  }

  init(gridView: SpreadsheetGridView) {
    self.gridView = gridView
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    let clippedDirtyRect = dirtyRect.intersection(bounds)
    guard !clippedDirtyRect.isEmpty else { return }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSBezierPath(rect: bounds).addClip()

    NSColor.controlBackgroundColor.setFill()
    clippedDirtyRect.fill()
    guard let gridView else { return }
    let first = max(0, Int(floor(scrollOffset / SpreadsheetGridView.rowHeight)))
    let last = min(
      SpreadsheetGridView.rowCount - 1,
      Int(ceil((scrollOffset + bounds.height) / SpreadsheetGridView.rowHeight))
    )
    guard first <= last else { return }
    for row in first...last {
      let y = CGFloat(row) * SpreadsheetGridView.rowHeight - scrollOffset
      let rect = NSRect(
        x: 0,
        y: y,
        width: bounds.width,
        height: SpreadsheetGridView.rowHeight
      )
      if row >= gridView.selectedRange.start.row,
        row <= gridView.selectedRange.end.row
      {
        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        rect.fill()
      }
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .right
      (String(row + 1) as NSString).draw(
        in: rect.insetBy(dx: 5, dy: 5),
        withAttributes: [
          .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
          .foregroundColor: NSColor.secondaryLabelColor,
          .paragraphStyle: paragraph,
        ]
      )
      NSColor.gridColor.setStroke()
      NSBezierPath.strokeLine(
        from: NSPoint(x: 0, y: rect.maxY - 0.5),
        to: NSPoint(x: bounds.width, y: rect.maxY - 0.5)
      )
    }
    NSColor.gridColor.setStroke()
    NSBezierPath.strokeLine(
      from: NSPoint(x: bounds.width - 0.5, y: 0),
      to: NSPoint(x: bounds.width - 0.5, y: bounds.height)
    )
  }
}
