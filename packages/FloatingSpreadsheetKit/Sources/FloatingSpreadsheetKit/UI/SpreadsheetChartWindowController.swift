import AppKit
import Charts
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class SpreadsheetChartWindowController: NSWindowController, NSWindowDelegate {
  let documentID: UUID
  var onReturnToSpreadsheet: (() -> Void)?
  var onClose: (() -> Void)?

  private let spreadsheetDocument: SpreadsheetDocument
  private let chartID: UUID
  private let panel: FloatingSpreadsheetPanel
  private let model: SpreadsheetChartViewModel
  private let chartHost: NSView
  private let toolbar = SpreadsheetChartToolbarView()
  private var statisticsPopover: NSPopover?
  private var documentObserver: NSObjectProtocol?
  private var didClose = false

  init(document: SpreadsheetDocument, chartID: UUID) {
    spreadsheetDocument = document
    self.chartID = chartID
    documentID = document.id
    panel = FloatingSpreadsheetPanel(size: NSSize(width: 560, height: 360))
    let viewModel = SpreadsheetChartViewModel(document: document, chartID: chartID)
    model = viewModel
    chartHost = NSHostingView(rootView: SpreadsheetChartView(model: viewModel))
    super.init(window: panel)
    configureWindow()
    configureContent()
    observeDocument()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    if let documentObserver {
      NotificationCenter.default.removeObserver(documentObserver)
    }
  }

  func presentCentered() {
    FloatingSpreadsheetWindowPlacement.center(
      panel,
      preferredSize: NSSize(width: 560, height: 360)
    )
    NSApp.activate(ignoringOtherApps: true)
    panel.orderFrontRegardless()
    panel.makeKey()
  }

  func bringToFront() {
    NSApp.activate(ignoringOtherApps: true)
    panel.orderFrontRegardless()
    panel.makeKey()
  }

  func closeWindow() {
    panel.close()
  }

  func windowDidBecomeKey(_ notification: Notification) {
    validateAlwaysOnTop()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.12
      panel.animator().alphaValue = 1
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    validateAlwaysOnTop()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      panel.animator().alphaValue = 0.82
    }
  }

  func windowWillClose(_ notification: Notification) {
    guard !didClose else { return }
    didClose = true
    onClose?()
  }

  private func configureWindow() {
    panel.delegate = self
    panel.minSize = FloatingSpreadsheetPanel.windowSize(
      forSurfaceSize: NSSize(width: 360, height: 250)
    )
    panel.contentMinSize = panel.minSize
  }

  private func configureContent() {
    let backdrop = panel.installRoundedContent()

    toolbar.translatesAutoresizingMaskIntoConstraints = false
    toolbar.onType = { [weak self] type in self?.changeType(type) }
    toolbar.onToggleFrozen = { [weak self] in self?.toggleFrozen() }
    toolbar.onOptions = { [weak self] in self?.showOptions() }
    toolbar.onStatistics = { [weak self] in self?.showHistogramStatistics() }
    toolbar.onCopyPNG = { [weak self] in self?.copyAsPNG() }
    toolbar.onSavePNG = { [weak self] in self?.saveAsPNG() }
    toolbar.onReturnToSource = { [weak self] in self?.onReturnToSpreadsheet?() }
    toolbar.onClose = { [weak self] in self?.closeWindow() }
    backdrop.addSubview(toolbar)

    chartHost.translatesAutoresizingMaskIntoConstraints = false
    backdrop.addSubview(chartHost)

    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
      toolbar.topAnchor.constraint(equalTo: backdrop.topAnchor),
      toolbar.heightAnchor.constraint(equalToConstant: 30),
      chartHost.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 6),
      chartHost.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -6),
      chartHost.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
      chartHost.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -6),
    ])
    refreshToolbar()
  }

  private func observeDocument() {
    documentObserver = NotificationCenter.default.addObserver(
      forName: .floatingSpreadsheetDidChange,
      object: spreadsheetDocument,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      if spreadsheetDocument.charts.contains(where: { $0.id == self.chartID }) {
        model.reload()
        refreshToolbar()
      } else {
        closeWindow()
      }
    }
  }

  private func changeType(_ type: SpreadsheetChartType) {
    guard var chart = spreadsheetDocument.charts.first(where: { $0.id == chartID }) else { return }
    chart.type = type
    if chart.isFrozen {
      chart.frozenSeries = spreadsheetDocument.chartSnapshotSeries(for: chart)
    }
    spreadsheetDocument.updateChart(chart, label: "Change chart type")
  }

  private func toggleFrozen() {
    guard let chart = spreadsheetDocument.charts.first(where: { $0.id == chartID }) else { return }
    spreadsheetDocument.setChartFrozen(id: chartID, frozen: !chart.isFrozen)
  }

  private func showOptions() {
    guard let chart = spreadsheetDocument.charts.first(where: { $0.id == chartID }) else { return }
    let xAxis = chart.effectiveXAxis
    let yAxis = chart.effectiveYAxis
    let xUsesDate = model.usesDateXAxis
    let xUsesTime = model.usesTimeXAxis
    let yUsesTime = model.usesTimeValueAxis
    let supportsXAxisDomain = chart.type != .pie
      && (chart.type == .scatter || model.usesNumericXAxis || xUsesDate || xUsesTime)
    let supportsYAxisDomain = chart.type != .pie

    let rangeField = NSTextField(string: chart.sourceRange.description)
    rangeField.placeholderString = "A1:D12"
    let titleField = NSTextField(string: chart.title)
    let headerCheckbox = NSButton(
      checkboxWithTitle: "First row contains headers",
      target: nil,
      action: nil
    )
    headerCheckbox.state = chart.firstRowContainsHeaders ? .on : .off
    let xModeControl = NSSegmentedControl(
      labels: ["Row index", "First column = X"],
      trackingMode: .selectOne,
      target: nil,
      action: nil
    )
    xModeControl.selectedSegment = chart.firstColumnContainsLabels ? 1 : 0
    xModeControl.setAccessibilityLabel("Horizontal axis source")
    let lastValueLabelsCheckbox = NSButton(
      checkboxWithTitle: "Label the last value of every series",
      target: nil,
      action: nil
    )
    lastValueLabelsCheckbox.state = chart.displaysLastValueLabels ? .on : .off
    if chart.type == .histogram {
      xModeControl.isEnabled = false
      xModeControl.selectedSegment = 0
      xModeControl.toolTip = "Histograms use every numeric cell in the range."
    }

    let xTitleField = NSTextField(string: xAxis.title)
    xTitleField.placeholderString = "Optional"
    let xMinimumField = NSTextField(
      string: axisBoundText(xAxis.minimum, isTime: xUsesTime, isDate: xUsesDate)
    )
    let xMaximumField = NSTextField(
      string: axisBoundText(xAxis.maximum, isTime: xUsesTime, isDate: xUsesDate)
    )
    let xScalePopup = axisScalePopup(selected: xAxis.scale)
    let xGridCheckbox = NSButton(
      checkboxWithTitle: "Grid lines",
      target: nil,
      action: nil
    )
    let xLabelsCheckbox = NSButton(
      checkboxWithTitle: "Labels",
      target: nil,
      action: nil
    )
    xGridCheckbox.state = xAxis.showsGridLines ? .on : .off
    xLabelsCheckbox.state = xAxis.showsLabels ? .on : .off

    let yTitleField = NSTextField(string: yAxis.title)
    yTitleField.placeholderString = "Optional"
    let yMinimumField = NSTextField(
      string: axisBoundText(yAxis.minimum, isTime: yUsesTime, isDate: false)
    )
    let yMaximumField = NSTextField(
      string: axisBoundText(yAxis.maximum, isTime: yUsesTime, isDate: false)
    )
    let yScalePopup = axisScalePopup(selected: yAxis.scale)
    let yGridCheckbox = NSButton(
      checkboxWithTitle: "Grid lines",
      target: nil,
      action: nil
    )
    let yLabelsCheckbox = NSButton(
      checkboxWithTitle: "Labels",
      target: nil,
      action: nil
    )
    yGridCheckbox.state = yAxis.showsGridLines ? .on : .off
    yLabelsCheckbox.state = yAxis.showsLabels ? .on : .off

    let referenceValueField = NSTextField(
      string: axisBoundText(
        chart.referenceLine?.value,
        isTime: yUsesTime,
        isDate: false
      )
    )
    referenceValueField.placeholderString = yUsesTime ? "None or HH:mm" : "None"
    let referenceLabelField = NSTextField(string: chart.referenceLine?.label ?? "")
    referenceLabelField.placeholderString = "Optional label"

    let automaticPlaceholder = xUsesDate
      ? "Automatic or YYYY-MM-DD"
      : (xUsesTime ? "Automatic or HH:mm" : "Automatic")
    xMinimumField.placeholderString = supportsXAxisDomain ? automaticPlaceholder : "Categorical axis"
    xMaximumField.placeholderString = supportsXAxisDomain ? automaticPlaceholder : "Categorical axis"
    xMinimumField.isEnabled = supportsXAxisDomain
    xMaximumField.isEnabled = supportsXAxisDomain
    xScalePopup.isEnabled = supportsXAxisDomain
      && !xUsesTime
      && !xUsesDate
      && chart.type != .histogram
    if !xScalePopup.isEnabled { xScalePopup.selectItem(at: 0) }

    let yAutomaticPlaceholder = yUsesTime ? "Automatic or HH:mm" : "Automatic"
    yMinimumField.placeholderString = supportsYAxisDomain ? yAutomaticPlaceholder : "No axis"
    yMaximumField.placeholderString = supportsYAxisDomain ? yAutomaticPlaceholder : "No axis"
    yMinimumField.isEnabled = supportsYAxisDomain
    yMaximumField.isEnabled = supportsYAxisDomain
    yScalePopup.isEnabled = supportsYAxisDomain && !yUsesTime
    if !yScalePopup.isEnabled { yScalePopup.selectItem(at: 0) }

    let axisControlsEnabled = chart.type != .pie
    for control in [xTitleField, xGridCheckbox, xLabelsCheckbox] {
      control.isEnabled = axisControlsEnabled
    }
    for control in [yTitleField, yGridCheckbox, yLabelsCheckbox] {
      control.isEnabled = axisControlsEnabled
    }
    referenceValueField.isEnabled = axisControlsEnabled
    referenceLabelField.isEnabled = axisControlsEnabled
    lastValueLabelsCheckbox.isEnabled = axisControlsEnabled && chart.type != .histogram

    let generalGrid = NSGridView(views: [
      [NSTextField(labelWithString: "Title"), titleField],
      [NSTextField(labelWithString: "Data range"), rangeField],
      [NSTextField(labelWithString: "X values"), xModeControl],
    ])
    configureOptionsGrid(generalGrid)

    let xGrid = NSGridView(views: [
      [NSTextField(labelWithString: "Title"), xTitleField],
      [NSTextField(labelWithString: "Minimum"), xMinimumField],
      [NSTextField(labelWithString: "Maximum"), xMaximumField],
      [NSTextField(labelWithString: "Scale"), xScalePopup],
    ])
    configureOptionsGrid(xGrid)
    let xChecks = NSStackView(views: [xGridCheckbox, xLabelsCheckbox])
    xChecks.orientation = .horizontal
    xChecks.spacing = 14

    let yGrid = NSGridView(views: [
      [NSTextField(labelWithString: "Title"), yTitleField],
      [NSTextField(labelWithString: "Minimum"), yMinimumField],
      [NSTextField(labelWithString: "Maximum"), yMaximumField],
      [NSTextField(labelWithString: "Scale"), yScalePopup],
    ])
    configureOptionsGrid(yGrid)
    let yChecks = NSStackView(views: [yGridCheckbox, yLabelsCheckbox])
    yChecks.orientation = .horizontal
    yChecks.spacing = 14

    let referenceGrid = NSGridView(views: [
      [NSTextField(labelWithString: "Value"), referenceValueField],
      [NSTextField(labelWithString: "Label"), referenceLabelField],
    ])
    configureOptionsGrid(referenceGrid)

    let xHeading = optionsHeading("X axis")
    let yHeading = optionsHeading("Y axis")
    let firstSeparator = NSBox()
    firstSeparator.boxType = .separator
    let secondSeparator = NSBox()
    secondSeparator.boxType = .separator
    let thirdSeparator = NSBox()
    thirdSeparator.boxType = .separator

    let stack = NSStackView(views: [
      generalGrid,
      headerCheckbox,
      lastValueLabelsCheckbox,
      firstSeparator,
      xHeading,
      xGrid,
      xChecks,
      secondSeparator,
      yHeading,
      yGrid,
      yChecks,
      thirdSeparator,
      optionsHeading("Reference line"),
      referenceGrid,
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    stack.frame = NSRect(x: 0, y: 0, width: 440, height: 500)
    for view in [
      generalGrid,
      firstSeparator,
      xGrid,
      secondSeparator,
      yGrid,
      thirdSeparator,
      referenceGrid,
    ] {
      view.widthAnchor.constraint(equalToConstant: 440).isActive = true
    }

    let alert = NSAlert()
    alert.messageText = "Chart settings"
    alert.accessoryView = stack
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "Delete chart")
    alert.beginSheetModal(for: panel) { [weak self] response in
      guard let self else { return }
      if response == .alertThirdButtonReturn {
        spreadsheetDocument.removeChart(id: chartID)
        return
      }
      guard response == .alertFirstButtonReturn,
        let range = CellRange(rangeField.stringValue)
      else {
        if response == .alertFirstButtonReturn {
          showChartSettingsError("Use a data range such as A1:D12.")
        }
        return
      }
      do {
        var changed = chart
        changed.title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if changed.title.isEmpty { changed.title = "Chart" }
        changed.sourceRange = range
        changed.firstRowContainsHeaders = headerCheckbox.state == .on
        changed.firstColumnContainsLabels = xModeControl.isEnabled
          && xModeControl.selectedSegment == 1
        changed.seriesOrientation = .columns
        if lastValueLabelsCheckbox.isEnabled {
          changed.showsLastValueLabels = lastValueLabelsCheckbox.state == .on
            ? true
            : nil
        }

        let changedXAxis = try chartAxisConfiguration(
          current: xAxis,
          titleField: xTitleField,
          minimumField: xMinimumField,
          maximumField: xMaximumField,
          scalePopup: xScalePopup,
          gridCheckbox: xGridCheckbox,
          labelsCheckbox: xLabelsCheckbox,
          supportsDomain: supportsXAxisDomain,
          isTime: xUsesTime,
          isDate: xUsesDate,
          axisName: "X"
        )
        let changedYAxis = try chartAxisConfiguration(
          current: yAxis,
          titleField: yTitleField,
          minimumField: yMinimumField,
          maximumField: yMaximumField,
          scalePopup: yScalePopup,
          gridCheckbox: yGridCheckbox,
          labelsCheckbox: yLabelsCheckbox,
          supportsDomain: supportsYAxisDomain,
          isTime: yUsesTime,
          isDate: false,
          axisName: "Y"
        )
        changed.xAxis = changedXAxis == .standard ? nil : changedXAxis
        changed.yAxis = changedYAxis == .standard ? nil : changedYAxis
        if referenceValueField.isEnabled {
          let referenceValue = try parseAxisBound(
            referenceValueField.stringValue,
            isTime: yUsesTime,
            isDate: false,
            name: "Reference line"
          )
          if changedYAxis.scale == .logarithmic,
            referenceValue.map({ $0 <= 0 }) == true
          {
            throw SpreadsheetChartSettingsError.nonPositiveLogarithmicBound("reference line")
          }
          changed.referenceLine = referenceValue.map {
            SpreadsheetChartReferenceLine(
              value: $0,
              label: referenceLabelField.stringValue.trimmingCharacters(
                in: .whitespacesAndNewlines
              )
            )
          }
        }
        if changed.isFrozen {
          changed.frozenSeries = spreadsheetDocument.chartSnapshotSeries(for: changed)
        }
        spreadsheetDocument.updateChart(changed, label: "Update chart settings")
      } catch {
        showChartSettingsError(error.localizedDescription)
      }
    }
  }

  private func configureOptionsGrid(_ grid: NSGridView) {
    grid.rowSpacing = 6
    grid.columnSpacing = 10
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .fill
  }

  private func optionsHeading(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    return label
  }

  private func axisScalePopup(selected: SpreadsheetChartAxisScale) -> NSPopUpButton {
    let popup = NSPopUpButton()
    popup.addItems(withTitles: ["Linear", "Logarithmic"])
    popup.selectItem(at: selected == .logarithmic ? 1 : 0)
    return popup
  }

  private func axisBoundText(_ value: Double?, isTime: Bool, isDate: Bool) -> String {
    guard let value else { return "" }
    if isDate {
      return SpreadsheetDate.format(Date(timeIntervalSince1970: value))
    }
    if isTime { return SpreadsheetTime.format(value) }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 10
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }

  private func chartAxisConfiguration(
    current: SpreadsheetChartAxisConfiguration,
    titleField: NSTextField,
    minimumField: NSTextField,
    maximumField: NSTextField,
    scalePopup: NSPopUpButton,
    gridCheckbox: NSButton,
    labelsCheckbox: NSButton,
    supportsDomain: Bool,
    isTime: Bool,
    isDate: Bool,
    axisName: String
  ) throws -> SpreadsheetChartAxisConfiguration {
    guard titleField.isEnabled else { return current }
    let minimum = supportsDomain
      ? try parseAxisBound(
        minimumField.stringValue,
        isTime: isTime,
        isDate: isDate,
        name: "\(axisName) minimum"
      )
      : current.minimum
    let maximum = supportsDomain
      ? try parseAxisBound(
        maximumField.stringValue,
        isTime: isTime,
        isDate: isDate,
        name: "\(axisName) maximum"
      )
      : current.maximum
    let scale: SpreadsheetChartAxisScale = scalePopup.isEnabled
      && scalePopup.indexOfSelectedItem == 1
      ? .logarithmic
      : .linear

    if let minimum, let maximum, minimum >= maximum {
      throw SpreadsheetChartSettingsError.invalidRange(axisName)
    }
    if scale == .logarithmic,
      (minimum.map { $0 <= 0 } == true || maximum.map { $0 <= 0 } == true)
    {
      throw SpreadsheetChartSettingsError.nonPositiveLogarithmicBound(axisName)
    }

    return SpreadsheetChartAxisConfiguration(
      title: titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
      minimum: minimum,
      maximum: maximum,
      scale: scale,
      showsGridLines: gridCheckbox.state == .on,
      showsLabels: labelsCheckbox.state == .on
    )
  }

  private func parseAxisBound(
    _ rawValue: String,
    isTime: Bool,
    isDate: Bool,
    name: String
  ) throws -> Double? {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    if isDate {
      guard let date = SpreadsheetDate.parse(value) else {
        throw SpreadsheetChartSettingsError.invalidBound(
          name,
          isTime: false,
          isDate: true
        )
      }
      return date.timeIntervalSince1970
    }
    if isTime, let time = SpreadsheetTime.parse(value) { return time }
    let normalized = value.replacingOccurrences(of: ",", with: ".")
    guard let number = Double(normalized), number.isFinite else {
      throw SpreadsheetChartSettingsError.invalidBound(name, isTime: isTime, isDate: false)
    }
    return number
  }

  private func showChartSettingsError(_ message: String) {
    NSSound.beep()
    let errorAlert = NSAlert()
    errorAlert.alertStyle = .warning
    errorAlert.messageText = "Invalid chart settings"
    errorAlert.informativeText = message
    errorAlert.beginSheetModal(for: panel)
  }

  private func refreshToolbar() {
    guard let chart = spreadsheetDocument.charts.first(where: { $0.id == chartID }) else { return }
    toolbar.update(type: chart.type, isFrozen: chart.isFrozen)
  }

  private func showHistogramStatistics() {
    guard model.histogramResult != nil else {
      NSSound.beep()
      return
    }
    statisticsPopover?.close()
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = true
    popover.contentSize = NSSize(width: 650, height: 380)
    popover.contentViewController = NSHostingController(
      rootView: SpreadsheetHistogramStatisticsView(model: model)
    )
    statisticsPopover = popover
    popover.show(
      relativeTo: toolbar.statisticsAnchor.bounds,
      of: toolbar.statisticsAnchor,
      preferredEdge: .minY
    )
  }

  private func copyAsPNG() {
    guard let data = SpreadsheetChartPNGExporter.pngData(for: chartHost) else {
      showExportError("The chart could not be rendered as a PNG image.")
      return
    }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setData(data, forType: .png) else {
      showExportError("The PNG image could not be copied to the clipboard.")
      return
    }
    toolbar.showCopySucceeded()
  }

  private func saveAsPNG() {
    let savePanel = NSSavePanel()
    savePanel.title = "Save chart as PNG"
    savePanel.nameFieldStringValue = suggestedPNGFilename()
    savePanel.allowedContentTypes = [.png]
    savePanel.canCreateDirectories = true
    savePanel.beginSheetModal(for: panel) { [weak self] response in
      guard response == .OK, let self, let url = savePanel.url else { return }
      guard let data = SpreadsheetChartPNGExporter.pngData(for: chartHost) else {
        showExportError("The chart could not be rendered as a PNG image.")
        return
      }
      do {
        try data.write(to: url, options: .atomic)
      } catch {
        showExportError("The PNG image could not be saved.", informativeText: error.localizedDescription)
      }
    }
  }

  private func suggestedPNGFilename() -> String {
    let title = spreadsheetDocument.charts.first(where: { $0.id == chartID })?.title ?? "Chart"
    let invalidCharacters = CharacterSet(charactersIn: "/:")
      .union(.newlines)
      .union(.controlCharacters)
    let components = title.components(separatedBy: invalidCharacters)
    let sanitized = components.joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(sanitized.isEmpty ? "Chart" : sanitized).png"
  }

  private func showExportError(_ message: String, informativeText: String = "") {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = message
    alert.informativeText = informativeText
    alert.beginSheetModal(for: panel)
  }

  private func validateAlwaysOnTop() {
    guard panel.level != .floating else { return }
    panel.close()
  }
}

