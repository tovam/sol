import AppKit

private final class SpotlightFallbackBackgroundView: NSVisualEffectView {
  private let tintOverlay = NSView(frame: .zero)

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
    layer?.cornerRadius = 24
    layer?.cornerCurve = .circular
    layer?.masksToBounds = true

    tintOverlay.wantsLayer = true
    tintOverlay.frame = bounds
    tintOverlay.autoresizingMask = [.width, .height]
    addSubview(tintOverlay)
  }

  func applyGlassAppearance(
    style: String,
    cornerRadius: CGFloat,
    tintColor: NSColor?
  ) {
    // NSVisualEffectView has no exact clear/regular equivalent. These are the
    // closest stable legacy materials for Sol's floating panel.
    material = style == "regular" ? .hudWindow : .popover
    layer?.cornerRadius = cornerRadius
    tintOverlay.layer?.backgroundColor = tintColor?.cgColor
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

  func applyGlassAppearance(
    style: String,
    cornerRadius: Double,
    tintHex: String?,
    tintOpacity: Double
  ) {
    let safeRadius = CGFloat(min(max(cornerRadius, 0), 32))
    let safeOpacity = CGFloat(min(max(tintOpacity, 0), 1))
    let tintColor: NSColor?

    if let tintHex,
      !tintHex.isEmpty,
      safeOpacity > 0,
      let parsedColor = NSColor(hex: tintHex as NSString)
    {
      tintColor = parsedColor.withAlphaComponent(safeOpacity)
    } else {
      tintColor = nil
    }

    if #available(macOS 26.0, *), let glassView = contentView as? NSGlassEffectView {
      glassView.style = style == "regular" ? .regular : .clear
      glassView.cornerRadius = safeRadius
      glassView.tintColor = tintColor
      glassView.needsDisplay = true
    } else if let effectView = contentView as? SpotlightFallbackBackgroundView {
      effectView.applyGlassAppearance(
        style: style,
        cornerRadius: safeRadius,
        tintColor: tintColor
      )
      effectView.needsDisplay = true
    }

    invalidateShadow()
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
