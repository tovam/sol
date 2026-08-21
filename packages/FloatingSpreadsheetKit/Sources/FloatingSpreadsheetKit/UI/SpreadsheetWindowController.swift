import AppKit

final class SpreadsheetWindowController: NSWindowController, NSWindowDelegate,
  SpreadsheetGridViewDelegate, SpreadsheetToolbarViewDelegate
{
  private static let preferredSurfaceSize = NSSize(width: 430, height: 390)

  var onClose: (() -> Void)?
  var onOpenChart: ((SpreadsheetChartDefinition) -> Void)?

  private let spreadsheetDocument: SpreadsheetDocument
  private let panel: FloatingSpreadsheetPanel
  private let toolbar = SpreadsheetToolbarView()
  private let cellContentBar = SpreadsheetCellContentBarView()
  private let gridContainer: SpreadsheetGridContainerView
  private var documentObserver: NSObjectProtocol?
  private var chartPopover: NSPopover?
  private var settingsPopover: NSPopover?
  private weak var settingsContent: SpreadsheetSettingsPopoverController?
  private var didClose = false

  init(document: SpreadsheetDocument) {
    spreadsheetDocument = document
    panel = FloatingSpreadsheetPanel(size: Self.preferredSurfaceSize)
    gridContainer = SpreadsheetGridContainerView(document: document)
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
      preferredSize: Self.preferredSurfaceSize
    )
    NSApp.activate(ignoringOtherApps: true)
    panel.orderFrontRegardless()
    panel.makeKey()
    panel.makeFirstResponder(gridContainer.gridView)
  }

  func bringToFront() {
    NSApp.activate(ignoringOtherApps: true)
    panel.orderFrontRegardless()
    panel.makeKey()
    panel.makeFirstResponder(gridContainer.gridView)
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
      panel.animator().alphaValue = 0.84
    }
  }

  func windowWillClose(_ notification: Notification) {
    guard !didClose else { return }
    didClose = true
    chartPopover?.close()
    settingsPopover?.close()
    onClose?()
  }

  private func configureWindow() {
    panel.delegate = self
    panel.minSize = FloatingSpreadsheetPanel.windowSize(
      forSurfaceSize: NSSize(width: 400, height: 200)
    )
    panel.contentMinSize = panel.minSize
  }

  private func configureContent() {
    let backdrop = panel.installRoundedContent()

    toolbar.delegate = self
    toolbar.updateTitle(spreadsheetDocument.name)
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    cellContentBar.translatesAutoresizingMaskIntoConstraints = false
    gridContainer.gridView.delegate = self
    gridContainer.translatesAutoresizingMaskIntoConstraints = false
    backdrop.addSubview(toolbar)
    backdrop.addSubview(cellContentBar)
    backdrop.addSubview(gridContainer)

    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
      toolbar.topAnchor.constraint(equalTo: backdrop.topAnchor),
      toolbar.heightAnchor.constraint(equalToConstant: 32),
      cellContentBar.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
      cellContentBar.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
      cellContentBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
      cellContentBar.heightAnchor.constraint(equalToConstant: 20),
      gridContainer.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
      gridContainer.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
      gridContainer.topAnchor.constraint(equalTo: cellContentBar.bottomAnchor),
      gridContainer.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
    ])
    refreshToolbarSelection()
  }

  private func observeDocument() {
    documentObserver = NotificationCenter.default.addObserver(
      forName: .floatingSpreadsheetDidChange,
      object: spreadsheetDocument,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      toolbar.updateTitle(spreadsheetDocument.name)
      gridContainer.reloadData()
      refreshToolbarSelection()
      settingsContent?.update(spreadsheetDocument.settings)
    }
  }

  func spreadsheetGridView(
    _ gridView: SpreadsheetGridView,
    selectionDidChange range: CellRange
  ) {
    refreshToolbarSelection()
  }

  func spreadsheetGridView(
    _ gridView: SpreadsheetGridView,
    pasteText text: String,
    at origin: CellAddress
  ) {
    do {
      let detection = try DelimitedTextParser().detect(text)
      switch detection {
      case .direct(let candidate):
        confirmAndImport(candidate.rows, options: candidate.options, origin: origin)
      case .ambiguous(let candidates):
        let initial = candidates.first?.options
          ?? DelimitedTextOptions(separator: .comma)
        DelimitedImportCoordinator.resolve(
          text: text,
          initialOptions: initial,
          in: panel
        ) { [weak self] rows, options in
          self?.confirmAndImport(rows, options: options, origin: origin)
        }
      }
    } catch {
      NSAlert(error: error).beginSheetModal(for: panel)
    }
  }

  func spreadsheetGridViewDidRequestBold(_ gridView: SpreadsheetGridView) {
    toggleBold()
  }

  func spreadsheetGridViewDidRequestItalic(_ gridView: SpreadsheetGridView) {
    toggleItalic()
  }

  func spreadsheetToolbar(_ toolbar: SpreadsheetToolbarView, renameTo name: String) {
    spreadsheetDocument.rename(to: name)
    toolbar.updateTitle(spreadsheetDocument.name)
    panel.makeFirstResponder(gridContainer.gridView)
  }

  func spreadsheetToolbarDidRequestBold(_ toolbar: SpreadsheetToolbarView) {
    toggleBold()
  }

  func spreadsheetToolbarDidRequestItalic(_ toolbar: SpreadsheetToolbarView) {
    toggleItalic()
  }

  func spreadsheetToolbarDidRequestDate(_ toolbar: SpreadsheetToolbarView) {
    toggleFormat(.date)
  }

  func spreadsheetToolbarDidRequestPercent(_ toolbar: SpreadsheetToolbarView) {
    toggleFormat(.percent)
  }

  func spreadsheetToolbarDidRequestCurrency(_ toolbar: SpreadsheetToolbarView) {
    toggleFormat(.currency(code: spreadsheetDocument.settings.currencyCode))
  }

  func spreadsheetToolbarDidRequestSettings(_ toolbar: SpreadsheetToolbarView) {
    showSettingsPopover(relativeTo: toolbar.settingsPositioningView)
  }

  func spreadsheetToolbarDidRequestImport(_ toolbar: SpreadsheetToolbarView) {
    DelimitedImportCoordinator.chooseFile(in: panel) { [weak self] rows, options in
      guard let self else { return }
      confirmAndImport(
        rows,
        options: options,
        origin: gridContainer.gridView.activeCell
      )
    }
  }

  func spreadsheetToolbarDidRequestChart(_ toolbar: SpreadsheetToolbarView) {
    showChartPopover(relativeTo: toolbar)
  }

  func spreadsheetToolbarDidRequestClose(_ toolbar: SpreadsheetToolbarView) {
    closeWindow()
  }

  private func toggleBold() {
    let range = gridContainer.gridView.selectedRange
    let active = gridContainer.gridView.activeCell
    let enabled = !(spreadsheetDocument.record(at: active)?.style.isBold ?? false)
    spreadsheetDocument.setBold(enabled, in: range)
  }

  private func toggleItalic() {
    let range = gridContainer.gridView.selectedRange
    let active = gridContainer.gridView.activeCell
    let enabled = !(spreadsheetDocument.record(at: active)?.style.isItalic ?? false)
    spreadsheetDocument.setItalic(enabled, in: range)
  }

  private func toggleFormat(_ requested: CellDisplayFormat) {
    let range = gridContainer.gridView.selectedRange
    let active = gridContainer.gridView.activeCell
    let current = spreadsheetDocument.record(at: active)?.style.displayFormat ?? .automatic
    spreadsheetDocument.setDisplayFormat(
      current == requested ? .automatic : requested,
      in: range
    )
  }

  private func confirmAndImport(
    _ rows: [[String]],
    options: DelimitedTextOptions,
    origin: CellAddress
  ) {
    DelimitedImportCoordinator.confirmOverwrite(
      rows: rows,
      options: options,
      at: origin,
      document: spreadsheetDocument,
      in: panel
    ) { [weak self] rows, options in
      guard let self else { return }
      gridContainer.gridView.applyImportedRows(
        rows,
        firstRowIsHeader: options.firstRowIsHeader
      )
    }
  }

  private func showChartPopover(relativeTo positioningView: NSView) {
    chartPopover?.close()
    let content = SpreadsheetChartPopoverController(
      document: spreadsheetDocument,
      initialRange: gridContainer.gridView.selectedRange
    )
    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentSize = content.view.frame.size
    popover.contentViewController = content
    content.onCreate = { [weak self, weak popover] chart in
      guard let self else { return }
      spreadsheetDocument.addChart(chart)
      popover?.close()
      onOpenChart?(chart)
    }
    content.onOpen = { [weak self, weak popover] chart in
      popover?.close()
      self?.onOpenChart?(chart)
    }
    chartPopover = popover
    popover.show(
      relativeTo: positioningView.bounds,
      of: positioningView,
      preferredEdge: .maxY
    )
  }

  private func showSettingsPopover(relativeTo positioningView: NSView) {
    settingsPopover?.close()
    let content = SpreadsheetSettingsPopoverController(
      settings: spreadsheetDocument.settings
    )
    content.onChange = { [weak self] settings in
      self?.spreadsheetDocument.updateSettings(settings)
    }
    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentSize = content.view.frame.size
    popover.contentViewController = content
    settingsContent = content
    settingsPopover = popover
    popover.show(
      relativeTo: positioningView.bounds,
      of: positioningView,
      preferredEdge: .maxY
    )
  }

  private func refreshToolbarSelection() {
    let address = gridContainer.gridView.activeCell
    let style = spreadsheetDocument.record(at: address)?.style ?? .plain
    toolbar.updateSelection(address: address.description, style: style)
    cellContentBar.update(
      address: address,
      rawContent: spreadsheetDocument.rawInput(at: address)
    )
  }

  private func validateAlwaysOnTop() {
    guard panel.level != .floating else { return }
    panel.close()
  }
}
