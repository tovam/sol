import AppKit

private final class SpotlightBackgroundView: NSVisualEffectView {
  static let cornerRadius: CGFloat = 24

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configureLayer()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configureLayer()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateBorderColor()
  }

  private func configureLayer() {
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.borderWidth = 0.5
    updateBorderColor()
  }

  private func updateBorderColor() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
    }
  }
}

final class Panel: NSPanel, NSWindowDelegate {
  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    self.hasShadow = true
    self.level = .floating
    self.collectionBehavior.insert(.fullScreenAuxiliary)
    self.collectionBehavior.insert(.canJoinAllSpaces)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.isMovableByWindowBackground = true
    self.isReleasedWhenClosed = false
    self.isOpaque = false
    self.animationBehavior = .utilityWindow
    self.delegate = self
    self.backgroundColor = .clear

    if #available(macOS 11.0, *) {
      self.titlebarSeparatorStyle = .none
    }

    let effectView = SpotlightBackgroundView(
      frame: .zero
    )
    effectView.autoresizingMask = [.width, .height]
    effectView.material = .popover
    effectView.blendingMode = .behindWindow
    effectView.state = .active

    self.contentView = effectView
    self.contentView!.wantsLayer = true
  }

  override var canBecomeKey: Bool {
    return true
  }

  override var canBecomeMain: Bool {
    return true
  }

  func windowDidResignKey(_ notification: Notification) {
    DispatchQueue.main.async {
      PanelManager.shared.hideWindow()
    }
  }
}
