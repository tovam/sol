import AppKit

protocol SpreadsheetToolbarViewDelegate: AnyObject {
  func spreadsheetToolbar(_ toolbar: SpreadsheetToolbarView, renameTo name: String)
  func spreadsheetToolbarDidRequestBold(_ toolbar: SpreadsheetToolbarView)
  func spreadsheetToolbarDidRequestItalic(_ toolbar: SpreadsheetToolbarView)
  func spreadsheetToolbarDidRequestDate(_ toolbar: SpreadsheetToolbarView)
  func spreadsheetToolbarDidRequestPercent(_ toolbar: SpreadsheetToolbarView)
  func spreadsheetToolbarDidRequestCurrency(_ toolbar: SpreadsheetToolbarView)
  func spreadsheetToolbarDidRequestSettings(_ toolbar: SpreadsheetToolbarView)
  func spreadsheetToolbarDidRequestImport(_ toolbar: SpreadsheetToolbarView)
  func spreadsheetToolbarDidRequestChart(_ toolbar: SpreadsheetToolbarView)
  func spreadsheetToolbarDidRequestClose(_ toolbar: SpreadsheetToolbarView)
}

final class SpreadsheetToolbarView: NSView, NSTextFieldDelegate {
  weak var delegate: SpreadsheetToolbarViewDelegate?

  private let titleField = DraggableSpreadsheetTitleField()
  private let addressLabel = NSTextField(labelWithString: "A1")
  private let boldButton: NSButton
  private let italicButton: NSButton
  private let dateButton: NSButton
  private let percentButton: NSButton
  private let currencyButton: NSButton
  private let settingsButton: NSButton
  private let importButton: NSButton
  private let chartButton: NSButton
  private let closeButton: NSButton
  private let bottomSeparator = NSView()

  override init(frame frameRect: NSRect) {
    boldButton = Self.makeButton(symbol: "bold", tooltip: "Bold (⌘B)")
    italicButton = Self.makeButton(symbol: "italic", tooltip: "Italic (⌘I)")
    dateButton = Self.makeButton(symbol: "calendar", tooltip: "Date format")
    percentButton = Self.makeButton(symbol: "percent", tooltip: "Percent format")
    currencyButton = Self.makeButton(
      symbol: "dollarsign.circle",
      tooltip: "Currency format"
    )
    settingsButton = Self.makeButton(
      symbol: "gearshape",
      tooltip: "Spreadsheet settings"
    )
    importButton = Self.makeButton(
      symbol: "square.and.arrow.down",
      tooltip: "Import CSV or TSV"
    )
    chartButton = Self.makeButton(symbol: "chart.xyaxis.line", tooltip: "Charts")
    closeButton = Self.makeButton(symbol: "xmark", tooltip: "Close spreadsheet")
    super.init(frame: frameRect)
    configure()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateTitle(_ title: String) {
    guard titleField.currentEditor() == nil else { return }
    titleField.stringValue = title
  }

  func updateSelection(address: String, style: CellStyle) {
    addressLabel.stringValue = address
    boldButton.state = style.isBold ? .on : .off
    italicButton.state = style.isItalic ? .on : .off
    dateButton.state = style.displayFormat == .date ? .on : .off
    percentButton.state = style.displayFormat == .percent ? .on : .off
    if case .currency = style.displayFormat {
      currencyButton.state = .on
    } else {
      currencyButton.state = .off
    }
  }

  var settingsPositioningView: NSView { settingsButton }

  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }

  override var mouseDownCanMoveWindow: Bool { true }

  func controlTextDidEndEditing(_ notification: Notification) {
    delegate?.spreadsheetToolbar(self, renameTo: titleField.stringValue)
    titleField.finishRenaming()
  }