private enum SpreadsheetChartSettingsError: LocalizedError {
  case invalidBound(String, isTime: Bool, isDate: Bool)
  case invalidRange(String)
  case nonPositiveLogarithmicBound(String)

  var errorDescription: String? {
    switch self {
    case .invalidBound(let name, let isTime, let isDate):
      if isDate { return "\(name) must be a date such as 2026-08-21." }
      return isTime
        ? "\(name) must be a number or a time such as 9:30."
        : "\(name) must be a number."
    case .invalidRange(let axis):
      return "The \(axis) axis minimum must be lower than its maximum."
    case .nonPositiveLogarithmicBound(let axis):
      return "The \(axis) axis bounds must be greater than zero for a logarithmic scale."
    }
  }
}

private final class SpreadsheetChartToolbarView: NSView {
  var onType: ((SpreadsheetChartType) -> Void)?
  var onToggleFrozen: (() -> Void)?
  var onOptions: (() -> Void)?
  var onStatistics: (() -> Void)?
  var onCopyPNG: (() -> Void)?
  var onSavePNG: (() -> Void)?
  var onReturnToSource: (() -> Void)?
  var onClose: (() -> Void)?

  private let typeButton = SpreadsheetChartToolbarView.button(
    symbol: "chart.xyaxis.line",
    tooltip: "Chart type"
  )
  private let freezeButton = SpreadsheetChartToolbarView.button(
    symbol: "snowflake",
    tooltip: "Freeze live data"
  )
  private let copyButton = SpreadsheetChartToolbarView.button(
    symbol: "doc.on.doc",
    tooltip: "Copy chart as PNG"
  )
  private let statisticsButton = SpreadsheetChartToolbarView.button(
    symbol: "tablecells",
    tooltip: "Histogram statistics"
  )

