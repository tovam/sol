import AppKit
import UniformTypeIdentifiers

final class DelimitedImportCoordinator: NSObject {
  typealias Completion = ([[String]], DelimitedTextOptions) -> Void

  private let originalText: String
  private let originalData: Data?
  private let completion: Completion
  private let alert = NSAlert()
  private let separatorPopup = NSPopUpButton()
  private let headerCheckbox = NSButton(checkboxWithTitle: "First row is a header", target: nil, action: nil)
  private let encodingPopup = NSPopUpButton()
  private let quoteField = NSTextField(string: "\"")
  private let escapePopup = NSPopUpButton()
  private let preview = NSTextView()
  private var options: DelimitedTextOptions

  private init(
    text: String,
    data: Data?,
    initialOptions: DelimitedTextOptions,
    completion: @escaping Completion
  ) {
    originalText = text
    originalData = data
    options = initialOptions
    self.completion = completion
    super.init()
  }

  static func resolve(
    text: String,
    data: Data? = nil,
    initialOptions: DelimitedTextOptions,
    in window: NSWindow,
    completion: @escaping Completion
  ) {
    let coordinator = DelimitedImportCoordinator(
      text: text,
      data: data,
      initialOptions: initialOptions,
      completion: completion
    )
    coordinator.present(in: window)
  }

