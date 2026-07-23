import AppKit
import Foundation

let externalPromptWindowIdentifier = NSUserInterfaceItemIdentifier("com.ospfranco.sol.external-prompt")

private enum ExternalPromptKind: String {
  case choice
  case input
  case choiceOrInput = "choice-or-input"
}

private enum ExternalPromptIcon {
  case symbol(String)
  case emoji(String)
}

private struct ExternalPromptItem {
  let id: String
  let label: String
  let detail: String?
  let icon: ExternalPromptIcon?
  let hasValue: Bool
  let value: Any
}

private struct ExternalPromptInput {
  let placeholder: String
  let initialValue: String
  let secure: Bool
  let minLength: Int
  let maxLength: Int
}

private struct ExternalPromptDismissPolicy {
  let escape: Bool
  let outsideClick: Bool
}

private struct ExternalPromptRequest {
  let sourceName: String
  let sourcePID: Int?
  let title: String
  let message: String?
  let kind: ExternalPromptKind
  let multiple: Bool
  let items: [ExternalPromptItem]
  let input: ExternalPromptInput?
  let dismiss: ExternalPromptDismissPolicy
  let sensitive: Bool
  let timeoutMilliseconds: Int

  static func parse(_ object: Any) throws -> ExternalPromptRequest {
    let root = try PromptJSON.object(object, field: nil)
    try PromptJSON.allowOnly(
      root,
      keys: [
        "source", "title", "message", "kind", "multiple", "items", "input",
        "dismiss", "sensitive", "timeoutMs",
      ],
      field: nil
    )

    let source = try PromptJSON.object(
      PromptJSON.required(root, key: "source"),
      field: "source"
    )
    try PromptJSON.allowOnly(source, keys: ["name", "pid"], field: "source")
    let sourceName = try PromptJSON.string(
      PromptJSON.required(source, key: "name", parent: "source"),
      field: "source.name",
      minimum: 1,
      maximum: 200
    )
    let sourcePID = try PromptJSON.optionalInteger(
      source["pid"],
      field: "source.pid",
      minimum: 1
    )
    let title = try PromptJSON.string(
      PromptJSON.required(root, key: "title"),
      field: "title",
      minimum: 1,
      maximum: 200
    )
    let message = try PromptJSON.optionalString(
      root["message"],
      field: "message",
      maximum: 2_000
    )
    let kindValue = try PromptJSON.string(
      PromptJSON.required(root, key: "kind"),
      field: "kind",
      minimum: 1,
      maximum: 50
    )
    guard let kind = ExternalPromptKind(rawValue: kindValue) else {
      throw PromptJSON.error(
        "kind must be choice, input, or choice-or-input.",
        field: "kind"
      )
    }
    let multiple = try PromptJSON.optionalBoolean(root["multiple"], field: "multiple") ?? false
    if multiple && kind != .choice {
      throw PromptJSON.error(
        "multiple can only be true when kind is choice.",
        field: "multiple"
      )
    }

    let items: [ExternalPromptItem]
    if kind == .input {
      if root["items"] != nil, !(root["items"] is NSNull) {
        throw PromptJSON.error("items is forbidden when kind is input.", field: "items")
      }
      items = []
    } else {
      guard let rawItems = root["items"] as? [Any], !rawItems.isEmpty else {
        throw PromptJSON.error(
          "items must contain at least one item for this kind.",
          field: "items"
        )
      }
      guard rawItems.count <= 1_000 else {
        throw PromptJSON.error("items cannot contain more than 1000 entries.", field: "items")
      }
      var seenIDs = Set<String>()
      items = try rawItems.enumerated().map { index, rawItem in
        let field = "items[\(index)]"
        let item = try PromptJSON.object(rawItem, field: field)
        try PromptJSON.allowOnly(
          item,
          keys: ["id", "label", "detail", "icon", "value"],
          field: field
        )
        let id = try PromptJSON.string(
          PromptJSON.required(item, key: "id", parent: field),
          field: "\(field).id",
          minimum: 1,
          maximum: 200
        )
        guard seenIDs.insert(id).inserted else {
          throw PromptJSON.error("id must be unique.", field: "\(field).id")
        }
        let label = try PromptJSON.string(
          PromptJSON.required(item, key: "label", parent: field),
          field: "\(field).label",
          minimum: 1,
          maximum: 500
        )
        let detail = try PromptJSON.optionalString(
          item["detail"],
          field: "\(field).detail",
          maximum: 2_000
        )
        let icon = try parseIcon(item["icon"], field: "\(field).icon")
        let hasValue = item.keys.contains("value")
        return ExternalPromptItem(
          id: id,
          label: label,
          detail: detail,
          icon: icon,
          hasValue: hasValue,
          value: item["value"] ?? NSNull()
        )
      }
    }

    let input: ExternalPromptInput?
    if kind == .choice {
      if root["input"] != nil, !(root["input"] is NSNull) {
        throw PromptJSON.error("input is forbidden when kind is choice.", field: "input")
      }
      input = nil
    } else {
      let rawInput = try PromptJSON.object(
        PromptJSON.required(root, key: "input"),
        field: "input"
      )
      try PromptJSON.allowOnly(
        rawInput,
        keys: ["placeholder", "initialValue", "secure", "minLength", "maxLength"],
        field: "input"
      )
      let placeholder = try PromptJSON.optionalString(
        rawInput["placeholder"],
        field: "input.placeholder",
        maximum: 200
      ) ?? ""
      let initialValue = try PromptJSON.optionalString(
        rawInput["initialValue"],
        field: "input.initialValue",
        maximum: 10_000
      ) ?? ""
      let secure = try PromptJSON.optionalBoolean(rawInput["secure"], field: "input.secure") ?? false
      let minLength = try PromptJSON.optionalInteger(
        rawInput["minLength"],
        field: "input.minLength",
        minimum: 0
      ) ?? 0
      let maxLength = try PromptJSON.optionalInteger(
        rawInput["maxLength"],
        field: "input.maxLength",
        minimum: 0
      ) ?? 10_000
      guard minLength <= maxLength else {
        throw PromptJSON.error(
          "minLength cannot exceed maxLength.",
          field: "input.minLength"
        )
      }
      guard initialValue.count <= maxLength else {
        throw PromptJSON.error(
          "initialValue exceeds maxLength.",
          field: "input.initialValue"
        )
      }
      input = ExternalPromptInput(
        placeholder: placeholder,
        initialValue: initialValue,
        secure: secure,
        minLength: minLength,
        maxLength: maxLength
      )
    }

    let dismiss: ExternalPromptDismissPolicy
    if let rawDismissValue = root["dismiss"], !(rawDismissValue is NSNull) {
      let rawDismiss = try PromptJSON.object(rawDismissValue, field: "dismiss")
      try PromptJSON.allowOnly(
        rawDismiss,
        keys: ["escape", "outsideClick"],
        field: "dismiss"
      )
      dismiss = ExternalPromptDismissPolicy(
        escape: try PromptJSON.optionalBoolean(
          rawDismiss["escape"],
          field: "dismiss.escape"
        ) ?? true,
        outsideClick: try PromptJSON.optionalBoolean(
          rawDismiss["outsideClick"],
          field: "dismiss.outsideClick"
        ) ?? true
      )
    } else {
      dismiss = ExternalPromptDismissPolicy(escape: true, outsideClick: true)
    }

    let explicitlySensitive = try PromptJSON.optionalBoolean(
      root["sensitive"],
      field: "sensitive"
    ) ?? false
    let timeoutMilliseconds = try PromptJSON.optionalInteger(
      root["timeoutMs"],
      field: "timeoutMs",
      minimum: 0
    ) ?? 0

    return ExternalPromptRequest(
      sourceName: sourceName,
      sourcePID: sourcePID,
      title: title,
      message: message,
      kind: kind,
      multiple: multiple,
      items: items,
      input: input,
      dismiss: dismiss,
      sensitive: explicitlySensitive || input?.secure == true,
      timeoutMilliseconds: timeoutMilliseconds
    )
  }