  var statisticsAnchor: NSView { statisticsButton }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.7).cgColor

    let source = Self.button(symbol: "arrowshape.turn.up.left", tooltip: "Return to spreadsheet")
    let options = Self.button(symbol: "gearshape", tooltip: "Chart settings")
    let save = Self.button(symbol: "square.and.arrow.down", tooltip: "Save chart as PNG")
    let close = Self.button(symbol: "xmark", tooltip: "Close chart")
    source.target = self
    source.action = #selector(returnToSource)
    options.target = self
    options.action = #selector(showOptions)
    save.target = self
    save.action = #selector(savePNG)
    close.target = self
    close.action = #selector(closeWindow)
    typeButton.target = self
    typeButton.action = #selector(showTypes)
    freezeButton.target = self
    freezeButton.action = #selector(toggleFrozen)
    copyButton.target = self
    copyButton.action = #selector(copyPNG)
    statisticsButton.target = self
    statisticsButton.action = #selector(showStatistics)

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let stack = NSStackView(
      views: [
        close,
        spacer,
        source,
        typeButton,
        freezeButton,
        statisticsButton,
        copyButton,
        save,
        options,
      ]
    )
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }

  func update(type: SpreadsheetChartType, isFrozen: Bool) {
    typeButton.image = NSImage(
      systemSymbolName: Self.symbol(for: type),
      accessibilityDescription: "Chart type: \(type.rawValue)"
    )
    freezeButton.image = NSImage(
      systemSymbolName: isFrozen ? "snowflake.circle.fill" : "snowflake",
      accessibilityDescription: isFrozen ? "Unfreeze data" : "Freeze live data"
    )
    freezeButton.contentTintColor = isFrozen ? .controlAccentColor : .secondaryLabelColor
    statisticsButton.isHidden = type != .histogram
  }

  func showCopySucceeded() {
    copyButton.image = NSImage(
      systemSymbolName: "checkmark",
      accessibilityDescription: "Chart copied as PNG"
    )
    copyButton.contentTintColor = .systemGreen
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
      guard let self else { return }
      copyButton.image = NSImage(
        systemSymbolName: "doc.on.doc",
        accessibilityDescription: "Copy chart as PNG"
      )
      copyButton.contentTintColor = .secondaryLabelColor
    }
  }

  @objc private func showTypes() {
    let menu = NSMenu()
    for type in SpreadsheetChartType.allCases {
      let item = NSMenuItem(
        title: type.rawValue.capitalized,
        action: #selector(selectType(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = type.rawValue
      item.image = NSImage(systemSymbolName: Self.symbol(for: type), accessibilityDescription: nil)
      menu.addItem(item)
    }
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: 0, y: typeButton.bounds.maxY + 2),
      in: typeButton
    )
  }

  @objc private func selectType(_ sender: NSMenuItem) {
    guard let rawValue = sender.representedObject as? String,
      let type = SpreadsheetChartType(rawValue: rawValue)
    else {
      return
    }
    onType?(type)
  }

  @objc private func toggleFrozen() { onToggleFrozen?() }
  @objc private func showOptions() { onOptions?() }
  @objc private func showStatistics() { onStatistics?() }
  @objc private func copyPNG() { onCopyPNG?() }
  @objc private func savePNG() { onSavePNG?() }
  @objc private func returnToSource() { onReturnToSource?() }
  @objc private func closeWindow() { onClose?() }

  private static func button(symbol: String, tooltip: String) -> NSButton {
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
      ?? NSImage(size: NSSize(width: 14, height: 14))
    let button = NSButton(image: image, target: nil, action: nil)
    button.isBordered = false
    button.bezelStyle = .accessoryBarAction
    button.imagePosition = .imageOnly
    button.toolTip = tooltip
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 26),
      button.heightAnchor.constraint(equalToConstant: 26),
    ])
    return button
  }

  private static func symbol(for type: SpreadsheetChartType) -> String {
    switch type {
    case .line: return "chart.xyaxis.line"
    case .bar: return "chart.bar"
    case .area: return "chart.line.uptrend.xyaxis"
    case .scatter: return "chart.dots.scatter"
    case .pie: return "chart.pie"
    case .histogram: return "chart.bar.xaxis"
    }
  }
}

