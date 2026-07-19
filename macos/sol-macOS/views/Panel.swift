import Foundation

let appDelegate = NSApp.delegate as? AppDelegate

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
    self.delegate = self
    self.backgroundColor = .clear

    if #available(macOS 11.0, *) {
      self.titlebarSeparatorStyle = .none
    }

    let effectView = NSVisualEffectView(
      frame: .zero
    )
    effectView.autoresizingMask = [.width, .height]
    effectView.material = .popover
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    effectView.wantsLayer = true
    effectView.layer?.cornerRadius = 16
    effectView.layer?.cornerCurve = .continuous
    effectView.layer?.masksToBounds = true
    effectView.layer?.borderWidth = 0.5
    effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor

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
