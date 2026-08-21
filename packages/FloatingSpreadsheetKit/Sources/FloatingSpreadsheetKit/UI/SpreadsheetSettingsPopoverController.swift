import AppKit

final class SpreadsheetSettingsPopoverController: NSViewController {
  var onChange: ((SpreadsheetSettings) -> Void)?

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

  init(settings: SpreadsheetSettings) {
    self.settings = settings
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 238, height: 82))

    localeControl.target = self
    localeControl.action = #selector(changeLocale)
    localeControl.segmentStyle = .rounded
    localeControl.setAccessibilityLabel("Displayed number and date format")

    currencyPopup.addItems(withTitles: Self.currencies.map(\.title))
    currencyPopup.target = self
    currencyPopup.action = #selector(changeCurrency)
    currencyPopup.setAccessibilityLabel("Spreadsheet currency")

    let formatLabel = NSTextField(labelWithString: "Format")
    let currencyLabel = NSTextField(labelWithString: "Currency")
    for label in [formatLabel, currencyLabel] {
      label.font = .systemFont(ofSize: 11)
      label.textColor = .secondaryLabelColor
      label.alignment = .right
    }

    let grid = NSGridView(views: [
      [formatLabel, localeControl],
      [currencyLabel, currencyPopup],
    ])
    grid.rowSpacing = 8
    grid.columnSpacing = 10
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .fill
    grid.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(grid)

    NSLayoutConstraint.activate([
      grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
      grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
      grid.centerYAnchor.constraint(equalTo: root.centerYAnchor),
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
}