private struct SpreadsheetChartDatum: Identifiable {
  var id: String
  var series: String
  var category: String
  var x: Double
  var xDate: Date?
  var xIsNumeric: Bool
  var value: Double
  var xIsTime: Bool
  var valueIsTime: Bool
  var histogramLowerBound: Double?
  var histogramUpperBound: Double?
}

private struct SpreadsheetChartHoverSelection: Identifiable {
  var id: String
  var points: [SpreadsheetChartDatum]

  var anchor: SpreadsheetChartDatum? { points.first }
}

private final class SpreadsheetChartViewModel: ObservableObject {
  @Published private(set) var chart: SpreadsheetChartDefinition?
  @Published private(set) var data: [SpreadsheetChartDatum] = []
  @Published private(set) var histogramResult: SpreadsheetHistogramResult? = nil

  private let document: SpreadsheetDocument
  private let chartID: UUID

  var usesTimeXAxis: Bool {
    !data.isEmpty && data.allSatisfy(\.xIsTime)
  }

  var usesDateXAxis: Bool {
    !data.isEmpty && data.allSatisfy { $0.xDate != nil }
  }

  var usesNumericXAxis: Bool {
    !data.isEmpty && data.allSatisfy(\.xIsNumeric)
  }

  var usesTimeValueAxis: Bool {
    !data.isEmpty && data.allSatisfy(\.valueIsTime)
  }

  init(document: SpreadsheetDocument, chartID: UUID) {
    self.document = document
    self.chartID = chartID
    reload()
  }