  private static func parseIcon(_ value: Any?, field: String) throws -> ExternalPromptIcon? {
    guard let value, !(value is NSNull) else { return nil }
    let icon = try PromptJSON.object(value, field: field)
    guard let typeValue = icon["type"] else {
      throw PromptJSON.error("type is required.", field: "\(field).type")
    }
    let type = try PromptJSON.string(
      typeValue,
      field: "\(field).type",
      minimum: 1,
      maximum: 30
    )
    switch type {
    case "sf-symbol":
      try PromptJSON.allowOnly(icon, keys: ["type", "name"], field: field)
      let name = try PromptJSON.string(
        PromptJSON.required(icon, key: "name", parent: field),
        field: "\(field).name",
        minimum: 1,
        maximum: 200
      )
      return .symbol(name)
    case "emoji":
      try PromptJSON.allowOnly(icon, keys: ["type", "value"], field: field)
      let emoji = try PromptJSON.string(
        PromptJSON.required(icon, key: "value", parent: field),
        field: "\(field).value",
        minimum: 1,
        maximum: 16
      )
      guard emoji.count == 1 else {
        throw PromptJSON.error(
          "value must contain one extended grapheme cluster.",
          field: "\(field).value"
        )
      }
      return .emoji(emoji)
    default:
      throw PromptJSON.error(
        "type must be sf-symbol or emoji.",
        field: "\(field).type"
      )
    }
  }
}

