import AppKit
import QuartzCore

@available(macOS 26.0, *)
private final class SpotlightGlassHostView: NSView {
  static let glassInset: CGFloat = 2
  let glassView = NSGlassEffectView(frame: .zero)
  private let panelClipView = NSView(frame: .zero)
  private let contentClipView = NSView(frame: .zero)
  private let shadowLayer = CALayer()
  private var shadowOpacity: CGFloat = 0.32
  private var shadowRadius: CGFloat = 12
  private var shadowOffsetY: CGFloat = 3
  var requestedCornerRadius: CGFloat = 24 {
    didSet {
      updateResolvedCornerRadius()
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.masksToBounds = false

    shadowLayer.shadowColor = NSColor.black.cgColor
    shadowLayer.masksToBounds = false
    layer?.insertSublayer(shadowLayer, at: 0)

    // Keep the Liquid Glass clip separate from the outer host: the glass must
    // stay clipped to rounded corners, while its shadow must be free to draw
    // into the transparent window margin around it.
    panelClipView.wantsLayer = true
    panelClipView.layer?.backgroundColor = NSColor.clear.cgColor
    panelClipView.layer?.cornerCurve = .circular
    panelClipView.layer?.masksToBounds = true
    contentClipView.wantsLayer = true
    contentClipView.layer?.backgroundColor = NSColor.clear.cgColor
    contentClipView.layer?.cornerCurve = .circular
    contentClipView.layer?.masksToBounds = true
    glassView.contentView = contentClipView
    panelClipView.addSubview(glassView)
    addSubview(panelClipView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    let shadowInsets = resolvedShadowInsets
    panelClipView.frame = NSRect(
      x: shadowInsets.left,
      y: shadowInsets.bottom,
      width: max(0, bounds.width - shadowInsets.left - shadowInsets.right),
      height: max(0, bounds.height - shadowInsets.top - shadowInsets.bottom)
    )
    let inset = Self.glassInset
    glassView.frame = NSRect(
      x: inset,
      y: inset,
      width: max(0, panelClipView.bounds.width - inset * 2),
      height: max(0, panelClipView.bounds.height - inset * 2)
    )
    contentClipView.frame = glassView.bounds
    contentClipView.subviews.forEach { $0.frame = contentClipView.bounds }
    updateResolvedCornerRadius()
  }

  var contentInsets: NSEdgeInsets {
    let shadowInsets = resolvedShadowInsets
    return NSEdgeInsets(
      top: shadowInsets.top + Self.glassInset,
      left: shadowInsets.left + Self.glassInset,
      bottom: shadowInsets.bottom + Self.glassInset,
      right: shadowInsets.right + Self.glassInset
    )
  }

  func applyShadowAppearance(opacity: CGFloat, radius: CGFloat, offsetY: CGFloat) {
    shadowOpacity = min(max(opacity, 0), 1)
    shadowRadius = min(max(radius, 0), 32)
    shadowOffsetY = min(max(offsetY, -16), 16)
    needsLayout = true
  }

  func installContentView(_ rootView: NSView) {
    contentClipView.subviews.forEach { $0.removeFromSuperview() }
    rootView.frame = contentClipView.bounds
    rootView.autoresizingMask = [.width, .height]
    contentClipView.addSubview(rootView)
  }

  func layoutContentView(_ rootView: NSView) {
    contentClipView.frame = glassView.bounds
    rootView.frame = contentClipView.bounds
  }

  private func updateResolvedCornerRadius() {
    guard glassView.bounds.width > 0, glassView.bounds.height > 0 else { return }
    // Avoid the exact half-height degeneracy that can turn the regular
    // style's inner highlight into a cusp on the collapsed 64 pt bar.
    let maximumRadius = max(
      0,
      min(glassView.bounds.width, glassView.bounds.height) / 2 - 0.5
    )
    let resolvedRadius = min(requestedCornerRadius, maximumRadius)
    let outerMaximumRadius = max(
      0,
      min(panelClipView.bounds.width, panelClipView.bounds.height) / 2
    )
    let outerRadius = min(
      resolvedRadius + Self.glassInset,
      outerMaximumRadius
    )
    if abs((panelClipView.layer?.cornerRadius ?? 0) - outerRadius) > 0.01 {
      panelClipView.layer?.cornerRadius = outerRadius
    }
    if abs(glassView.cornerRadius - resolvedRadius) > 0.01 {
      glassView.cornerRadius = resolvedRadius
    }
    if abs((contentClipView.layer?.cornerRadius ?? 0) - resolvedRadius) > 0.01 {
      contentClipView.layer?.cornerRadius = resolvedRadius
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shadowLayer.frame = NSRect(
      x: panelClipView.frame.minX + glassView.frame.minX,
      y: panelClipView.frame.minY + glassView.frame.minY,
      width: glassView.frame.width,
      height: glassView.frame.height
    )
    shadowLayer.shadowOpacity = Float(shadowOpacity)
    shadowLayer.shadowRadius = shadowRadius
    shadowLayer.shadowOffset = CGSize(width: 0, height: -shadowOffsetY)
    shadowLayer.shadowPath = CGPath(
      roundedRect: shadowLayer.bounds,
      cornerWidth: resolvedRadius,
      cornerHeight: resolvedRadius,
      transform: nil
    )
    CATransaction.commit()
  }

  private var resolvedShadowInsets: NSEdgeInsets {
    guard shadowOpacity > 0 else { return NSEdgeInsetsZero }
    let blurExtent = ceil(shadowRadius + 2)
    return NSEdgeInsets(
      top: max(0, ceil(blurExtent - shadowOffsetY)),
      left: blurExtent,
      bottom: max(0, ceil(blurExtent + shadowOffsetY)),
      right: blurExtent
    )
  }
}

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
  private weak var installedRootView: NSView?

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
      let hostView = SpotlightGlassHostView(frame: .zero)
      hostView.glassView.style = .clear
      hostView.glassView.tintColor = nil
      hostView.requestedCornerRadius = 24
      self.contentView = hostView
      // NSGlassEffectView supplies its own elevation. A second NSWindow shadow
      // creates a dirty double rim around the stronger regular style.
      self.hasShadow = false
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
    installedRootView = rootView
    rootView.autoresizingMask = [.width, .height]

    if #available(macOS 26.0, *), let hostView = contentView as? SpotlightGlassHostView {
      hostView.installContentView(rootView)
    } else {
      rootView.frame = contentView?.bounds ?? .zero
      contentView?.addSubview(rootView)
    }
  }

