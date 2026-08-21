import AppKit

final class FloatingSpreadsheetPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  convenience init(size: NSSize) {
    self.init(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .resizable],
      backing: .buffered,
      defer: false
    )
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
    isMovableByWindowBackground = true
    animationBehavior = .utilityWindow
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
      window.setContentSize(preferredSize)
      window.center()
      return
    }
    let size = NSSize(
      width: min(preferredSize.width, screen.visibleFrame.width * 0.9),
      height: min(preferredSize.height, screen.visibleFrame.height * 0.86)
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