  func reload() {
    guard let chart = document.charts.first(where: { $0.id == chartID }) else {
      self.chart = nil
      data = []
      histogramResult = nil
      return
    }
    self.chart = chart
    if chart.type == .histogram {
      let result = SpreadsheetHistogramCalculator.calculate(
        samples: document.histogramSamples(for: chart)
      )
      histogramResult = result
      data = result?.bins.map { bin in
        SpreadsheetChartDatum(
          id: "histogram-\(bin.index)",
          series: "Frequency",
          category: histogramBinLabel(bin, isDuration: result?.isDuration == true),
          x: bin.midpoint,
          xDate: nil,
          xIsNumeric: true,
          value: Double(bin.count),
          xIsTime: result?.isDuration == true,
          valueIsTime: false,
          histogramLowerBound: bin.lowerBound,
          histogramUpperBound: bin.upperBound
        )
      } ?? []
      return
    }
    histogramResult = nil
    data = document.chartSeries(for: chart).flatMap { series in
      series.points.enumerated().map { index, point in
        SpreadsheetChartDatum(
          id: "\(series.name)-\(index)-\(point.category)",
          series: series.name,
          category: point.category,
          x: point.x ?? Double(index),
          xDate: point.xDate,
          xIsNumeric: point.x != nil,
          value: point.value,
          xIsTime: point.xIsTime == true,
          valueIsTime: point.valueIsTime == true,
          histogramLowerBound: nil,
          histogramUpperBound: nil
        )
      }
    }
  }

  func plottableData(for definition: SpreadsheetChartDefinition) -> [SpreadsheetChartDatum] {
    let hasNumericXAxis = definition.type == .scatter || usesNumericXAxis || usesTimeXAxis
    let xScale = definition.type == .histogram
      ? SpreadsheetChartAxisScale.linear
      : definition.effectiveXAxis.scale
    let yScale = definition.effectiveYAxis.scale
    var result = data.filter { datum in
      let hasValidX = definition.type == .pie
        || usesDateXAxis
        || !hasNumericXAxis
        || xScale == .linear
        || datum.x > 0
      let hasValidY = definition.type == .pie
        || yScale == .linear
        || datum.value > 0
      return hasValidX && hasValidY
    }
    if usesDateXAxis {
      result.sort {
        if $0.xDate == $1.xDate { return $0.series < $1.series }
        return ($0.xDate ?? .distantPast) < ($1.xDate ?? .distantPast)
      }
    }
    return result
  }

  func lastDataBySeries(for definition: SpreadsheetChartDefinition) -> [SpreadsheetChartDatum] {
    guard definition.type != .histogram else { return [] }
    var result: [String: SpreadsheetChartDatum] = [:]
    for datum in plottableData(for: definition) {
      guard let current = result[datum.series] else {
        result[datum.series] = datum
        continue
      }
      if usesDateXAxis {
        if (datum.xDate ?? .distantPast) >= (current.xDate ?? .distantPast) {
          result[datum.series] = datum
        }
      } else if usesNumericXAxis || definition.type == .scatter {
        if datum.x >= current.x { result[datum.series] = datum }
      } else {
        result[datum.series] = datum
      }
    }
    return result.values.sorted { $0.series.localizedCaseInsensitiveCompare($1.series) == .orderedAscending }
  }

  func hoverSelection(
    for definition: SpreadsheetChartDefinition,
    nearest date: Date
  ) -> SpreadsheetChartHoverSelection? {
    let data = plottableData(for: definition)
    guard let closest = data.min(by: {
      abs(($0.xDate ?? .distantPast).timeIntervalSince(date))
        < abs(($1.xDate ?? .distantPast).timeIntervalSince(date))
    }), let selectedDate = closest.xDate
    else {
      return nil
    }
    return makeHoverSelection(
      id: "date-\(selectedDate.timeIntervalSince1970)",
      points: data.filter { $0.xDate == selectedDate }
    )
  }

  func hoverSelection(
    for definition: SpreadsheetChartDefinition,
    nearest x: Double
  ) -> SpreadsheetChartHoverSelection? {
    let data = plottableData(for: definition)
    guard let closest = data.min(by: { abs($0.x - x) < abs($1.x - x) }) else {
      return nil
    }
    let tolerance = max(1e-9, abs(closest.x) * 1e-9)
    return makeHoverSelection(
      id: "number-\(closest.x)",
      points: data.filter { abs($0.x - closest.x) <= tolerance }
    )
  }

  func hoverSelection(
    for definition: SpreadsheetChartDefinition,
    category: String
  ) -> SpreadsheetChartHoverSelection? {
    makeHoverSelection(
      id: "category-\(category)",
      points: plottableData(for: definition).filter { $0.category == category }
    )
  }

  private func makeHoverSelection(
    id: String,
    points: [SpreadsheetChartDatum]
  ) -> SpreadsheetChartHoverSelection? {
    guard !points.isEmpty else { return nil }
    return SpreadsheetChartHoverSelection(
      id: id,
      points: points.sorted {
        $0.series.localizedCaseInsensitiveCompare($1.series) == .orderedAscending
      }
    )
  }

  func xDomain(for definition: SpreadsheetChartDefinition) -> ClosedRange<Double>? {
    guard definition.type != .pie,
      !usesDateXAxis,
      definition.type == .scatter || usesNumericXAxis || usesTimeXAxis
    else {
      return nil
    }
    return axisDomain(
      values: definition.type == .histogram
        ? plottableData(for: definition).flatMap {
          [$0.histogramLowerBound ?? $0.x, $0.histogramUpperBound ?? $0.x]
        }
        : plottableData(for: definition).map(\.x),
      configuration: definition.effectiveXAxis
    )
  }

  func xDateDomain(for definition: SpreadsheetChartDefinition) -> ClosedRange<Date>? {
    guard definition.type != .pie, usesDateXAxis else { return nil }
    let configuration = definition.effectiveXAxis
    guard configuration.minimum != nil || configuration.maximum != nil else { return nil }
    let dates = plottableData(for: definition).compactMap(\.xDate)
    var lower = configuration.minimum.map { Date(timeIntervalSince1970: $0) }
      ?? dates.min()
      ?? Date(timeIntervalSince1970: 0)
    var upper = configuration.maximum.map { Date(timeIntervalSince1970: $0) }
      ?? dates.max()
      ?? lower.addingTimeInterval(86_400)
    if lower >= upper {
      if configuration.minimum != nil, configuration.maximum == nil {
        upper = lower.addingTimeInterval(86_400)
      } else {
        lower = upper.addingTimeInterval(-86_400)
      }
    }
    return lower...upper
  }

  func formattedDate(_ date: Date) -> String {
    SpreadsheetDate.format(date, locale: document.settings.displayLocale.locale)
  }

  func formattedValue(_ value: Double, isTime: Bool) -> String {
    if isTime { return SpreadsheetTime.format(value) }
    let formatter = NumberFormatter()
    formatter.locale = document.settings.displayLocale.locale
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 6
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }

  func formattedXAxisValue(_ value: Double) -> String {
    if chart?.type == .histogram, histogramResult?.isDuration == true {
      return formattedDuration(value)
    }
    if usesTimeXAxis { return SpreadsheetTime.format(value) }
    return formattedValue(value, isTime: false)
  }

