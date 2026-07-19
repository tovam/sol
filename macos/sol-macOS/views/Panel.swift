import AppKit

private final class SpotlightBackgroundView: NSVisualEffectView {
  static let cornerRadius: CGFloat = 24
  private let glassTintLayer = CAGradientLayer()
  private let edgeHighlightLayer = CAGradientLayer()
  private let edgeHighlightMask = CAShapeLayer()

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
    updateGlassAppearance()
  }

  override func layout() {
    super.layout()
    updateGlassFrames()
  }

  private func configureLayer() {
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.borderWidth = 0.65

    glassTintLayer.startPoint = CGPoint(x: 0, y: 1)
    glassTintLayer.endPoint = CGPoint(x: 1, y: 0)
    glassTintLayer.locations = [0, 0.48, 1]
    layer?.insertSublayer(glassTintLayer, at: 0)

    edgeHighlightLayer.startPoint = CGPoint(x: 0, y: 1)
    edgeHighlightLayer.endPoint = CGPoint(x: 1, y: 0)
    edgeHighlightLayer.locations = [0, 0.45, 1]
    edgeHighlightLayer.mask = edgeHighlightMask
    layer?.addSublayer(edgeHighlightLayer)

    edgeHighlightMask.fillColor = NSColor.clear.cgColor
    edgeHighlightMask.strokeColor = NSColor.white.cgColor
    edgeHighlightMask.lineWidth = 1.15

    updateGlassFrames()
    updateGlassAppearance()
  }

  private func updateGlassFrames() {
    glassTintLayer.frame = bounds
    edgeHighlightLayer.frame = bounds
    edgeHighlightMask.frame = bounds
    edgeHighlightMask.path = CGPath(
      roundedRect: bounds.insetBy(dx: 0.6, dy: 0.6),
      cornerWidth: Self.cornerRadius - 0.6,
      cornerHeight: Self.cornerRadius - 0.6,
      transform: nil
    )
  }

  private func updateGlassAppearance() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      layer?.borderColor = (
        isDark
          ? NSColor.white.withAlphaComponent(0.16)
          : NSColor.black.withAlphaComponent(0.11)
      ).cgColor

      glassTintLayer.colors = isDark
        ? [
          NSColor.white.withAlphaComponent(0.105).cgColor,
          NSColor.white.withAlphaComponent(0.025).cgColor,
          NSColor.black.withAlphaComponent(0.075).cgColor,
        ]
        : [
          NSColor.white.withAlphaComponent(0.30).cgColor,
          NSColor.white.withAlphaComponent(0.08).cgColor,
          NSColor.white.withAlphaComponent(0.17).cgColor,
        ]
      edgeHighlightLayer.colors = [
        NSColor.white.withAlphaComponent(isDark ? 0.38 : 0.72).cgColor,
        NSColor.white.withAlphaComponent(isDark ? 0.08 : 0.18).cgColor,
        NSColor.white.withAlphaComponent(isDark ? 0.16 : 0.34).cgColor,
      ]
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
