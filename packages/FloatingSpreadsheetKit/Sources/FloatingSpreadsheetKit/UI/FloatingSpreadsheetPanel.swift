import AppKit

final class FloatingSpreadsheetPanel: NSPanel {
  static let shadowPadding: CGFloat = 14

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func sendEvent(_ event: NSEvent) {
    if isEscape(event) {
      close()
      return
    }
    super.sendEvent(event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard !isEscape(event) else {
      close()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func cancelOperation(_ sender: Any?) {
    close()
  }

  convenience init(size: NSSize) {
    let framedSize = Self.windowSize(forSurfaceSize: size)
    self.init(
      contentRect: NSRect(origin: .zero, size: framedSize),
      styleMask: [.borderless, .resizable],
      backing: .buffered,
      defer: false
    )
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isOpaque = false
    backgroundColor = .clear
    // The default content view is rectangular. Enabling the system shadow here
    // makes AppKit cache that rectangle even after the rounded surface is added.
    hasShadow = false
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
    isMovableByWindowBackground = true
    animationBehavior = .utilityWindow
  }

  static func windowSize(forSurfaceSize size: NSSize) -> NSSize {
    NSSize(
      width: size.width + shadowPadding * 2,
      height: size.height + shadowPadding * 2
    )
  }

  func installRoundedContent() -> FloatingSpreadsheetBackdropView {
    let host = FloatingSpreadsheetShadowHostView(frame: contentView?.bounds ?? .zero)
    host.autoresizingMask = [.width, .height]
    contentView = host
    return host.backdrop
  }

  private func isEscape(_ event: NSEvent) -> Bool {
    event.type == .keyDown
      && (event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1B}")
  }
}

private final class FloatingSpreadsheetShadowHostView: NSView {
  let backdrop = FloatingSpreadsheetBackdropView(frame: .zero)
  private let shadowLayer = CALayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.masksToBounds = true

    shadowLayer.masksToBounds = false
    shadowLayer.shadowColor = NSColor.black.cgColor
    shadowLayer.shadowOpacity = 0.25
    shadowLayer.shadowRadius = 10
    shadowLayer.shadowOffset = CGSize(width: 0, height: -2)
    layer?.addSublayer(shadowLayer)

    addSubview(backdrop)
    applyColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isOpaque: Bool { false }

  override func layout() {
    super.layout()
    let padding = FloatingSpreadsheetPanel.shadowPadding
    let surfaceFrame = bounds.insetBy(dx: padding, dy: padding)
    backdrop.frame = surfaceFrame

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shadowLayer.frame = surfaceFrame
    shadowLayer.cornerRadius = 14
    shadowLayer.cornerCurve = .continuous
    shadowLayer.shadowPath = CGPath(
      roundedRect: shadowLayer.bounds,
      cornerWidth: 14,
      cornerHeight: 14,
      transform: nil
    )
    CATransaction.commit()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  private func applyColors() {
    shadowLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
  }
}

final class FloatingSpreadsheetBackdropView: NSVisualEffectView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    material = .popover
    blendingMode = .behindWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = 14
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.borderWidth = 0.5
    applyColors()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  private func applyColors() {
    layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.58).cgColor
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.8).cgColor
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

enum FloatingSpreadsheetWindowPlacement {
  static func center(_ window: NSWindow, preferredSize: NSSize) {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
      ?? NSScreen.main
    guard let screen else {
      let requestedSize = window is FloatingSpreadsheetPanel
        ? FloatingSpreadsheetPanel.windowSize(forSurfaceSize: preferredSize)
        : preferredSize
      window.setContentSize(requestedSize)
      window.center()
      return
    }
    let requestedSize = window is FloatingSpreadsheetPanel
      ? FloatingSpreadsheetPanel.windowSize(forSurfaceSize: preferredSize)
      : preferredSize
    let size = NSSize(
      width: min(requestedSize.width, screen.visibleFrame.width * 0.9),
      height: min(requestedSize.height, screen.visibleFrame.height * 0.86)
    )
    window.setFrame(
      NSRect(
        x: floor(screen.visibleFrame.midX - size.width / 2),
        y: floor(screen.visibleFrame.midY - size.height / 2),
        width: size.width,
        height: size.height
      ),
      display: false
    )
  }
}