  func histogramStatisticsText(_ result: SpreadsheetHistogramResult) -> String {
    let format: (Double) -> String = { [weak self] value in
      guard let self else { return String(value) }
      return result.isDuration
        ? self.formattedDuration(value)
        : self.formattedValue(value, isTime: false)
    }
    let percentage: (Double) -> String = { value in
      String(format: "%.1f%%", value * 100)
    }
    var lines = [
      "Method\t\(result.method.rawValue)",
      "Samples\t\(result.sampleCount)",
      "Bin width\t\(format(result.binWidth))",
      "Minimum\t\(format(result.minimum))",
      "Maximum\t\(format(result.maximum))",
      "Mean\t\(format(result.mean))",
      "Median\t\(format(result.median))",
      "Standard deviation\t\(format(result.standardDeviation))",
      "",
      "Bin\tn\t%\tCumulative %\tMean\tMedian\tStd. dev.\tObserved min\tObserved max",
    ]
    lines.append(contentsOf: result.bins.map { bin in
      [
        histogramBinLabel(bin, isDuration: result.isDuration),
        String(bin.count),
        percentage(bin.percentage),
        percentage(bin.cumulativePercentage),
        bin.mean.map(format) ?? "—",
        bin.median.map(format) ?? "—",
        bin.standardDeviation.map(format) ?? "—",
        bin.minimum.map(format) ?? "—",
        bin.maximum.map(format) ?? "—",
      ].joined(separator: "\t")
    })
    return lines.joined(separator: "\n")
  }

  func formattedHistogramValue(_ value: Double, isDuration: Bool) -> String {
    isDuration
      ? formattedDuration(value)
      : formattedValue(value, isTime: false)
  }

  func formattedHistogramPercentage(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
  }

  func yDomain(for definition: SpreadsheetChartDefinition) -> ClosedRange<Double>? {
    guard definition.type != .pie else { return nil }
    return axisDomain(
      values: plottableData(for: definition).map(\.value),
      configuration: definition.effectiveYAxis
    )
  }

  private func axisDomain(
    values: [Double],
    configuration: SpreadsheetChartAxisConfiguration
  ) -> ClosedRange<Double>? {
    guard configuration.scale == .logarithmic
      || configuration.minimum != nil
      || configuration.maximum != nil
    else {
      return nil
    }

    let validValues = values.filter {
      $0.isFinite && (configuration.scale == .linear || $0 > 0)
    }
    let fallbackMinimum = configuration.scale == .logarithmic ? 1.0 : 0.0
    let fallbackMaximum = configuration.scale == .logarithmic ? 10.0 : 1.0
    var lower = configuration.minimum ?? validValues.min() ?? fallbackMinimum
    var upper = configuration.maximum ?? validValues.max() ?? fallbackMaximum

    if configuration.scale == .logarithmic {
      lower = max(lower, Double.leastNormalMagnitude)
      upper = max(upper, Double.leastNormalMagnitude)
    }
    if lower >= upper {
      if configuration.minimum != nil, configuration.maximum == nil {
        upper = configuration.scale == .logarithmic
          ? lower * 10
          : lower + max(abs(lower) * 0.1, 1)
      } else if configuration.minimum == nil, configuration.maximum != nil {
        lower = configuration.scale == .logarithmic
          ? max(Double.leastNormalMagnitude, upper / 10)
          : upper - max(abs(upper) * 0.1, 1)
      } else if configuration.scale == .logarithmic {
        lower = max(Double.leastNormalMagnitude, lower / 10)
        upper *= 10
      } else {
        let padding = max(abs(lower) * 0.1, 1)
        lower -= padding
        upper += padding
      }
    }
    return lower...upper
  }

  func histogramBinLabel(
    _ bin: SpreadsheetHistogramBin,
    isDuration: Bool
  ) -> String {
    let lower = isDuration
      ? formattedDuration(bin.lowerBound)
      : formattedValue(bin.lowerBound, isTime: false)
    let upper = isDuration
      ? formattedDuration(bin.upperBound)
      : formattedValue(bin.upperBound, isTime: false)
    return "[\(lower), \(upper)\(bin.includesUpperBound ? "]" : ")")"
  }

  private func formattedDuration(_ fractionOfDay: Double) -> String {
    guard fractionOfDay.isFinite else { return "" }
    let totalSeconds = Int((fractionOfDay * 86_400).rounded())
    let sign = totalSeconds < 0 ? "−" : ""
    let absoluteSeconds = abs(totalSeconds)
    let hours = absoluteSeconds / 3_600
    let minutes = (absoluteSeconds / 60) % 60
    let seconds = absoluteSeconds % 60
    if seconds == 0 {
      return String(format: "%@%d:%02d", sign, hours, minutes)
    }
    return String(format: "%@%d:%02d:%02d", sign, hours, minutes, seconds)
  }
}

private struct SpreadsheetHistogramStatisticsView: View {
  @ObservedObject var model: SpreadsheetChartViewModel

  var body: some View {
    if let result = model.histogramResult {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Image(systemName: "chart.bar.xaxis")
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 1) {
            Text("Histogram statistics")
              .font(.system(size: 13, weight: .semibold))
            Text("\(result.method.rawValue) bins · readable boundaries")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
              model.histogramStatisticsText(result),
              forType: .string
            )
          } label: {
            Label("Copy", systemImage: "doc.on.doc")
          }
          .controlSize(.small)
        }

        HStack(spacing: 6) {
          summaryValue("Samples", String(result.sampleCount))
          summaryValue(
            "Bin width",
            model.formattedHistogramValue(result.binWidth, isDuration: result.isDuration)
          )
          summaryValue(
            "Mean",
            model.formattedHistogramValue(result.mean, isDuration: result.isDuration)
          )
          summaryValue(
            "Median",
            model.formattedHistogramValue(result.median, isDuration: result.isDuration)
          )
          summaryValue(
            "Std. dev.",
            model.formattedHistogramValue(
              result.standardDeviation,
              isDuration: result.isDuration
            )
          )
        }

        Divider()
        histogramHeader
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(result.bins) { bin in
              histogramRow(bin, result: result)
            }
          }
        }
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(Color.secondary.opacity(0.16), lineWidth: 0.5)
        }
      }
      .padding(13)
      .frame(width: 650, height: 380)
    } else {
      ContentUnavailableView("No histogram data", systemImage: "chart.bar.xaxis")
        .frame(width: 650, height: 380)
    }
  }

  private func summaryValue(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title.uppercased())
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.045))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }

  private var histogramHeader: some View {
    HStack(spacing: 6) {
      columnHeader("BIN", width: 176, alignment: .leading)
      columnHeader("N", width: 34)
      columnHeader("%", width: 46)
      columnHeader("CUM.", width: 54)
      columnHeader("MEAN", width: 78)
      columnHeader("MEDIAN", width: 78)
      columnHeader("STD. DEV.", width: 82)
    }
    .padding(.horizontal, 7)
  }

  private func histogramRow(
    _ bin: SpreadsheetHistogramBin,
    result: SpreadsheetHistogramResult
  ) -> some View {
    HStack(spacing: 6) {
      tableValue(
        model.histogramBinLabel(bin, isDuration: result.isDuration),
        width: 176,
        alignment: .leading
      )
      tableValue(String(bin.count), width: 34)
      tableValue(model.formattedHistogramPercentage(bin.percentage), width: 46)
      tableValue(model.formattedHistogramPercentage(bin.cumulativePercentage), width: 54)
      tableValue(
        bin.mean.map {
          model.formattedHistogramValue($0, isDuration: result.isDuration)
        } ?? "—",
        width: 78
      )
      tableValue(
        bin.median.map {
          model.formattedHistogramValue($0, isDuration: result.isDuration)
        } ?? "—",
        width: 78
      )
      tableValue(
        bin.standardDeviation.map {
          model.formattedHistogramValue($0, isDuration: result.isDuration)
        } ?? "—",
        width: 82
      )
    }
    .padding(.horizontal, 7)
    .frame(height: 24)
    .background(bin.index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
  }

  private func columnHeader(
    _ value: String,
    width: CGFloat,
    alignment: Alignment = .trailing
  ) -> some View {
    Text(value)
      .font(.system(size: 8, weight: .semibold))
      .foregroundStyle(.secondary)
      .frame(width: width, alignment: alignment)
  }

  private func tableValue(
    _ value: String,
    width: CGFloat,
    alignment: Alignment = .trailing
  ) -> some View {
    Text(value)
      .font(.system(size: 10, design: .monospaced))
      .monospacedDigit()
      .lineLimit(1)
      .truncationMode(.middle)
      .frame(width: width, alignment: alignment)
      .help(value)
  }
}