  private func configure() {
    wantsLayer = true

    titleField.stringValue = "Spreadsheet"
    titleField.placeholderString = "Spreadsheet name"
    titleField.font = .systemFont(ofSize: 12, weight: .semibold)
    titleField.textColor = .labelColor
    titleField.isBordered = false
    titleField.isBezeled = false
    titleField.drawsBackground = false
    titleField.focusRingType = .none
    titleField.cell?.usesSingleLineMode = true
    titleField.cell?.lineBreakMode = .byTruncatingTail
    titleField.delegate = self
    titleField.finishRenaming()
    titleField.setAccessibilityLabel("Spreadsheet name")

    addressLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    addressLabel.textColor = .secondaryLabelColor
    addressLabel.alignment = .center
    addressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    configureButton(boldButton, action: #selector(bold))
    configureButton(italicButton, action: #selector(italic))
    configureButton(dateButton, action: #selector(date))
    configureButton(percentButton, action: #selector(percent))
    configureButton(currencyButton, action: #selector(currency))
    configureButton(settingsButton, action: #selector(settings))
    configureButton(importButton, action: #selector(importData))
    configureButton(chartButton, action: #selector(chart))
    configureButton(closeButton, action: #selector(close))
    for button in [settingsButton, importButton, chartButton, closeButton] {
      button.setButtonType(.momentaryPushIn)
    }

    let stack = NSStackView(views: [
      closeButton,
      Self.separator(),
      titleField,
      addressLabel,
      Self.separator(),
      boldButton,
      italicButton,
      dateButton,
      percentButton,
      currencyButton,
      Self.separator(),
      settingsButton,
      importButton,
      chartButton,
    ])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    bottomSeparator.wantsLayer = true
    bottomSeparator.translatesAutoresizingMaskIntoConstraints = false
    addSubview(bottomSeparator)
    applyColors()

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
      titleField.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
      addressLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 42),
      bottomSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
      bottomSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
      bottomSeparator.bottomAnchor.constraint(equalTo: bottomAnchor),
      bottomSeparator.heightAnchor.constraint(equalToConstant: 1),
    ])
    titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  private func applyColors() {
    layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.96).cgColor
    bottomSeparator.layer?.backgroundColor = NSColor.separatorColor.cgColor
    for button in [
      boldButton,
      italicButton,
      dateButton,
      percentButton,
      currencyButton,
      settingsButton,
      importButton,
      chartButton,
      closeButton,
    ] {
      button.contentTintColor = .labelColor
    }
  }

  private func configureButton(_ button: NSButton, action: Selector) {
    button.target = self
    button.action = action
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 26),
      button.heightAnchor.constraint(equalToConstant: 26),
    ])
  }

  @objc private func bold() {
    delegate?.spreadsheetToolbarDidRequestBold(self)
  }

  @objc private func italic() {
    delegate?.spreadsheetToolbarDidRequestItalic(self)
  }

  @objc private func date() {
    delegate?.spreadsheetToolbarDidRequestDate(self)
  }

  @objc private func percent() {
    delegate?.spreadsheetToolbarDidRequestPercent(self)
  }

  @objc private func currency() {
    delegate?.spreadsheetToolbarDidRequestCurrency(self)
  }

  @objc private func settings() {
    delegate?.spreadsheetToolbarDidRequestSettings(self)
  }

  @objc private func importData() {
    delegate?.spreadsheetToolbarDidRequestImport(self)
  }

  @objc private func chart() {
    delegate?.spreadsheetToolbarDidRequestChart(self)
  }

  @objc private func close() {
    delegate?.spreadsheetToolbarDidRequestClose(self)
  }

  private static func makeButton(symbol: String, tooltip: String) -> NSButton {
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
      ?? NSImage(size: NSSize(width: 14, height: 14))
    let button = NSButton(image: image, target: nil, action: nil)
    button.bezelStyle = .accessoryBarAction
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.toolTip = tooltip
    button.setButtonType(.toggle)
    return button
  }

  private static func separator() -> NSView {
    let view = NSView()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.separatorColor.cgColor
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      view.widthAnchor.constraint(equalToConstant: 1),
      view.heightAnchor.constraint(equalToConstant: 17),
    ])
    return view
  }
}

private final class DraggableSpreadsheetTitleField: NSTextField {
  override var mouseDownCanMoveWindow: Bool { !isEditable }

  override func mouseDown(with event: NSEvent) {
    guard event.clickCount >= 2 else {
      window?.performDrag(with: event)
      return
    }

    isEditable = true
    isSelectable = true
    window?.makeFirstResponder(self)
    selectText(nil)
  }

  func finishRenaming() {
    isEditable = false
    isSelectable = false
  }
}
