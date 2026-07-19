enum PreferredScreen {
  case frontmost
  case withMouse
}

@objc class PanelManager: NSObject {
  let baseSize = NSSize(width: 680, height: 450)
  public var preferredScreen: PreferredScreen = .frontmost
  private let mainWindow: Panel = Panel(contentRect: .zero)
  private var rootView: NSView?

  @objc static public let shared = PanelManager()

  public func setRootView(_ rootView: NSView) {
    mainWindow.installRootView(rootView)
    self.rootView = rootView
  }

  func setGlassAppearance(
    style: String,
    cornerRadius: Double,
    tintHex: String?,
    tintOpacity: Double
  ) {
    mainWindow.applyGlassAppearance(
      style: style,
      cornerRadius: cornerRadius,
      tintHex: tintHex,
      tintOpacity: tintOpacity
    )
  }

  @objc func showWindow(target: String? = nil) {
    HotKeyManager.shared.settingsHotKey.isPaused = false

    guard
      let screen =
        (preferredScreen == .frontmost ? getFrontmostScreen() : getScreenWithMouse())
    else {
      return
    }

    let yOffset = screen.visibleFrame.height * 0.3
    let x = screen.visibleFrame.midX - mainWindow.frame.width / 2
    let y = screen.visibleFrame.midY - mainWindow.frame.height + yOffset
    mainWindow.setFrameOrigin(NSPoint(x: floor(x), y: floor(y)))

    mainWindow.setIsVisible(true)

    mainWindow.makeKeyAndOrderFront(self)

    SolEmitter.sharedInstance.onShow(target: nil)
  }

  @objc func hideWindow() {
    mainWindow.setIsVisible(false)
    SolEmitter.sharedInstance.onHide()
    HotKeyManager.shared.settingsHotKey.isPaused = true
  }

  @objc func resetSize() {
    let origin = CGPoint(x: 0, y: 0)
    let size = mainWindow.windowSize(forContentSize: baseSize)
    let frame = NSRect(origin: origin, size: size)
    mainWindow.setFrame(frame, display: false)
    mainWindow.layoutInstalledRootView()
    mainWindow.center()
  }

  @objc func setHeight(_ height: Int) {
    var finalHeight = height
    if height == 0 {
      finalHeight = Int(baseSize.height)
    }

    let contentSize = NSSize(width: Int(baseSize.width), height: finalHeight)
    let windowSize = mainWindow.windowSize(forContentSize: contentSize)
    guard
      let screen =
        (preferredScreen == .frontmost ? getFrontmostScreen() : getScreenWithMouse())
    else {
      return
    }

    let yOffset = screen.visibleFrame.height * 0.3
    let y = floor(screen.visibleFrame.midY - windowSize.height + yOffset)

    let frame = NSRect(
      x: mainWindow.frame.minX,
      y: y,
      width: windowSize.width,
      height: windowSize.height
    )
    self.mainWindow.setFrame(frame, display: true)
    self.mainWindow.layoutInstalledRootView()
  }

  @objc func setRelativeSize(_ proportion: Double) {
    guard let screenSize = NSScreen.main?.frame.size else {
      return
    }

    let origin = CGPoint(x: 0, y: 0)
    let contentSize = CGSize(
      width: screenSize.width * CGFloat(proportion),
      height: screenSize.height * CGFloat(proportion)
    )
    let size = mainWindow.windowSize(forContentSize: contentSize)

    let frame = NSRect(origin: origin, size: size)
    mainWindow.setFrame(frame, display: false)
    mainWindow.layoutInstalledRootView()
    mainWindow.center()
  }

  func toggle() {
    if mainWindow.isVisible {
      hideWindow()
    } else {
      showWindow()
    }
  }

  func setPreferredScreen(_ preferredScreen: PreferredScreen) {
    self.preferredScreen = preferredScreen
  }

  func getPreferredScreen() -> NSScreen? {
    return self.preferredScreen == .frontmost ? getFrontmostScreen() : getScreenWithMouse()
  }

  func getFrontmostScreen() -> NSScreen? {
    return mainWindow.screen ?? NSScreen.main
  }

}