private enum PromptJSON {
  static func error(_ message: String, field: String?) -> SolHTTPAPIError {
    SolHTTPAPIError(status: 422, code: "invalid_field", message: message, field: field)
  }

  static func required(
    _ object: [String: Any],
    key: String,
    parent: String? = nil
  ) throws -> Any {
    guard let value = object[key], !(value is NSNull) else {
      let field = parent.map { "\($0).\(key)" } ?? key
      throw error("\(field) is required.", field: field)
    }
    return value
  }

  static func object(_ value: Any, field: String?) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
      throw error("Expected a JSON object.", field: field)
    }
    return object
  }

  static func allowOnly(_ object: [String: Any], keys: Set<String>, field: String?) throws {
    if let unknown = object.keys.first(where: { !keys.contains($0) }) {
      let path = field.map { "\($0).\(unknown)" } ?? unknown
      throw error("Unknown field \(path).", field: path)
    }
  }

  static func string(
    _ value: Any,
    field: String,
    minimum: Int,
    maximum: Int
  ) throws -> String {
    guard let string = value as? String else {
      throw error("Expected a string.", field: field)
    }
    guard string.count >= minimum, string.count <= maximum else {
      throw error(
        "Length must be between \(minimum) and \(maximum) characters.",
        field: field
      )
    }
    return string
  }

  static func optionalString(_ value: Any?, field: String, maximum: Int) throws -> String? {
    guard let value, !(value is NSNull) else { return nil }
    return try string(value, field: field, minimum: 0, maximum: maximum)
  }

  static func optionalBoolean(_ value: Any?, field: String) throws -> Bool? {
    guard let value, !(value is NSNull) else { return nil }
    guard let number = value as? NSNumber,
      CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID()
    else {
      throw error("Expected a boolean.", field: field)
    }
    return number.boolValue
  }

  static func optionalInteger(
    _ value: Any?,
    field: String,
    minimum: Int
  ) throws -> Int? {
    guard let value, !(value is NSNull) else { return nil }
    guard let number = value as? NSNumber,
      CFGetTypeID(number as CFTypeRef) != CFBooleanGetTypeID()
    else {
      throw error("Expected an integer.", field: field)
    }
    let double = number.doubleValue
    guard double.isFinite, double.rounded() == double,
      double >= Double(minimum), double <= Double(Int.max)
    else {
      throw error("Expected an integer greater than or equal to \(minimum).", field: field)
    }
    return Int(double)
  }
}

private final class ExternalPromptSession {
  let id = UUID()
  let request: ExternalPromptRequest
  let context: SolHTTPRequestContext
  var timeoutWorkItem: DispatchWorkItem?

  init(request: ExternalPromptRequest, context: SolHTTPRequestContext) {
    self.request = request
    self.context = context
  }
}

final class ExternalPromptCoordinator: NSObject, SolHTTPRouteHandler {
  static let shared = ExternalPromptCoordinator()

  private var pending: [ExternalPromptSession] = []
  private var active: ExternalPromptSession?
  private var controller: ExternalPromptWindowController?
  private var applicationToRestore: NSRunningApplication?

  private override init() {
    super.init()
  }

  func handle(_ request: SolHTTPRequest, context: SolHTTPRequestContext) -> Bool {
    guard request.path == "/v1/ui/prompts" else { return false }
    guard request.method == "POST" else {
      context.respond(.error(SolHTTPAPIError(
        status: 404,
        code: "not_found",
        message: "POST is required for /v1/ui/prompts."
      )))
      return true
    }

    do {
      let prompt = try ExternalPromptRequest.parse(request.jsonObject())
      let session = ExternalPromptSession(request: prompt, context: context)
      context.onDisconnect { [weak self, weak session] in
        guard let session else { return }
        DispatchQueue.main.async {
          self?.remove(sessionID: session.id, respond: false, response: nil)
        }
      }
      DispatchQueue.main.async { [weak self] in
        self?.enqueue(session)
      }
    } catch let error as SolHTTPAPIError {
      context.respond(.error(error))
    } catch {
      context.respond(.error(SolHTTPAPIError(
        status: 422,
        code: "invalid_field",
        message: error.localizedDescription
      )))
    }
    return true
  }

