import AppKit

final class SpreadsheetSettingsPopoverController: NSViewController {
  var onChange: ((SpreadsheetSettings) -> Void)?
  var onDelete: (() -> Void)?

  private static let currencies: [(code: String, title: String)] = [
    ("EUR", "€  EUR"),
    ("USD", "$  USD"),
    ("GBP", "£  GBP"),
    ("CHF", "CHF"),
    ("CAD", "$  CAD"),
    ("JPY", "¥  JPY"),
  ]

  private var settings: SpreadsheetSettings
  private let localeControl = NSSegmentedControl(
    labels: SpreadsheetDisplayLocale.allCases.map(\.shortLabel),
    trackingMode: .selectOne,
    target: nil,
    action: nil
  )
  private let currencyPopup = NSPopUpButton()
  private let timeZonePopup = NSComboBox()
  private let archiveCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
  private let archiveDatePicker = NSDatePicker()

  init(settings: SpreadsheetSettings) {
    self.settings = settings
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 212))

    localeControl.target = self
    localeControl.action = #selector(changeLocale)
    localeControl.segmentStyle = .rounded
    localeControl.setAccessibilityLabel("Displayed number and date format")

    currencyPopup.addItems(withTitles: Self.currencies.map(\.title))
    currencyPopup.target = self
    currencyPopup.action = #selector(changeCurrency)
    currencyPopup.setAccessibilityLabel("Spreadsheet currency")

    timeZonePopup.addItem(withObjectValue: "System — \(TimeZone.current.identifier)")
    timeZonePopup.addItems(withObjectValues: TimeZone.knownTimeZoneIdentifiers)
    timeZonePopup.isEditable = true
    timeZonePopup.completes = true
    timeZonePopup.numberOfVisibleItems = 12
    timeZonePopup.target = self
    timeZonePopup.action = #selector(changeTimeZone)
    timeZonePopup.setAccessibilityLabel("Spreadsheet time zone")

    archiveCheckbox.target = self
    archiveCheckbox.action = #selector(toggleScheduledArchive)
    archiveCheckbox.setAccessibilityLabel("Enable scheduled spreadsheet archive")
    archiveDatePicker.datePickerStyle = .textFieldAndStepper
    archiveDatePicker.datePickerElements = [.yearMonthDay, .hourMinute]
    archiveDatePicker.minDate = Date().addingTimeInterval(60)
    archiveDatePicker.target = self
    archiveDatePicker.action = #selector(changeScheduledArchiveDate)
    archiveDatePicker.setAccessibilityLabel("Scheduled archive date and time")

    let archiveControls = NSStackView(views: [archiveCheckbox, archiveDatePicker])
    archiveControls.orientation = .horizontal
    archiveControls.alignment = .centerY
    archiveControls.spacing = 6

    let formatLabel = NSTextField(labelWithString: "Format")
    let currencyLabel = NSTextField(labelWithString: "Currency")
    let timeZoneLabel = NSTextField(labelWithString: "Time zone")
    let archiveLabel = NSTextField(labelWithString: "Auto-archive")
    for label in [formatLabel, currencyLabel, timeZoneLabel, archiveLabel] {
      label.font = .systemFont(ofSize: 11)
      label.textColor = .secondaryLabelColor
      label.alignment = .right
    }

    let grid = NSGridView(views: [
      [formatLabel, localeControl],
      [currencyLabel, currencyPopup],
      [timeZoneLabel, timeZonePopup],
      [archiveLabel, archiveControls],
    ])
    grid.rowSpacing = 8
    grid.columnSpacing = 10
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .fill
    grid.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(grid)

    let archiveExplanation = NSTextField(
      wrappingLabelWithString: "At this time the window closes and the sheet moves to Sol Settings."
    )
    archiveExplanation.font = .systemFont(ofSize: 10)
    archiveExplanation.textColor = .secondaryLabelColor
    archiveExplanation.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(archiveExplanation)

    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(separator)

    let deleteButton = NSButton(
      title: "Delete this spreadsheet…",
      target: self,
      action: #selector(deleteSpreadsheet)
    )
    deleteButton.image = NSImage(
      systemSymbolName: "trash",
      accessibilityDescription: "Delete this spreadsheet"
    )
    deleteButton.imagePosition = .imageLeading
    deleteButton.bezelStyle = .rounded
    deleteButton.contentTintColor = .systemRed
    deleteButton.setAccessibilityLabel("Delete this spreadsheet")
    deleteButton.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(deleteButton)

    NSLayoutConstraint.activate([
      grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
      grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
      grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
      archiveExplanation.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
      archiveExplanation.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
      archiveExplanation.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 6),
      separator.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
      separator.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
      separator.topAnchor.constraint(equalTo: archiveExplanation.bottomAnchor, constant: 9),
      deleteButton.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
      deleteButton.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
      deleteButton.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 7),
      deleteButton.heightAnchor.constraint(equalToConstant: 26),
    ])

    view = root
    update(settings)
  }

  func update(_ settings: SpreadsheetSettings) {
    self.settings = settings
    guard isViewLoaded else { return }
    localeControl.selectedSegment = SpreadsheetDisplayLocale.allCases.firstIndex(
      of: settings.displayLocale
    ) ?? 0
    let currencyIndex = Self.currencies.firstIndex {
      $0.code == settings.currencyCode
    } ?? 0
    currencyPopup.selectItem(at: currencyIndex)
    timeZonePopup.stringValue = settings.timeZoneIdentifier
      ?? "System — \(TimeZone.current.identifier)"
    let scheduledArchiveAt = settings.scheduledArchiveAt
    archiveCheckbox.state = scheduledArchiveAt == nil ? .off : .on
    archiveDatePicker.isEnabled = scheduledArchiveAt != nil
    archiveDatePicker.dateValue = scheduledArchiveAt
      ?? Calendar.current.date(byAdding: .day, value: 1, to: Date())
      ?? Date().addingTimeInterval(86_400)
  }

  @objc private func changeLocale() {
    let locales = SpreadsheetDisplayLocale.allCases
    guard localeControl.selectedSegment >= 0,
      localeControl.selectedSegment < locales.count
    else {
      return
    }
    settings.displayLocale = locales[localeControl.selectedSegment]
    onChange?(settings)
  }

  @objc private func changeCurrency() {
    let selected = currencyPopup.indexOfSelectedItem
    guard selected >= 0, selected < Self.currencies.count else { return }
    settings.currencyCode = Self.currencies[selected].code
    onChange?(settings)
  }

  @objc private func changeTimeZone() {
    let value = timeZonePopup.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("System —") || value.isEmpty {
      settings.timeZoneIdentifier = nil
    } else if TimeZone(identifier: value) != nil {
      settings.timeZoneIdentifier = value
    } else {
      NSSound.beep()
      timeZonePopup.stringValue = settings.timeZoneIdentifier
        ?? "System — \(TimeZone.current.identifier)"
      return
    }
    onChange?(settings)
  }

  @objc private func toggleScheduledArchive() {
    if archiveCheckbox.state == .on {
      let minimum = Date().addingTimeInterval(60)
      let selected = max(archiveDatePicker.dateValue, minimum)
      archiveDatePicker.dateValue = selected
      archiveDatePicker.isEnabled = true
      settings.scheduledArchiveAt = selected
    } else {
      archiveDatePicker.isEnabled = false
      settings.scheduledArchiveAt = nil
    }
    onChange?(settings)
  }

  @objc private func changeScheduledArchiveDate() {
    guard archiveCheckbox.state == .on else { return }
    settings.scheduledArchiveAt = archiveDatePicker.dateValue
    onChange?(settings)
  }

  @objc private func deleteSpreadsheet() {
    onDelete?()
  }
}
