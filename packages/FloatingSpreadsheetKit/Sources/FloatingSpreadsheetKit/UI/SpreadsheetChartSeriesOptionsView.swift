import AppKit

enum SpreadsheetChartPalette {
  static let colors = [
    "#4F7CF7",
    "#F59E0B",
    "#10B981",
    "#8B5CF6",
    "#EF4444",
    "#06B6D4",
    "#EC4899",
    "#84CC16",
  ]

  static func defaultHex(at index: Int) -> String {
    colors[index % colors.count]
  }

  static func color(from hex: String?) -> NSColor {
    guard let hex else { return .controlAccentColor }
    let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard value.count == 6, let integer = UInt64(value, radix: 16) else {
      return .controlAccentColor
    }
    return NSColor(
      srgbRed: CGFloat((integer >> 16) & 0xFF) / 255,
      green: CGFloat((integer >> 8) & 0xFF) / 255,
      blue: CGFloat(integer & 0xFF) / 255,
      alpha: 1
    )
  }

  static func hex(from color: NSColor) -> String {
    guard let rgb = color.usingColorSpace(.sRGB) else { return colors[0] }
    return String(
      format: "#%02X%02X%02X",
      Int((rgb.redComponent * 255).rounded()),
      Int((rgb.greenComponent * 255).rounded()),
      Int((rgb.blueComponent * 255).rounded())
    )
  }
}

final class SpreadsheetChartSeriesOptionsView: NSView {
  private let rows: [SpreadsheetChartSeriesOptionRow]

  init(
    series: [SpreadsheetChartSeries],
    chart: SpreadsheetChartDefinition,
    showsLineControls: Bool,
    xPlaceholder: String,
    yPlaceholder: String,
    visibleHeight: CGFloat = 176
  ) {
    rows = series.enumerated().map { index, series in
      SpreadsheetChartSeriesOptionRow(
        series: series,
        configuration: chart.configuration(for: series.stableID),
        defaultColorHex: SpreadsheetChartPalette.defaultHex(at: index),
        showsLineControls: showsLineControls,
        xPlaceholder: xPlaceholder,
        yPlaceholder: yPlaceholder
      )
    }
    super.init(frame: NSRect(x: 0, y: 0, width: 440, height: visibleHeight))
    configure(series: series, showsLineControls: showsLineControls)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configurations() -> [SpreadsheetChartSeriesConfiguration] {
    rows.map { $0.configuration() }
  }

  private func configure(
    series: [SpreadsheetChartSeries],
    showsLineControls: Bool
  ) {
    wantsLayer = true
    layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.32).cgColor
    layer?.cornerRadius = 7
    layer?.borderWidth = 0.5
    layer?.borderColor = NSColor.separatorColor.cgColor

    guard !rows.isEmpty else {
      let label = NSTextField(labelWithString: "No plottable series in this range yet.")
      label.textColor = .secondaryLabelColor
      label.alignment = .center
      label.translatesAutoresizingMaskIntoConstraints = false
      addSubview(label)
      NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: centerXAnchor),
        label.centerYAnchor.constraint(equalTo: centerYAnchor),
      ])
      return
    }

    let content = NSStackView(views: rows)
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 6
    content.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
    let rowHeight: CGFloat = showsLineControls ? 126 : 38
    content.frame = NSRect(
      x: 0,
      y: 0,
      width: 428,
      height: CGFloat(rows.count) * rowHeight + CGFloat(max(0, rows.count - 1) * 6) + 12
    )
    for row in rows {
      row.widthAnchor.constraint(equalToConstant: 416).isActive = true
      row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
    }

    let scrollView = NSScrollView(frame: bounds)
    scrollView.documentView = content
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }
}

private final class SpreadsheetChartSeriesOptionRow: NSView {
  private let seriesID: String
  private let visibleCheckbox = NSButton(
    checkboxWithTitle: "Visible",
    target: nil,
    action: nil
  )
  private let pointsCheckbox = NSButton(
    checkboxWithTitle: "Points",
    target: nil,
    action: nil
  )
  private let targetCheckbox = NSButton(
    checkboxWithTitle: "Target A→B",
    target: nil,
    action: nil
  )
  private let colorWell = NSColorWell()
  private let startXField = NSTextField()
  private let startYField = NSTextField()
  private let endXField = NSTextField()
  private let endYField = NSTextField()
  private let scaleCheckbox = NSButton(
    checkboxWithTitle: "Include target in axis scale",
    target: nil,
    action: nil
  )
  private var targetControls: [NSControl] = []