private struct SpreadsheetChartView: View {
  @ObservedObject var model: SpreadsheetChartViewModel
  @State private var hoverSelection: SpreadsheetChartHoverSelection? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if let chart = model.chart {
        Text(chart.title)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
          .padding(.horizontal, 6)
        if model.data.isEmpty {
          ContentUnavailableView(
            "No numeric data",
            systemImage: "chart.xyaxis.line",
            description: Text("Change the source range or enter numbers in the spreadsheet.")
          )
        } else if model.plottableData(for: chart).isEmpty {
          ContentUnavailableView(
            "No plottable data",
            systemImage: "chart.xyaxis.line",
            description: Text("Logarithmic axes require values greater than zero.")
          )
        } else {
          chartContent(chart)
            .chartLegend(position: .bottom, alignment: .center, spacing: 8)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
      } else {
        ContentUnavailableView("Chart unavailable", systemImage: "chart.xyaxis.line")
      }
    }
    .background(Color.clear)
  }

  @ViewBuilder
  private func chartContent(_ definition: SpreadsheetChartDefinition) -> some View {
    let xAxis = definition.effectiveXAxis
    let yAxis = definition.effectiveYAxis
    Chart {
      ForEach(model.plottableData(for: definition)) { datum in
        switch definition.type {
      case .line:
        if model.usesDateXAxis {
          LineMark(
            x: .value("Date", datum.xDate ?? .distantPast),
            y: .value("Value", datum.value)
          )
          .foregroundStyle(by: .value("Series", datum.series))
          .symbol(by: .value("Series", datum.series))
        } else if model.usesNumericXAxis {
          LineMark(
            x: .value(model.usesTimeXAxis ? "Time" : "X", datum.x),
            y: .value("Value", datum.value)
          )
          .foregroundStyle(by: .value("Series", datum.series))
          .symbol(by: .value("Series", datum.series))
        } else {
          LineMark(
            x: .value("Category", datum.category),
            y: .value("Value", datum.value)
          )
          .foregroundStyle(by: .value("Series", datum.series))
          .symbol(by: .value("Series", datum.series))
        }
      case .bar:
        if model.usesDateXAxis {
          BarMark(
            x: .value("Date", datum.xDate ?? .distantPast),
            y: .value("Value", datum.value)
          )
          .foregroundStyle(by: .value("Series", datum.series))
        } else if model.usesNumericXAxis {
          BarMark(
            x: .value(model.usesTimeXAxis ? "Time" : "X", datum.x),
            y: .value("Value", datum.value)
          )
          .foregroundStyle(by: .value("Series", datum.series))
        } else {
          BarMark(
            x: .value("Category", datum.category),
            y: .value("Value", datum.value)
          )
          .foregroundStyle(by: .value("Series", datum.series))
        }
      case .area:
        if model.usesDateXAxis {
          AreaMark(
            x: .value("Date", datum.xDate ?? .distantPast),
            y: .value("Value", datum.value)
          )
          .foregroundStyle(by: .value("Series", datum.series))
          .opacity(0.55)
        } else if model.usesNumericXAxis {
          AreaMark(
            x: .value(model.usesTimeXAxis ? "Time" : "X", datum.x),
            y: .value("Value", datum.value)
          )
          .foregroundStyle(by: .value("Series", datum.series))
          .opacity(0.55)
        } else {
          AreaMark(
            x: .value("Category", datum.category),
            y: .value("Value", datum.value)
          )
          .foregroundStyle(by: .value("Series", datum.series))
          .opacity(0.55)
        }
      case .scatter:
        if model.usesDateXAxis {
          PointMark(
            x: .value("Date", datum.xDate ?? .distantPast),
            y: .value("Value", datum.value)
          )
          .foregroundStyle(by: .value("Series", datum.series))
          .symbolSize(42)
        } else {
          PointMark(
            x: .value("X", datum.x),
            y: .value("Value", datum.value)
          )
          .foregroundStyle(by: .value("Series", datum.series))
          .symbolSize(42)
        }
      case .pie:
          SectorMark(
            angle: .value("Value", abs(datum.value)),
            innerRadius: .ratio(0.48),
            angularInset: 1.2
          )
          .foregroundStyle(by: .value("Category", datum.category))
      case .histogram:
        if let lowerBound = datum.histogramLowerBound,
          let upperBound = datum.histogramUpperBound
        {
          BarMark(
            xStart: .value("Lower bound", lowerBound),
            xEnd: .value("Upper bound", upperBound),
            y: .value("Count", datum.value)
          )
          .foregroundStyle(Color.accentColor.gradient)
        }
        }
      }
      if definition.type != .pie, let referenceLine = definition.referenceLine {
        RuleMark(y: .value("Reference", referenceLine.value))
          .foregroundStyle(Color.orange)
          .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [6, 4]))
          .annotation(position: .top, alignment: .trailing) {
            Text(
              referenceLine.label.isEmpty
                ? model.formattedValue(
                  referenceLine.value,
                  isTime: model.usesTimeValueAxis
                )
                : referenceLine.label
            )
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
          }
      }
      if definition.type != .pie, definition.displaysLastValueLabels {
        ForEach(model.lastDataBySeries(for: definition)) { datum in
          if model.usesDateXAxis {
            PointMark(
              x: .value("Date", datum.xDate ?? .distantPast),
              y: .value("Last value", datum.value)
            )
            .foregroundStyle(by: .value("Series", datum.series))
            .symbolSize(30)
            .annotation(position: .top, spacing: 3) {
              lastValueLabel(datum)
            }
          } else if model.usesNumericXAxis || definition.type == .scatter {
            PointMark(
              x: .value("X", datum.x),
              y: .value("Last value", datum.value)
            )
            .foregroundStyle(by: .value("Series", datum.series))
            .symbolSize(30)
            .annotation(position: .top, spacing: 3) {
              lastValueLabel(datum)
            }
          } else {
            PointMark(
              x: .value("Category", datum.category),
              y: .value("Last value", datum.value)
            )
            .foregroundStyle(by: .value("Series", datum.series))
            .symbolSize(30)
            .annotation(position: .top, spacing: 3) {
              lastValueLabel(datum)
            }
          }
        }
      }
      if definition.type != .pie,
        let selection = hoverSelection,
        let anchor = selection.anchor
      {
        if model.usesDateXAxis {
          RuleMark(x: .value("Hovered date", anchor.xDate ?? .distantPast))
            .foregroundStyle(Color.secondary.opacity(0.65))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .annotation(position: .top, spacing: 5) {
              hoverCard(selection)
            }
        } else if model.usesNumericXAxis || definition.type == .scatter {
          RuleMark(x: .value("Hovered X", anchor.x))
            .foregroundStyle(Color.secondary.opacity(0.65))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .annotation(position: .top, spacing: 5) {
              hoverCard(selection)
            }
        } else {
          RuleMark(x: .value("Hovered category", anchor.category))
            .foregroundStyle(Color.secondary.opacity(0.65))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .annotation(position: .top, spacing: 5) {
              hoverCard(selection)
            }
        }

        ForEach(selection.points) { datum in
          if model.usesDateXAxis {
            PointMark(
              x: .value("Hovered date", datum.xDate ?? .distantPast),
              y: .value("Hovered value", datum.value)
            )
            .foregroundStyle(by: .value("Series", datum.series))
            .symbolSize(52)
          } else if model.usesNumericXAxis || definition.type == .scatter {
            PointMark(
              x: .value("Hovered X", datum.x),
              y: .value("Hovered value", datum.value)
            )
            .foregroundStyle(by: .value("Series", datum.series))
            .symbolSize(52)
          } else {
            PointMark(
              x: .value("Hovered category", datum.category),
              y: .value("Hovered value", datum.value)
            )
            .foregroundStyle(by: .value("Series", datum.series))
            .symbolSize(52)
          }
        }
      }
    }
    .modifier(
      SpreadsheetChartScaleModifier(
        xDomain: model.xDomain(for: definition),
        xDateDomain: model.xDateDomain(for: definition),
        yDomain: model.yDomain(for: definition),
        xScale: definition.type == .histogram ? .linear : xAxis.scale,
        yScale: yAxis.scale
      )
    )
    .chartXAxis {
      if definition.type != .pie {
        if model.usesDateXAxis {
          AxisMarks(values: .automatic(desiredCount: 6)) { value in
            if xAxis.showsGridLines { AxisGridLine() }
            AxisTick()
            if xAxis.showsLabels {
              AxisValueLabel {
                if let date = value.as(Date.self) {
                  Text(model.formattedDate(date))
                }
              }
            }
          }
        } else if model.usesTimeXAxis {
          AxisMarks(values: .automatic(desiredCount: 6)) { value in
            if xAxis.showsGridLines { AxisGridLine() }
            AxisTick()
            if xAxis.showsLabels {
              AxisValueLabel {
                if let time = value.as(Double.self) {
                  Text(model.formattedXAxisValue(time))
                }
              }
            }
          }
        } else if definition.type == .histogram {
          AxisMarks(values: .automatic(desiredCount: 6)) { value in
            if xAxis.showsGridLines { AxisGridLine() }
            AxisTick()
            if xAxis.showsLabels {
              AxisValueLabel {
                if let number = value.as(Double.self) {
                  Text(model.formattedXAxisValue(number))
                }
              }
            }
          }
        } else {
          AxisMarks(values: .automatic(desiredCount: 6)) { _ in
            if xAxis.showsGridLines { AxisGridLine() }
            AxisTick()
            if xAxis.showsLabels { AxisValueLabel() }
          }
        }
      }
    }
    .chartYAxis {
      if definition.type != .pie {
        if definition.type == .histogram {
          AxisMarks(values: .automatic(desiredCount: 6)) { value in
            if yAxis.showsGridLines { AxisGridLine() }
            AxisTick()
            if yAxis.showsLabels {
              AxisValueLabel {
                if let count = value.as(Double.self) {
                  Text(String(Int(count.rounded())))
                }
              }
            }
          }
        } else if model.usesTimeValueAxis {
          AxisMarks(values: .automatic(desiredCount: 6)) { value in
            if yAxis.showsGridLines { AxisGridLine() }
            AxisTick()
            if yAxis.showsLabels {
              AxisValueLabel {
                if let time = value.as(Double.self) {
                  Text(SpreadsheetTime.format(time))
                }
              }
            }
          }
        } else {
          AxisMarks(values: .automatic(desiredCount: 6)) { _ in
            if yAxis.showsGridLines { AxisGridLine() }
            AxisTick()
            if yAxis.showsLabels { AxisValueLabel() }
          }
        }
      }
    }
    .chartXAxisLabel(definition.type == .pie ? "" : xAxis.title)
    .chartYAxisLabel(definition.type == .pie ? "" : yAxis.title)
    .chartOverlay { proxy in
      GeometryReader { geometry in
        if definition.type != .pie {
          Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
              switch phase {
              case .active(let location):
                guard let plotFrame = proxy.plotFrame else {
                  hoverSelection = nil
                  return
                }
                let frame = geometry[plotFrame]
                guard frame.contains(location) else {
                  hoverSelection = nil
                  return
                }
                let xPosition = location.x - frame.minX
                if model.usesDateXAxis {
                  let date: Date? = proxy.value(atX: xPosition)
                  hoverSelection = date.flatMap {
                    model.hoverSelection(for: definition, nearest: $0)
                  }
                } else if model.usesNumericXAxis || definition.type == .scatter {
                  let x: Double? = proxy.value(atX: xPosition)
                  hoverSelection = x.flatMap {
                    model.hoverSelection(for: definition, nearest: $0)
                  }
                } else {
                  let category: String? = proxy.value(atX: xPosition)
                  hoverSelection = category.flatMap {
                    model.hoverSelection(for: definition, category: $0)
                  }
                }
              case .ended:
                hoverSelection = nil
              }
            }
        }
      }
    }
  }

  private func hoverCard(_ selection: SpreadsheetChartHoverSelection) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(hoverTitle(selection))
        .font(.system(size: 10, weight: .semibold))
      ForEach(selection.points.prefix(8)) { datum in
        HStack(spacing: 8) {
          Text(datum.series)
            .foregroundStyle(.secondary)
          Spacer(minLength: 8)
          Text(model.formattedValue(datum.value, isTime: model.usesTimeValueAxis))
            .monospacedDigit()
        }
        .font(.system(size: 10))
      }
      if selection.points.count > 8 {
        Text("+\(selection.points.count - 8) more")
          .font(.system(size: 9))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 5)
    .frame(minWidth: 120)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    .overlay {
      RoundedRectangle(cornerRadius: 6)
        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
    .allowsHitTesting(false)
  }

  private func hoverTitle(_ selection: SpreadsheetChartHoverSelection) -> String {
    guard let anchor = selection.anchor else { return "" }
    if model.chart?.type == .histogram { return anchor.category }
    if let date = anchor.xDate { return model.formattedDate(date) }
    if model.usesTimeXAxis { return model.formattedXAxisValue(anchor.x) }
    if model.usesNumericXAxis { return model.formattedValue(anchor.x, isTime: false) }
    return anchor.category
  }

  private func lastValueLabel(_ datum: SpreadsheetChartDatum) -> some View {
    Text(
      "\(datum.series) · \(model.formattedValue(datum.value, isTime: model.usesTimeValueAxis))"
    )
    .font(.system(size: 9, weight: .medium))
    .lineLimit(1)
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
  }
}

private struct SpreadsheetChartScaleModifier: ViewModifier {
  let xDomain: ClosedRange<Double>?
  let xDateDomain: ClosedRange<Date>?
  let yDomain: ClosedRange<Double>?
  let xScale: SpreadsheetChartAxisScale
  let yScale: SpreadsheetChartAxisScale

  @ViewBuilder
  func body(content: Content) -> some View {
    if let xDateDomain {
      applyYScale(to: content.chartXScale(domain: xDateDomain))
    } else if let xDomain {
      if xScale == .logarithmic {
        applyYScale(to: content.chartXScale(domain: xDomain, type: .log))
      } else {
        applyYScale(to: content.chartXScale(domain: xDomain))
      }
    } else {
      applyYScale(to: content)
    }
  }

  @ViewBuilder
  private func applyYScale<ChartView: View>(to content: ChartView) -> some View {
    if let yDomain {
      if yScale == .logarithmic {
        content.chartYScale(domain: yDomain, type: .log)
      } else {
        content.chartYScale(domain: yDomain)
      }
    } else {
      content
    }
  }
}
