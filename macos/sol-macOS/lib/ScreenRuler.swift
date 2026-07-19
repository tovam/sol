import Cocoa

final class ScreenRulerController: NSObject {
  static let shared = ScreenRulerController()

  private var panel: NSPanel?

  func toggle() {
    DispatchQueue.main.async {
      if self.panel != nil {
        self.hide()
      } else {
        self.show()
      }
    }
  }

  func hide() {
    panel?.orderOut(nil)
    panel = nil
  }

  private func show() {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
      ?? NSScreen.main
    guard let screen else { return }

    let rulerSize = NSSize(
      width: min(820, screen.visibleFrame.width * 0.82),
      height: 154
    )
    let origin = NSPoint(
      x: screen.visibleFrame.midX - rulerSize.width / 2,
      y: screen.visibleFrame.maxY - rulerSize.height - 72
    )
    let frame = NSRect(origin: origin, size: rulerSize)
    let rulerPanel = NSPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel, .resizable],
      backing: .buffered,
      defer: false
    )
    rulerPanel.level = .floating
    rulerPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    rulerPanel.isOpaque = false
    rulerPanel.backgroundColor = .clear
    rulerPanel.hasShadow = true
    rulerPanel.isReleasedWhenClosed = false
    rulerPanel.isMovableByWindowBackground = true
    rulerPanel.minSize = NSSize(width: 300, height: 140)
    rulerPanel.maxSize = NSSize(width: screen.frame.width, height: 190)

    let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: rulerSize))
    effectView.autoresizingMask = [.width, .height]
    effectView.material = .hudWindow
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    effectView.wantsLayer = true
    effectView.layer?.cornerRadius = 16
    effectView.layer?.cornerCurve = .continuous
    effectView.layer?.masksToBounds = true
    effectView.layer?.borderWidth = 0.5
    effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor

    let rulerView = ScreenRulerView(frame: effectView.bounds, screen: screen)
    rulerView.autoresizingMask = [.width, .height]
    effectView.addSubview(rulerView)
    rulerPanel.contentView = effectView
    rulerPanel.orderFrontRegardless()
    panel = rulerPanel
  }
}

private final class ScreenRulerView: NSView {
  private let scale: CGFloat
  private let pixelsPerCentimeter: CGFloat?

  init(frame frameRect: NSRect, screen: NSScreen) {
    scale = screen.backingScaleFactor
    pixelsPerCentimeter = Self.horizontalPixelsPerCentimeter(for: screen)
    super.init(frame: frameRect)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isOpaque: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    drawPointsTrack(baseline: 9)
    drawPixelsTrack(baseline: 51)
    drawCentimetersTrack(baseline: 93)

    let density = pixelsPerCentimeter.map { String(format: "%.1f px/cm", $0) }
      ?? "physical size unavailable"
    let hint = "1 logical px/pt = \(format(scale)) physical px · \(density) · drag · double-click to close" as NSString
    let hintSize = hint.size(withAttributes: [
      .font: NSFont.systemFont(ofSize: 10, weight: .regular)
    ])
    hint.draw(
      at: NSPoint(x: max(12, bounds.maxX - hintSize.width - 12), y: bounds.maxY - 18),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
    )
  }

  private func drawPointsTrack(baseline: CGFloat) {
    let maximum = max(0, Int(bounds.width))
    for point in stride(from: 0, through: maximum, by: 5) {
      drawTick(
        x: CGFloat(point), value: point, unit: "logical px/pt", baseline: baseline,
        isMajor: point % 50 == 0, isMedium: point % 10 == 0)
    }
  }

  private func drawPixelsTrack(baseline: CGFloat) {
    let maximum = max(0, Int(bounds.width * scale))
    for pixel in stride(from: 0, through: maximum, by: 10) {
      drawTick(
        x: CGFloat(pixel) / scale, value: pixel, unit: "physical px",
        baseline: baseline, isMajor: pixel % 100 == 0,
        isMedium: pixel % 50 == 0)
    }
  }

  private func drawCentimetersTrack(baseline: CGFloat) {
    guard let pixelsPerCentimeter else {
      let message = "cm unavailable for this display" as NSString
      message.draw(
        at: NSPoint(x: 8, y: baseline + 12),
        withAttributes: labelAttributes(color: .secondaryLabelColor))
      return
    }

    let pointsPerMillimeter = pixelsPerCentimeter / scale / 10
    guard pointsPerMillimeter > 0 else { return }
    let maximumMillimeters = Int(bounds.width / pointsPerMillimeter)
    for millimeter in 0...maximumMillimeters {
      let isCentimeter = millimeter % 10 == 0
      drawTick(
        x: CGFloat(millimeter) * pointsPerMillimeter,
        value: millimeter / 10, unit: "cm", baseline: baseline,
        isMajor: isCentimeter, isMedium: millimeter % 5 == 0,
        drawsLabel: isCentimeter)
    }
  }

  private func drawTick(
    x: CGFloat, value: Int, unit: String, baseline: CGFloat,
    isMajor: Bool, isMedium: Bool, drawsLabel: Bool? = nil
  ) {
    let alignedX = floor(x * scale) / scale + 0.5 / scale
    let tickHeight: CGFloat = isMajor ? 19 : (isMedium ? 12 : 7)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: alignedX, y: baseline))
    path.line(to: NSPoint(x: alignedX, y: baseline + tickHeight))
    path.lineWidth = isMajor ? 1.2 : 0.8
    (isMajor
      ? NSColor.labelColor.withAlphaComponent(0.82)
      : NSColor.secondaryLabelColor.withAlphaComponent(0.62)
    ).setStroke()
    path.stroke()

    if drawsLabel ?? isMajor {
      let text = value == 0 ? "0 \(unit)" : "\(value)"
      (text as NSString).draw(
        at: NSPoint(x: alignedX + 4, y: baseline + 21),
        withAttributes: labelAttributes(color: .labelColor))
    }
  }

  private func labelAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
    return [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
      .foregroundColor: color,
    ]
  }

  private func format(_ value: CGFloat) -> String {
    if value.rounded() == value {
      return String(Int(value))
    }
    return String(format: "%.2f", value)
  }

  private static func horizontalPixelsPerCentimeter(
    for screen: NSScreen
  ) -> CGFloat? {
    guard
      let number = screen.deviceDescription[
        NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    else {
      return nil
    }

    let displayID = CGDirectDisplayID(number.uint32Value)
    let millimeters = CGDisplayScreenSize(displayID).width
    let pixels = CGFloat(CGDisplayPixelsWide(displayID))
    guard millimeters > 0, pixels > 0 else { return nil }
    return pixels / (millimeters / 10)
  }

  override func mouseDown(with event: NSEvent) {
    if event.clickCount >= 2 {
      ScreenRulerController.shared.hide()
      return
    }
    window?.performDrag(with: event)
  }
}
