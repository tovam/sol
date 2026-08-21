import AppKit
import Charts
import Combine
import SwiftUI

final class SpreadsheetChartWindowController: NSWindowController, NSWindowDelegate {
  let documentID: UUID
  var onReturnToSpreadsheet: (() -> Void)?
  var onClose: (() -> Void)?

  private let spreadsheetDocument: SpreadsheetDocument
  private let chartID: UUID
  private let panel: FloatingSpreadsheetPanel
  private let model: SpreadsheetChartViewModel
  private let toolbar = SpreadsheetChartToolbarView()
  private var documentObserver: NSObjectProtocol?
  private var didClose = false

  init(document: SpreadsheetDocument, chartID: UUID) {
    spreadsheetDocument = document
    self.chartID = chartID
    documentID = document.id
    panel = FloatingSpreadsheetPanel(size: NSSize(width: 560, height: 360))
    model = SpreadsheetChartViewModel(document: document, chartID: chartID)
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
    panel.minSize = NSSize(width: 360, height: 250)
    panel.contentMinSize = panel.minSize
  }

  private func configureContent() {
    let backdrop = FloatingSpreadsheetBackdropView(frame: panel.contentView?.bounds ?? .zero)
    backdrop.autoresizingMask = [.width, .height]
    panel.contentView = backdrop

    toolbar.translatesAutoresizingMaskIntoConstraints = false
    toolbar.onType = { [weak self] type in self?.changeType(type) }
    toolbar.onToggleFrozen = { [weak self] in self?.toggleFrozen() }
    toolbar.onOptions = { [weak self] in self?.showOptions() }
    toolbar.onReturnToSource = { [weak self] in self?.onReturnToSpreadsheet?() }
    toolbar.onClose = { [weak self] in self?.closeWindow() }
    backdrop.addSubview(toolbar)

    let chartView = SpreadsheetChartView(model: model)
    let host = NSHostingView(rootView: chartView)
    host.translatesAutoresizingMaskIntoConstraints = false
    backdrop.addSubview(host)

    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
      toolbar.topAnchor.constraint(equalTo: backdrop.topAnchor),
      toolbar.heightAnchor.constraint(equalToConstant: 30),
      host.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 6),
      host.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -6),
      host.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
      host.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -6),
    ])
    panel.enableRoundedShadow()
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
    spreadsheetDocument.updateChart(chart, label: "Change chart type")
  }

  private func toggleFrozen() {
    guard let chart = spreadsheetDocument.charts.first(where: { $0.id == chartID }) else { return }
    spreadsheetDocument.setChartFrozen(id: chartID, frozen: !chart.isFrozen)
  }

  private func showOptions() {
    guard let chart = spreadsheetDocument.charts.first(where: { $0.id == chartID }) else { return }
    let rangeField = NSTextField(string: chart.sourceRange.description)
    rangeField.placeholderString = "A1:D12"
    let titleField = NSTextField(string: chart.title)
    let headerCheckbox = NSButton(
      checkboxWithTitle: "First row contains headers",
      target: nil,
      action: nil
    )
    headerCheckbox.state = chart.firstRowContainsHeaders ? .on : .off
    let labelsCheckbox = NSButton(
      checkboxWithTitle: "First column contains labels",
      target: nil,
      action: nil
    )
    labelsCheckbox.state = chart.firstColumnContainsLabels ? .on : .off
    let orientation = NSPopUpButton()
    orientation.addItems(withTitles: ["Series in columns", "Series in rows"])
    orientation.selectItem(at: chart.seriesOrientation == .columns ? 0 : 1)

    let grid = NSGridView(views: [
      [NSTextField(labelWithString: "Title"), titleField],
      [NSTextField(labelWithString: "Data range"), rangeField],
      [NSTextField(labelWithString: "Series"), orientation],
    ])
    grid.rowSpacing = 7
    grid.columnSpacing = 10
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .fill

    let stack = NSStackView(views: [grid, headerCheckbox, labelsCheckbox])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 7
    stack.frame = NSRect(x: 0, y: 0, width: 380, height: 132)

    let alert = NSAlert()
    alert.messageText = "Chart options"
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
        if response == .alertFirstButtonReturn { NSSound.beep() }
        return
      }
      var changed = chart
      changed.title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if changed.title.isEmpty { changed.title = "Chart" }
      changed.sourceRange = range
      changed.firstRowContainsHeaders = headerCheckbox.state == .on
      changed.firstColumnContainsLabels = labelsCheckbox.state == .on
      changed.seriesOrientation = orientation.indexOfSelectedItem == 1 ? .rows : .columns
      if changed.isFrozen {
        changed.frozenSeries = spreadsheetDocument.chartSeries(
          for: changed,
          ignoringFrozenState: true
        )
      }
      spreadsheetDocument.updateChart(changed)
    }
  }

  private func refreshToolbar() {
    guard let chart = spreadsheetDocument.charts.first(where: { $0.id == chartID }) else { return }
    toolbar.update(type: chart.type, isFrozen: chart.isFrozen)
  }

  private func validateAlwaysOnTop() {
    guard panel.level != .floating else { return }
    panel.close()
  }
}