  func cancelAll() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let sessions = pending + (active.map { [$0] } ?? [])
      pending.removeAll()
      active = nil
      controller?.dismiss()
      controller = nil
      for session in sessions {
        session.timeoutWorkItem?.cancel()
        session.context.respond(.error(SolHTTPAPIError(
          status: 503,
          code: "api_unavailable",
          message: "Sol is shutting down."
        )))
      }
    }
  }

  private func enqueue(_ session: ExternalPromptSession) {
    pending.append(session)

    if session.request.timeoutMilliseconds > 0 {
      let workItem = DispatchWorkItem { [weak self, weak session] in
        guard let session else { return }
        self?.remove(
          sessionID: session.id,
          respond: true,
          response: .json(["status": "timeout"])
        )
      }
      session.timeoutWorkItem = workItem
      DispatchQueue.main.asyncAfter(
        deadline: .now() + Double(session.request.timeoutMilliseconds) / 1_000,
        execute: workItem
      )
    }

    showNextIfNeeded()
  }

  private func showNextIfNeeded() {
    guard active == nil, !pending.isEmpty else { return }
    if applicationToRestore == nil,
      let frontmost = NSWorkspace.shared.frontmostApplication,
      frontmost.bundleIdentifier != Bundle.main.bundleIdentifier
    {
      applicationToRestore = frontmost
    }

    let session = pending.removeFirst()
    active = session
    PanelManager.shared.hideWindow()

    let controller = ExternalPromptWindowController(
      request: session.request,
      submit: { [weak self, weak session] response in
        guard let session else { return }
        self?.remove(sessionID: session.id, respond: true, response: .json(response))
      },
      cancel: { [weak self, weak session] reason in
        guard let session else { return }
        self?.remove(
          sessionID: session.id,
          respond: true,
          response: .json(["status": "cancelled", "reason": reason])
        )
      }
    )
    self.controller = controller
    controller.present()
  }

  private func remove(
    sessionID: UUID,
    respond: Bool,
    response: SolHTTPResponse?
  ) {
    if let active, active.id == sessionID {
      active.timeoutWorkItem?.cancel()
      controller?.dismiss()
      controller = nil
      self.active = nil
      if respond, let response {
        active.context.respond(response)
      }

      if pending.isEmpty {
        let application = applicationToRestore
        applicationToRestore = nil
        DispatchQueue.main.async {
          application?.activate(options: [])
        }
      } else {
        DispatchQueue.main.async { [weak self] in
          self?.showNextIfNeeded()
        }
      }
      return
    }

    guard let index = pending.firstIndex(where: { $0.id == sessionID }) else { return }
    let session = pending.remove(at: index)
    session.timeoutWorkItem?.cancel()
    if respond, let response {
      session.context.respond(response)
    }
  }
}

private enum ExternalPromptVisibleRow {
  case item(ExternalPromptItem)
  case custom(String)
}

private enum ExternalPromptInputLayout {
  static let additionalLeadingPadding: CGFloat = 7
  static let additionalTrailingPadding: CGFloat = 4

  static func textRect(from rect: NSRect, font: NSFont?) -> NSRect {
    var result = rect
    result.origin.x += additionalLeadingPadding
    result.size.width = max(
      0,
      result.width - additionalLeadingPadding - additionalTrailingPadding
    )

    let resolvedFont = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let lineHeight = min(result.height, ceil(resolvedFont.boundingRectForFont.height) + 2)
    result.origin.y += floor(max(0, result.height - lineHeight) / 2)
    result.size.height = lineHeight
    return result
  }
}

private final class ExternalPromptTextFieldCell: NSTextFieldCell {
  override func drawingRect(forBounds rect: NSRect) -> NSRect {
    ExternalPromptInputLayout.textRect(
      from: super.drawingRect(forBounds: rect),
      font: font
    )
  }

  override func edit(
    withFrame rect: NSRect,
    in controlView: NSView,
    editor textObj: NSText,
    delegate: Any?,
    event: NSEvent?
  ) {
    super.edit(
      withFrame: drawingRect(forBounds: rect),
      in: controlView,
      editor: textObj,
      delegate: delegate,
      event: event
    )
  }

  override func select(
    withFrame rect: NSRect,
    in controlView: NSView,
    editor textObj: NSText,
    delegate: Any?,
    start selStart: Int,
    length selLength: Int
  ) {
    super.select(
      withFrame: drawingRect(forBounds: rect),
      in: controlView,
      editor: textObj,
      delegate: delegate,
      start: selStart,
      length: selLength
    )
  }
}

private final class ExternalPromptSecureTextFieldCell: NSSecureTextFieldCell {
  override func drawingRect(forBounds rect: NSRect) -> NSRect {
    ExternalPromptInputLayout.textRect(
      from: super.drawingRect(forBounds: rect),
      font: font
    )
  }

  override func edit(
    withFrame rect: NSRect,
    in controlView: NSView,
    editor textObj: NSText,
    delegate: Any?,
    event: NSEvent?
  ) {
    super.edit(
      withFrame: drawingRect(forBounds: rect),
      in: controlView,
      editor: textObj,
      delegate: delegate,
      event: event
    )
  }