  func windowSize(forContentSize contentSize: NSSize) -> NSSize {
    if #available(macOS 26.0, *), let hostView = contentView as? SpotlightGlassHostView {
      let insets = hostView.contentInsets
      return NSSize(
        width: contentSize.width + insets.left + insets.right,
        height: contentSize.height + insets.top + insets.bottom
      )
    }
    return contentSize
  }

  var contentInsets: NSEdgeInsets {
    if #available(macOS 26.0, *), let hostView = contentView as? SpotlightGlassHostView {
      return hostView.contentInsets
    }
    return NSEdgeInsetsZero
  }

  func layoutInstalledRootView() {
    contentView?.layoutSubtreeIfNeeded()
    guard let installedRootView else { return }

    if #available(macOS 26.0, *), let hostView = contentView as? SpotlightGlassHostView {
      hostView.layoutSubtreeIfNeeded()
      hostView.layoutContentView(installedRootView)
    } else {
      installedRootView.frame = contentView?.bounds ?? .zero
    }
  }

  func snapshotImage() -> NSImage? {
    guard let contentView else { return nil }
    let bounds = contentView.bounds
    guard bounds.width > 0, bounds.height > 0 else { return nil }

    contentView.displayIfNeeded()
    guard let representation = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
      return nil
    }
    contentView.cacheDisplay(in: bounds, to: representation)

    let image = NSImage(size: bounds.size)
    image.addRepresentation(representation)
    return image
  }

  func applyGlassAppearance(
    style: String,
    cornerRadius: Double,
    tintHex: String?,
    tintOpacity: Double,
    shadowOpacity: Double,
    shadowRadius: Double,
    shadowOffsetY: Double
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

    if #available(macOS 26.0, *), let hostView = contentView as? SpotlightGlassHostView {
      let glassView = hostView.glassView
      glassView.style = style == "regular" ? .regular : .clear
      hostView.requestedCornerRadius = safeRadius
      hostView.applyShadowAppearance(
        opacity: CGFloat(shadowOpacity),
        radius: CGFloat(shadowRadius),
        offsetY: CGFloat(shadowOffsetY)
      )
      glassView.tintColor = tintColor
      hostView.needsLayout = true
      hostView.layoutSubtreeIfNeeded()
      glassView.needsDisplay = true
    } else if let effectView = contentView as? SpotlightFallbackBackgroundView {
      effectView.applyGlassAppearance(
        style: style,
        cornerRadius: safeRadius,
        tintColor: tintColor
      )
      effectView.needsDisplay = true
      invalidateShadow()
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
