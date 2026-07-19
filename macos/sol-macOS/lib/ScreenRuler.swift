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
      height: 82
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
    rulerPanel.minSize = NSSize(width: 300, height: 72)
    rulerPanel.maxSize = NSSize(width: screen.frame.width, height: 120)

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

    let rulerView = ScreenRulerView(frame: effectView.bounds)
    rulerView.autoresizingMask = [.width, .height]
    effectView.addSubview(rulerView)
    rulerPanel.contentView = effectView
    rulerPanel.orderFrontRegardless()
    panel = rulerPanel
  }
}

private final class ScreenRulerView: NSView {
  override var isOpaque: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let scale = window?.backingScaleFactor ?? 1
    let baseline: CGFloat = 13
    let tickColor = NSColor.labelColor.withAlphaComponent(0.82)
    let minorTickColor = NSColor.secondaryLabelColor.withAlphaComponent(0.68)
    let path = NSBezierPath()

    for point in stride(from: 0, through: max(0, Int(bounds.width)), by: 5) {
      let x = CGFloat(point) + 0.5
      let isMajor = point % 50 == 0
      let isMedium = point % 10 == 0
      let tickHeight: CGFloat = isMajor ? 25 : (isMedium ? 15 : 8)
      (isMajor ? tickColor : minorTickColor).setStroke()
      path.removeAllPoints()
      path.move(to: NSPoint(x: x, y: baseline))
      path.line(to: NSPoint(x: x, y: baseline + tickHeight))
      path.lineWidth = isMajor ? 1.2 : 0.8
      path.stroke()

      if isMajor {
        let label = "\(point)" as NSString
        label.draw(
          at: NSPoint(x: x + 4, y: baseline + 28),
          withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.labelColor,
          ]
        )
      }
    }

    let hint = "points · \(Int(scale))× Retina · drag · double-click to close" as NSString
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

  override func mouseDown(with event: NSEvent) {
    if event.clickCount >= 2 {
      ScreenRulerController.shared.hide()
      return
    }
    window?.performDrag(with: event)
  }
}
