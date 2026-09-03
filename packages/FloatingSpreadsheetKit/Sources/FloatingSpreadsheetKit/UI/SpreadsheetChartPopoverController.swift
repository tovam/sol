import AppKit

final class SpreadsheetChartPopoverController: NSViewController {
  var onCreate: ((SpreadsheetChartDefinition) -> Void)?
  var onOpen: ((SpreadsheetChartDefinition) -> Void)?

  private let document: SpreadsheetDocument
  private let initialRange: CellRange
  private let titleField = NSTextField(string: "Chart")
  private let rangeField = NSTextField()
  private let typePopup = NSPopUpButton()
  private let xModeControl = NSSegmentedControl(
    labels: ["Row index", "First column = X"],
    trackingMode: .selectOne,
    target: nil,
    action: nil
  )
  private let headerCheckbox = NSButton(
    checkboxWithTitle: "First row contains headers",
    target: nil,
    action: nil
  )
  private let savedChartsPopup = NSPopUpButton()
  private let validationLabel = NSTextField(labelWithString: "")

  init(document: SpreadsheetDocument, initialRange: CellRange) {
    self.document = document
    self.initialRange = initialRange
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 310, height: 292))
    rangeField.stringValue = initialRange.description
    rangeField.placeholderString = "A1:D12"
    typePopup.addItems(withTitles: SpreadsheetChartType.allCases.map {
      $0.rawValue.capitalized
    })
    typePopup.target = self
    typePopup.action = #selector(chartTypeChanged)
    headerCheckbox.state = .on
    xModeControl.selectedSegment = initialRange.columnCount > 1 ? 1 : 0
    xModeControl.setAccessibilityLabel("Horizontal axis source")
    updateControlsForSelectedType()

    let grid = NSGridView(views: [
      [NSTextField(labelWithString: "Title"), titleField],
      [NSTextField(labelWithString: "Type"), typePopup],
      [NSTextField(labelWithString: "Range"), rangeField],
      [NSTextField(labelWithString: "X values"), xModeControl],
    ])
    grid.rowSpacing = 7
    grid.columnSpacing = 10
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .fill

    validationLabel.textColor = .systemRed
    validationLabel.font = .systemFont(ofSize: 10)
    validationLabel.isHidden = true

    let createButton = NSButton(title: "Create chart", target: self, action: #selector(createChart))
    createButton.keyEquivalent = "\r"
    createButton.bezelStyle = .rounded

    let savedStack = NSStackView()
    savedStack.orientation = .horizontal
    savedStack.spacing = 6
    savedStack.alignment = .centerY
    let savedLabel = NSTextField(labelWithString: "Saved")
    savedLabel.textColor = .secondaryLabelColor
    savedChartsPopup.addItems(withTitles: document.charts.map(\.title))
    savedChartsPopup.isEnabled = !document.charts.isEmpty
    let openButton = NSButton(title: "Open", target: self, action: #selector(openSavedChart))
    openButton.isEnabled = !document.charts.isEmpty
    savedStack.addArrangedSubview(savedLabel)
    savedStack.addArrangedSubview(savedChartsPopup)
    savedStack.addArrangedSubview(openButton)

    let separator = NSBox()
    separator.boxType = .separator
    let stack = NSStackView(views: [
      grid,
      headerCheckbox,
      validationLabel,
      createButton,
      separator,
      savedStack,
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      stack.topAnchor.constraint(equalTo: root.topAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
      grid.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
      createButton.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
      savedStack.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
    ])
    savedChartsPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view = root
  }

  @objc private func createChart() {
    guard let range = CellRange(rangeField.stringValue) else {
      validationLabel.stringValue = "Use a cell range such as A1:D12."
      validationLabel.isHidden = false
      NSSound.beep()
      return
    }
    validationLabel.isHidden = true
    let types = SpreadsheetChartType.allCases
    let type = types[max(0, typePopup.indexOfSelectedItem)]
    let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let chart = SpreadsheetChartDefinition(
      title: title.isEmpty ? "Chart" : title,
      type: type,
      sourceRange: range,
      firstRowContainsHeaders: headerCheckbox.state == .on,
      firstColumnContainsLabels: type == .histogram
        ? false
        : xModeControl.selectedSegment == 1,
      seriesOrientation: .columns
    )
    onCreate?(chart)
  }

  @objc private func chartTypeChanged() {
    updateControlsForSelectedType()
  }

  private func updateControlsForSelectedType() {
    let types = SpreadsheetChartType.allCases
    guard typePopup.indexOfSelectedItem >= 0,
      typePopup.indexOfSelectedItem < types.count
    else {
      return
    }
    let isHistogram = types[typePopup.indexOfSelectedItem] == .histogram
    xModeControl.isEnabled = !isHistogram
    xModeControl.toolTip = isHistogram
      ? "Histograms use every numeric cell in the range."
      : nil
    if isHistogram { xModeControl.selectedSegment = 0 }
  }

  @objc private func openSavedChart() {
    let index = savedChartsPopup.indexOfSelectedItem
    guard index >= 0, index < document.charts.count else { return }
    onOpen?(document.charts[index])
  }
}