  init(
    series: SpreadsheetChartSeries,
    configuration: SpreadsheetChartSeriesConfiguration,
    defaultColorHex: String,
    showsLineControls: Bool,
    xPlaceholder: String,
    yPlaceholder: String
  ) {
    seriesID = series.stableID
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.035).cgColor
    layer?.cornerRadius = 6

    visibleCheckbox.state = configuration.isVisible ? .on : .off
    visibleCheckbox.setAccessibilityLabel("Show series \(series.name)")
    pointsCheckbox.state = configuration.showsPoints ? .on : .off
    pointsCheckbox.isHidden = !showsLineControls
    pointsCheckbox.setAccessibilityLabel("Show points for \(series.name)")
    targetCheckbox.state = configuration.target == nil ? .off : .on
    targetCheckbox.isHidden = !showsLineControls
    targetCheckbox.target = self
    targetCheckbox.action = #selector(toggleTarget)
    targetCheckbox.setAccessibilityLabel("Show target segment for \(series.name)")
    targetCheckbox.toolTip = "Draw a dashed target segment for this series"

    colorWell.color = SpreadsheetChartPalette.color(
      from: configuration.colorHex ?? defaultColorHex
    )
    colorWell.colorWellStyle = .minimal
    colorWell.setAccessibilityLabel("Color for \(series.name)")

    let name = NSTextField(labelWithString: series.name)
    name.font = .systemFont(ofSize: 11, weight: .semibold)
    name.lineBreakMode = .byTruncatingMiddle
    name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let top = NSStackView(views: [visibleCheckbox, name, colorWell, pointsCheckbox, targetCheckbox])
    top.orientation = .horizontal
    top.alignment = .centerY
    top.spacing = 8

    startXField.stringValue = configuration.target?.startX ?? ""
    startYField.stringValue = configuration.target?.startY ?? ""
    endXField.stringValue = configuration.target?.endX ?? ""
    endYField.stringValue = configuration.target?.endY ?? ""
    startXField.placeholderString = xPlaceholder
    endXField.placeholderString = xPlaceholder
    startYField.placeholderString = yPlaceholder
    endYField.placeholderString = yPlaceholder
    for field in [startXField, startYField, endXField, endYField] {
      field.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
      field.controlSize = .small
    }
    startXField.toolTip = "Target point A — X"
    startYField.toolTip = "Target point A — Y"
    endXField.toolTip = "Target point B — X"
    endYField.toolTip = "Target point B — Y"
    scaleCheckbox.state = configuration.target?.includesInScale == true ? .on : .off
    scaleCheckbox.controlSize = .small
    targetControls = [startXField, startYField, endXField, endYField, scaleCheckbox]

    let targetGrid = NSGridView(views: [
      [
        NSTextField(labelWithString: ""),
        targetCoordinateHeading("X"),
        targetCoordinateHeading("Y"),
      ],
      [NSTextField(labelWithString: "A"), startXField, startYField],
      [NSTextField(labelWithString: "B"), endXField, endYField],
    ])
    targetGrid.rowSpacing = 4
    targetGrid.columnSpacing = 6
    targetGrid.column(at: 0).xPlacement = .trailing
    targetGrid.column(at: 1).xPlacement = .fill
    targetGrid.column(at: 2).xPlacement = .fill

    let targetArea = NSStackView(views: [targetGrid, scaleCheckbox])
    targetArea.orientation = .vertical
    targetArea.alignment = .leading
    targetArea.spacing = 3
    targetArea.isHidden = !showsLineControls

    let stack = NSStackView(views: [top, targetArea])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 5
    stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 5, right: 8)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
      top.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16),
      targetGrid.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16),
    ])
    updateTargetControls()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configuration() -> SpreadsheetChartSeriesConfiguration {
    let target = targetCheckbox.state == .on
      ? SpreadsheetChartTargetSegment(
        startX: startXField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
        startY: startYField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
        endX: endXField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
        endY: endYField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
        includesInScale: scaleCheckbox.state == .on
      )
      : nil
    return SpreadsheetChartSeriesConfiguration(
      seriesID: seriesID,
      isVisible: visibleCheckbox.state == .on,
      colorHex: SpreadsheetChartPalette.hex(from: colorWell.color),
      showsPoints: pointsCheckbox.state == .on,
      target: target
    )
  }

  @objc private func toggleTarget() {
    updateTargetControls()
  }

  private func updateTargetControls() {
    let enabled = targetCheckbox.state == .on
    for control in targetControls { control.isEnabled = enabled }
  }

  private func targetCoordinateHeading(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 9, weight: .semibold)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    return label
  }
}