  override func select(
    withFrame rect: NSRect,
    in controlView: NSView,
    editor textObj: NSText,
    delegate: Any?,
    start selStart: Int,
    length selLength: Int
  ) {
    super.select(
      withFrame: drawingRect(forBounds: rect),
      in: controlView,
      editor: textObj,
      delegate: delegate,
      start: selStart,
      length: selLength
    )
  }
}

private final class ExternalPromptTableRowView: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    guard selectionHighlightStyle != .none else { return }
    NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 10, yRadius: 10).fill()
  }
}

private final class ExternalPromptCellView: NSTableCellView {
  private let iconImageView = NSImageView()
  private let emojiLabel = NSTextField(labelWithString: "")
  private let titleLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")
  private let checkLabel = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    iconImageView.translatesAutoresizingMaskIntoConstraints = false
    iconImageView.imageScaling = .scaleProportionallyUpOrDown
    emojiLabel.translatesAutoresizingMaskIntoConstraints = false
    emojiLabel.alignment = .center
    emojiLabel.font = .systemFont(ofSize: 18)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .systemFont(ofSize: 14.5, weight: .medium)
    titleLabel.lineBreakMode = .byTruncatingTail
    detailLabel.translatesAutoresizingMaskIntoConstraints = false
    detailLabel.font = .systemFont(ofSize: 12)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.alignment = .right
    detailLabel.lineBreakMode = .byTruncatingTail
    checkLabel.translatesAutoresizingMaskIntoConstraints = false
    checkLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    checkLabel.alignment = .center

    addSubview(iconImageView)
    addSubview(emojiLabel)
    addSubview(titleLabel)
    addSubview(detailLabel)
    addSubview(checkLabel)

    NSLayoutConstraint.activate([
      iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
      iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconImageView.widthAnchor.constraint(equalToConstant: 22),
      iconImageView.heightAnchor.constraint(equalToConstant: 22),
      emojiLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      emojiLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      emojiLabel.widthAnchor.constraint(equalToConstant: 28),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 44),
      titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      detailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 14),
      detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
      checkLabel.leadingAnchor.constraint(equalTo: detailLabel.trailingAnchor, constant: 10),
      checkLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      checkLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      checkLabel.widthAnchor.constraint(equalToConstant: 22),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(
    row: ExternalPromptVisibleRow,
    highlighted: Bool,
    checked: Bool,
    multiple: Bool
  ) {
    let label: String
    let detail: String?
    let icon: ExternalPromptIcon?
    switch row {
    case let .item(item):
      label = item.label
      detail = item.detail
      icon = item.icon
    case let .custom(text):
      label = "Utiliser « \(text) »"
      detail = "Texte libre"
      icon = .symbol("text.cursor")
    }

    titleLabel.stringValue = label
    detailLabel.stringValue = detail ?? ""
    detailLabel.isHidden = detail == nil
    checkLabel.stringValue = multiple ? (checked ? "✓" : "○") : ""
    checkLabel.isHidden = !multiple
    titleLabel.textColor = .labelColor
    detailLabel.textColor = .secondaryLabelColor
    checkLabel.textColor = .controlAccentColor

    iconImageView.image = nil
    iconImageView.isHidden = true
    emojiLabel.stringValue = ""
    emojiLabel.isHidden = true
    switch icon {
    case let .symbol(name):
      iconImageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        ?? NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: nil)
      iconImageView.contentTintColor = highlighted ? .controlAccentColor : .secondaryLabelColor
      iconImageView.isHidden = false
    case let .emoji(value):
      emojiLabel.stringValue = value
      emojiLabel.isHidden = false
    case nil:
      iconImageView.image = NSImage(
        systemSymbolName: "sparkle.magnifyingglass",
        accessibilityDescription: nil
      )
      iconImageView.contentTintColor = highlighted ? .controlAccentColor : .secondaryLabelColor
      iconImageView.isHidden = false
    }
  }
}

