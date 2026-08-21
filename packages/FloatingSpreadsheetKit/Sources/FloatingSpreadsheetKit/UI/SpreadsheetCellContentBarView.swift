import AppKit

final class SpreadsheetCellContentBarView: NSView {
  private let formulaLabel = NSTextField(labelWithString: "ƒx")
  private let contentLabel = NSTextField(labelWithString: "")
  private let separator = NSView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func update(address: CellAddress, rawContent: String) {
    contentLabel.stringValue = rawContent
    contentLabel.placeholderString = "Empty"
    contentLabel.toolTip = rawContent.isEmpty
      ? "\(address.description) is empty"
      : "\(address.description): \(rawContent)"
    setAccessibilityLabel("Contents of \(address.description)")
    setAccessibilityValue(rawContent)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  private func configure() {
    wantsLayer = true

    formulaLabel.font = .systemFont(ofSize: 10, weight: .medium)
    formulaLabel.textColor = .tertiaryLabelColor
    formulaLabel.alignment = .center
    formulaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    contentLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
    contentLabel.textColor = .labelColor
    contentLabel.cell?.usesSingleLineMode = true
    contentLabel.cell?.lineBreakMode = .byTruncatingTail

    separator.wantsLayer = true
    separator.translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView(views: [formulaLabel, separator, contentLabel])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
      formulaLabel.widthAnchor.constraint(equalToConstant: 20),
      separator.widthAnchor.constraint(equalToConstant: 1),
      separator.heightAnchor.constraint(equalToConstant: 12),
    ])
    contentLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    applyColors()
  }

  private func applyColors() {
    layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.96).cgColor
    separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
  }
}