  static func chooseFile(
    in window: NSWindow,
    completion: @escaping Completion
  ) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [
      .commaSeparatedText,
      .tabSeparatedText,
      .plainText,
      .text,
    ]
    panel.message = "Choose CSV, TSV, or plain delimited text"
    panel.beginSheetModal(for: window) { response in
      guard response == .OK, let url = panel.url else { return }
      do {
        let data = try Data(contentsOf: url)
        let parser = DelimitedTextParser()
        let decoded = try parser.decode(data)
        let detection = try parser.detect(decoded.text)
        switch detection {
        case .direct(let candidate):
          var options = candidate.options
          options.encoding = decoded.encoding
          completion(candidate.rows, options)
        case .ambiguous(let candidates):
          var initial = candidates.first?.options
            ?? DelimitedTextOptions(separator: .comma)
          initial.encoding = decoded.encoding
          resolve(
            text: decoded.text,
            data: data,
            initialOptions: initial,
            in: window,
            completion: completion
          )
        }
      } catch {
        presentError(error, in: window)
      }
    }
  }

  static func confirmOverwrite(
    rows: [[String]],
    options: DelimitedTextOptions,
    at origin: CellAddress,
    document: SpreadsheetDocument,
    in window: NSWindow,
    completion: @escaping Completion
  ) {
    let rowCount = max(1, rows.count)
    let columnCount = max(1, rows.map { $0.count }.max() ?? 1)
    let destination = CellRange(
      start: origin,
      end: CellAddress(
        row: origin.row + rowCount - 1,
        column: origin.column + columnCount - 1
      )
    )
    guard !document.isEmpty(destination) else {
      completion(rows, options)
      return
    }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Replace existing cells?"
    alert.informativeText = "The imported data overlaps cells that already contain values."
    alert.addButton(withTitle: "Replace")
    alert.addButton(withTitle: "Cancel")
    alert.beginSheetModal(for: window) { response in
      if response == .alertFirstButtonReturn {
        completion(rows, options)
      }
    }
  }

  private func present(in window: NSWindow) {
    alert.alertStyle = .informational
    alert.messageText = "Import delimited data"
    alert.informativeText = "Sol could not determine the format with enough confidence."
    alert.addButton(withTitle: "Import")
    alert.addButton(withTitle: "Cancel")
    alert.accessoryView = makeAccessoryView()
    updateControlsFromOptions()
    updatePreview()

    alert.beginSheetModal(for: window) { [self] response in
      guard response == .alertFirstButtonReturn else { return }
      updateOptionsFromControls()
      do {
        let parser = DelimitedTextParser()
        let text: String
        if let originalData {
          text = try parser.decode(originalData, encoding: options.encoding).text
        } else {
          text = originalText
        }
        completion(try parser.parse(text, options: options), options)
      } catch {
        Self.presentError(error, in: window)
      }
    }
  }

  private func makeAccessoryView() -> NSView {
    separatorPopup.addItems(withTitles: DelimitedTextSeparator.allCases.map(\.displayName))
    encodingPopup.addItems(withTitles: DelimitedTextEncoding.allCases.map(\.displayName))
    escapePopup.addItems(withTitles: ["Double the quote", "Backslash"])

    for control in [separatorPopup, encodingPopup, escapePopup] {
      control.target = self
      control.action = #selector(optionsChanged)
    }
    headerCheckbox.target = self
    headerCheckbox.action = #selector(optionsChanged)
    quoteField.target = self
    quoteField.action = #selector(optionsChanged)
    quoteField.alignment = .center
    quoteField.maximumNumberOfLines = 1
    quoteField.widthAnchor.constraint(equalToConstant: 48).isActive = true

    let grid = NSGridView(views: [
      [NSTextField(labelWithString: "Separator"), separatorPopup],
      [NSTextField(labelWithString: "Encoding"), encodingPopup],
      [NSTextField(labelWithString: "Quote"), quoteField],
      [NSTextField(labelWithString: "Escaping"), escapePopup],
    ])
    grid.rowSpacing = 6
    grid.columnSpacing = 12
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .fill

    preview.isEditable = false
    preview.isSelectable = true
    preview.drawsBackground = false
    preview.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
    preview.textContainerInset = NSSize(width: 6, height: 6)

    let previewScroll = NSScrollView()
    previewScroll.documentView = preview
    previewScroll.hasVerticalScroller = true
    previewScroll.borderType = .bezelBorder
    previewScroll.translatesAutoresizingMaskIntoConstraints = false
    previewScroll.heightAnchor.constraint(equalToConstant: 112).isActive = true

    let stack = NSStackView(views: [grid, headerCheckbox, previewScroll])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 4, bottom: 4, right: 4)
    stack.frame = NSRect(x: 0, y: 0, width: 440, height: 252)
    previewScroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
    return stack
  }

  private func updateControlsFromOptions() {
    separatorPopup.selectItem(at: DelimitedTextSeparator.allCases.firstIndex(of: options.separator) ?? 0)
    encodingPopup.selectItem(at: DelimitedTextEncoding.allCases.firstIndex(of: options.encoding) ?? 0)
    headerCheckbox.state = options.firstRowIsHeader ? .on : .off
    quoteField.stringValue = String(options.quote)
    escapePopup.selectItem(at: options.escapeMode == .doubledQuote ? 0 : 1)
  }

  private func updateOptionsFromControls() {
    let separators = DelimitedTextSeparator.allCases
    let encodings = DelimitedTextEncoding.allCases
    options.separator = separators[max(0, separatorPopup.indexOfSelectedItem)]
    options.encoding = encodings[max(0, encodingPopup.indexOfSelectedItem)]
    options.firstRowIsHeader = headerCheckbox.state == .on
    options.quote = quoteField.stringValue.first ?? "\""
    options.escapeMode = escapePopup.indexOfSelectedItem == 1 ? .backslash : .doubledQuote
  }

  @objc private func optionsChanged() {
    updateOptionsFromControls()
    updatePreview()
  }

  private func updatePreview() {
    do {
      let parser = DelimitedTextParser()
      let text: String
      if let originalData {
        text = try parser.decode(originalData, encoding: options.encoding).text
      } else {
        text = originalText
      }
      let rows = try parser.parse(text, options: options)
      let visible = rows.prefix(8).map { row in
        row.prefix(8).map { value in
          value.replacingOccurrences(of: "\n", with: "↵")
        }.joined(separator: "  │  ")
      }.joined(separator: "\n")
      preview.string = visible
      preview.textColor = .labelColor
    } catch {
      preview.string = error.localizedDescription
      preview.textColor = .systemRed
    }
  }

  private static func presentError(_ error: Error, in window: NSWindow) {
    let alert = NSAlert(error: error)
    alert.beginSheetModal(for: window)
  }
}