private final class SpreadsheetChartToolbarView: NSView {
  var onType: ((SpreadsheetChartType) -> Void)?
  var onToggleFrozen: (() -> Void)?
  var onOptions: (() -> Void)?
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

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.7).cgColor

    let source = Self.button(symbol: "arrowshape.turn.up.left", tooltip: "Return to spreadsheet")
    let options = Self.button(symbol: "slider.horizontal.3", tooltip: "Chart options")
    let close = Self.button(symbol: "xmark", tooltip: "Close chart")
    source.target = self
    source.action = #selector(returnToSource)
    options.target = self
    options.action = #selector(showOptions)
    close.target = self
    close.action = #selector(closeWindow)
    typeButton.target = self
    typeButton.action = #selector(showTypes)
    freezeButton.target = self
    freezeButton.action = #selector(toggleFrozen)

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let stack = NSStackView(views: [close, spacer, source, typeButton, freezeButton, options])
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
    }
  }
}

private struct SpreadsheetChartDatum: Identifiable {
  var id: String
  var series: String
  var category: String
  var x: Double
  var value: Double
}

private final class SpreadsheetChartViewModel: ObservableObject {
  @Published private(set) var chart: SpreadsheetChartDefinition?
  @Published private(set) var data: [SpreadsheetChartDatum] = []

  private let document: SpreadsheetDocument
  private let chartID: UUID

  init(document: SpreadsheetDocument, chartID: UUID) {
    self.document = document
    self.chartID = chartID
    reload()
  }

  func reload() {
    guard let chart = document.charts.first(where: { $0.id == chartID }) else {
      self.chart = nil
      data = []
      return
    }
    self.chart = chart
    data = document.chartSeries(for: chart).flatMap { series in
      series.points.enumerated().map { index, point in
        SpreadsheetChartDatum(
          id: "\(series.name)-\(index)-\(point.category)",
          series: series.name,
          category: point.category,
          x: point.x ?? Double(index),
          value: point.value
        )
      }
    }
  }
}

private struct SpreadsheetChartView: View {
  @ObservedObject var model: SpreadsheetChartViewModel

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
    Chart(model.data) { datum in
      switch definition.type {
      case .line:
        LineMark(
          x: .value("Category", datum.category),
          y: .value("Value", datum.value)
        )
        .foregroundStyle(by: .value("Series", datum.series))
        .symbol(by: .value("Series", datum.series))
      case .bar:
        BarMark(
          x: .value("Category", datum.category),
          y: .value("Value", datum.value)
        )
        .foregroundStyle(by: .value("Series", datum.series))
      case .area:
        AreaMark(
          x: .value("Category", datum.category),
          y: .value("Value", datum.value)
        )
        .foregroundStyle(by: .value("Series", datum.series))
        .opacity(0.55)
      case .scatter:
        PointMark(
          x: .value("X", datum.x),
          y: .value("Value", datum.value)
        )
        .foregroundStyle(by: .value("Series", datum.series))
        .symbolSize(42)
      case .pie:
        SectorMark(
          angle: .value("Value", abs(datum.value)),
          innerRadius: .ratio(0.48),
          angularInset: 1.2
        )
        .foregroundStyle(by: .value("Category", datum.category))
      }
    }
  }
}