private final class ExternalPromptWindowController: NSObject, NSTableViewDataSource,
  NSTableViewDelegate, NSTextFieldDelegate, NSWindowDelegate
{
  private let request: ExternalPromptRequest
  private let submit: ([String: Any]) -> Void
  private let cancel: (String) -> Void
  private let panel: Panel
  private let contentRootView = NSView(frame: .zero)
  private let rootStack = NSStackView()
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let submitButton = NSButton()
  private let validationLabel = NSTextField(labelWithString: "")
  private var inputField: NSTextField?
  private var tableHeightConstraint: NSLayoutConstraint?
  private var visibleRows: [ExternalPromptVisibleRow] = []
  private var checkedIDs = Set<String>()
  private var keyMonitor: Any?
  private var isDismissing = false
  private var isReloadingTable = false

  init(
    request: ExternalPromptRequest,
    submit: @escaping ([String: Any]) -> Void,
    cancel: @escaping (String) -> Void
  ) {
    self.request = request
    self.submit = submit
    self.cancel = cancel
    panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 656, height: 336))
    super.init()
    configurePanel()
    configureContent()
    refreshRows()
  }

  func present() {
    guard let screen = PanelManager.shared.getPreferredScreen() ?? NSScreen.main else { return }
    let size = panel.frame.size
    let visible = screen.visibleFrame
    panel.setFrameOrigin(NSPoint(
      x: floor(visible.midX - size.width / 2),
      y: floor(visible.maxY - visible.height * 0.22 - size.height)
    ))

    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window === panel else { return event }
      return handleKey(event) ? nil : event
    }

    NSApp.activate(ignoringOtherApps: true)
    // API prompts must surface even though Sol is an accessory-style app and
    // the shared glass panel is non-activating by design.
    panel.orderFrontRegardless()
    panel.makeKey()
    if let inputField {
      panel.makeFirstResponder(inputField)
    } else {
      panel.makeFirstResponder(tableView)
    }
  }

  func dismiss() {
    guard !isDismissing else { return }
    isDismissing = true
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
    panel.delegate = nil
    panel.orderOut(nil)
  }

  private func configurePanel() {
    panel.identifier = externalPromptWindowIdentifier
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .utilityWindow
    panel.delegate = self
    PanelManager.shared.applyCurrentGlassAppearance(to: panel)
  }

  private func configureContent() {
    contentRootView.wantsLayer = true
    contentRootView.layer?.backgroundColor = NSColor.clear.cgColor
    panel.installRootView(contentRootView)
    panel.setContentSize(panel.windowSize(forContentSize: NSSize(width: 620, height: 300)))
    panel.layoutInstalledRootView()

    rootStack.orientation = .vertical
    rootStack.alignment = .leading
    rootStack.spacing = 10
    rootStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    contentRootView.addSubview(rootStack)
    NSLayoutConstraint.activate([
      rootStack.leadingAnchor.constraint(equalTo: contentRootView.leadingAnchor),
      rootStack.trailingAnchor.constraint(equalTo: contentRootView.trailingAnchor),
      rootStack.topAnchor.constraint(equalTo: contentRootView.topAnchor),
      rootStack.bottomAnchor.constraint(equalTo: contentRootView.bottomAnchor),
    ])

    let sourceLabel = NSTextField(labelWithString: sourceText())
    sourceLabel.font = .systemFont(ofSize: 11, weight: .medium)
    sourceLabel.textColor = .tertiaryLabelColor
    sourceLabel.lineBreakMode = .byTruncatingTail
    rootStack.addArrangedSubview(sourceLabel)
    sourceLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -40).isActive = true

    let titleLabel = NSTextField(wrappingLabelWithString: request.title)
    titleLabel.font = .systemFont(ofSize: 21, weight: .semibold)
    titleLabel.maximumNumberOfLines = 2
    rootStack.addArrangedSubview(titleLabel)
    titleLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -40).isActive = true

    if let message = request.message, !message.isEmpty {
      let messageLabel = NSTextField(wrappingLabelWithString: message)
      messageLabel.font = .systemFont(ofSize: 13)
      messageLabel.textColor = .secondaryLabelColor
      messageLabel.maximumNumberOfLines = 4
      rootStack.addArrangedSubview(messageLabel)
      messageLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -40).isActive = true
    }

    if let input = request.input {
      let field: NSTextField
      if input.secure {
        let secureField = NSSecureTextField(frame: .zero)
        secureField.cell = ExternalPromptSecureTextFieldCell(textCell: input.initialValue)
        field = secureField
      } else {
        let textField = NSTextField(frame: .zero)
        textField.cell = ExternalPromptTextFieldCell(textCell: input.initialValue)
        field = textField
      }
      field.stringValue = input.initialValue
      field.placeholderString = input.placeholder
      field.font = .systemFont(ofSize: 15)
      field.focusRingType = .none
      field.isBezeled = true
      field.isBordered = true
      field.drawsBackground = true
      field.bezelStyle = .roundedBezel
      field.controlSize = .large
      field.isEditable = true
      field.isSelectable = true
      field.cell?.usesSingleLineMode = true
      field.cell?.lineBreakMode = .byClipping
      field.delegate = self
      field.translatesAutoresizingMaskIntoConstraints = false
      rootStack.addArrangedSubview(field)
      field.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -40).isActive = true
      field.heightAnchor.constraint(equalToConstant: 40).isActive = true
      inputField = field
    }

    if request.kind != .input {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("prompt"))
      column.resizingMask = .autoresizingMask
      tableView.addTableColumn(column)
      tableView.headerView = nil
      tableView.rowHeight = 50
      tableView.intercellSpacing = NSSize(width: 0, height: 0)
      tableView.backgroundColor = .clear
      tableView.selectionHighlightStyle = .regular
      tableView.allowsEmptySelection = false
      tableView.allowsMultipleSelection = false
      tableView.dataSource = self
      tableView.delegate = self
      tableView.target = self
      tableView.action = #selector(tableClicked)
      tableView.doubleAction = #selector(tableDoubleClicked)

      scrollView.documentView = tableView
      scrollView.drawsBackground = false
      scrollView.hasVerticalScroller = true
      scrollView.autohidesScrollers = true
      scrollView.borderType = .noBorder
      scrollView.translatesAutoresizingMaskIntoConstraints = false
      rootStack.addArrangedSubview(scrollView)
      scrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -40).isActive = true
      let height = scrollView.heightAnchor.constraint(equalToConstant: 50)
      height.isActive = true
      tableHeightConstraint = height
    }

    let footer = NSStackView()
    footer.orientation = .horizontal
    footer.alignment = .centerY
    footer.spacing = 10
    footer.translatesAutoresizingMaskIntoConstraints = false
    rootStack.addArrangedSubview(footer)
    footer.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -40).isActive = true

    validationLabel.font = .systemFont(ofSize: 11)
    validationLabel.textColor = .secondaryLabelColor
    validationLabel.lineBreakMode = .byTruncatingTail
    validationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    footer.addArrangedSubview(validationLabel)

    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    footer.addArrangedSubview(spacer)
    spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 8).isActive = true
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

    submitButton.title = request.multiple ? "Envoyer" : (request.kind == .choice ? "Choisir" : "Envoyer")
    submitButton.bezelStyle = .rounded
    submitButton.controlSize = .regular
    submitButton.target = self
    submitButton.action = #selector(submitButtonPressed)
    footer.addArrangedSubview(submitButton)

    updateValidation()
    resizePanelToFit()
  }

  private func sourceText() -> String {
    if let pid = request.sourcePID {
      return "Demande de \(request.sourceName) · identité déclarée · PID \(pid)"
    }
    return "Demande de \(request.sourceName) · identité déclarée"
  }

  private func resizePanelToFit() {
    panel.layoutInstalledRootView()
    contentRootView.layoutSubtreeIfNeeded()
    let cardHeight = max(184, rootStack.fittingSize.height)
    panel.setContentSize(
      panel.windowSize(forContentSize: NSSize(width: 620, height: cardHeight))
    )
    panel.layoutInstalledRootView()
    contentRootView.layoutSubtreeIfNeeded()
  }

  private func refreshRows() {
    let query = inputField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let matchingItems: [ExternalPromptItem]
    if request.kind == .choiceOrInput, !query.isEmpty {
      matchingItems = request.items.filter { item in
        item.label.range(
          of: query,
          options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil || item.detail?.range(
          of: query,
          options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
      }
    } else {
      matchingItems = request.items
    }
    visibleRows = matchingItems.map(ExternalPromptVisibleRow.item)

    if request.kind == .choiceOrInput, !query.isEmpty {
      let hasExactLabel = request.items.contains {
        $0.label.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
      }
      if !hasExactLabel {
        visibleRows.insert(.custom(query), at: 0)
      }
    }

    tableView.reloadData()
    if !visibleRows.isEmpty {
      tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
      tableView.scrollRowToVisible(0)
    }
    tableHeightConstraint?.constant = CGFloat(min(max(visibleRows.count, 1), 6)) * 50
    resizePanelToFit()
    updateValidation()
  }

  private func updateValidation() {
    if request.multiple {
      validationLabel.stringValue = "Entrée sélectionne · Cmd+Entrée envoie"
    } else if request.kind == .input, let input = request.input {
      let count = inputField?.stringValue.count ?? 0
      if count < input.minLength {
        validationLabel.stringValue = "\(input.minLength - count) caractère(s) encore requis"
      } else if count > input.maxLength {
        validationLabel.stringValue = "\(count - input.maxLength) caractère(s) en trop"
      } else {
        validationLabel.stringValue = "Entrée envoie · Échap annule"
      }
    } else if request.kind == .choiceOrInput,
      let input = request.input,
      let selectedRow = selectedVisibleRow()
    {
      if case let .custom(text) = selectedRow {
        if text.count < input.minLength {
          validationLabel.stringValue =
            "\(input.minLength - text.count) caractère(s) encore requis"
        } else if text.count > input.maxLength {
          validationLabel.stringValue = "\(text.count - input.maxLength) caractère(s) en trop"
        } else {
          validationLabel.stringValue = "Entrée envoie la réponse libre · Échap annule"
        }
      } else {
        validationLabel.stringValue = "Entrée choisit · Écrivez pour filtrer ou répondre"
      }
    } else {
      validationLabel.stringValue = "Entrée choisit · Échap annule"
    }
    submitButton.isEnabled = canSubmit()
  }

  private func canSubmit() -> Bool {
    if request.multiple {
      return !checkedIDs.isEmpty
    }
    if request.kind == .input, let input = request.input {
      let count = inputField?.stringValue.count ?? 0
      return count >= input.minLength && count <= input.maxLength
    }
    guard let selectedRow = selectedVisibleRow() else { return false }
    if case let .custom(text) = selectedRow, let input = request.input {
      return text.count >= input.minLength && text.count <= input.maxLength
    }
    return true
  }

  private func selectedVisibleRow() -> ExternalPromptVisibleRow? {
    let row = tableView.selectedRow
    guard row >= 0, row < visibleRows.count else { return nil }
    return visibleRows[row]
  }

  private func handleKey(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 53:
      if request.dismiss.escape {
        cancel("escape")
      }
      return true
    case 125:
      moveSelection(by: 1)
      return true
    case 126:
      moveSelection(by: -1)
      return true
    case 36, 76:
      let commandPressed = event.modifierFlags.contains(.command)
      if request.multiple {
        if commandPressed {
          submitCurrent()
        } else {
          toggleCurrentSelection()
        }
      } else {
        submitCurrent()
      }
      return true
    default:
      return false
    }
  }

  private func moveSelection(by offset: Int) {
    guard !visibleRows.isEmpty else { return }
    let current = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
    let next = (current + offset + visibleRows.count) % visibleRows.count
    tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
    tableView.scrollRowToVisible(next)
    reloadPreservingSelection()
  }

  private func toggleCurrentSelection() {
    let row = tableView.selectedRow
    guard request.multiple, row >= 0, row < visibleRows.count else { return }
    guard case let .item(item) = visibleRows[row] else { return }
    if checkedIDs.contains(item.id) {
      checkedIDs.remove(item.id)
    } else {
      checkedIDs.insert(item.id)
    }
    reloadPreservingSelection()
    updateValidation()
  }

  private func reloadPreservingSelection() {
    guard !isReloadingTable else { return }
    isReloadingTable = true
    defer { isReloadingTable = false }
    let selected = tableView.selectedRow
    tableView.reloadData()
    if selected >= 0, selected < visibleRows.count {
      tableView.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
    }
  }

  private func submitCurrent() {
    guard canSubmit() else { return }

    if request.multiple {
      let selectedItems = request.items.filter { checkedIDs.contains($0.id) }
      submit([
        "status": "selected",
        "items": selectedItems.map(responseItem),
      ])
      return
    }

    if request.kind == .input {
      submit([
        "status": "submitted",
        "text": inputField?.stringValue ?? "",
      ])
      return
    }

    let row = tableView.selectedRow
    guard row >= 0, row < visibleRows.count else { return }
    switch visibleRows[row] {
    case let .item(item):
      submit([
        "status": "selected",
        "items": [responseItem(item)],
      ])
    case let .custom(text):
      submit(["status": "submitted", "text": text])
    }
  }

  private func responseItem(_ item: ExternalPromptItem) -> [String: Any] {
    var response: [String: Any] = ["id": item.id]
    if item.hasValue {
      response["value"] = item.value
    }
    return response
  }

  @objc private func submitButtonPressed() {
    submitCurrent()
  }

  @objc private func tableClicked() {
    if request.multiple {
      toggleCurrentSelection()
    } else {
      reloadPreservingSelection()
      updateValidation()
    }
  }

  @objc private func tableDoubleClicked() {
    if !request.multiple {
      submitCurrent()
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    visibleRows.count
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    ExternalPromptTableRowView()
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  ) -> NSView? {
    guard row >= 0, row < visibleRows.count else { return nil }
    let view = ExternalPromptCellView()
    let checked: Bool
    if case let .item(item) = visibleRows[row] {
      checked = checkedIDs.contains(item.id)
    } else {
      checked = false
    }
    view.configure(
      row: visibleRows[row],
      highlighted: tableView.selectedRow == row,
      checked: checked,
      multiple: request.multiple
    )
    return view
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !isReloadingTable else { return }
    reloadPreservingSelection()
    updateValidation()
  }

  func controlTextDidChange(_ obj: Notification) {
    if request.kind == .choiceOrInput {
      refreshRows()
    } else {
      updateValidation()
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    guard !isDismissing, request.dismiss.outsideClick else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, !isDismissing else { return }
      cancel("outside-click")
    }
  }
}
