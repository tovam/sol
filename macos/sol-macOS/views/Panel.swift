import AppKit

private final class SpotlightFallbackBackgroundView: NSVisualEffectView {
  static let cornerRadius: CGFloat = 24

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configureLayer()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configureLayer()
  }

  private func configureLayer() {
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.cornerCurve = .circular
    layer?.masksToBounds = true
  }
}

final class Panel: NSPanel, NSWindowDelegate {
  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    self.hasShadow = true
    self.level = .floating
    self.collectionBehavior.insert(.fullScreenAuxiliary)
    self.collectionBehavior.insert(.canJoinAllSpaces)
    self.isMovableByWindowBackground = true
    self.isReleasedWhenClosed = false
    self.isOpaque = false
    self.animationBehavior = .utilityWindow
    self.delegate = self
    self.backgroundColor = .clear

    if #available(macOS 26.0, *) {
      let glassView = NSGlassEffectView(frame: .zero)
      glassView.autoresizingMask = [.width, .height]
      glassView.style = .clear
      glassView.tintColor = nil
      glassView.cornerRadius = 24
      self.contentView = glassView
    } else {
      let effectView = SpotlightFallbackBackgroundView(frame: .zero)
      effectView.autoresizingMask = [.width, .height]
      effectView.material = .popover
      effectView.blendingMode = .behindWindow
      effectView.state = .active
      self.contentView = effectView
    }
  }

  func installRootView(_ rootView: NSView) {
    rootView.autoresizingMask = [.width, .height]

    if #available(macOS 26.0, *), let glassView = contentView as? NSGlassEffectView {
      glassView.contentView = rootView
    } else {
      contentView?.addSubview(rootView)
    }
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
