enum PreferredScreen {
  case frontmost
  case withMouse
}

@objc class PanelManager: NSObject {
  let baseSize = NSSize(width: 680, height: 450)
  public var preferredScreen: PreferredScreen = .frontmost
  private let mainWindow: Panel = Panel(contentRect: .zero)
  private var rootView: NSView?
  private var searchWindowPosition = NSPoint(x: 50, y: 20)

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

  func setSearchWindowPosition(x: Double, y: Double) {
    searchWindowPosition = NSPoint(
      x: min(max(x, 0), 100),
      y: min(max(y, 0), 100)
    )

    guard mainWindow.isVisible, let screen = getPreferredScreen() else {
      return
    }

    mainWindow.setFrameOrigin(positionedOrigin(for: mainWindow.frame.size, on: screen))
  }

  private func positionedOrigin(for windowSize: NSSize, on screen: NSScreen) -> NSPoint {
    let visibleFrame = screen.visibleFrame
    let requestedCenterX =
      visibleFrame.minX + visibleFrame.width * searchWindowPosition.x / 100
    let requestedTopY =
      visibleFrame.maxY - visibleFrame.height * searchWindowPosition.y / 100
    let maximumX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
    let maximumY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height)

    return NSPoint(
      x: floor(min(max(requestedCenterX - windowSize.width / 2, visibleFrame.minX), maximumX)),
      y: floor(min(max(requestedTopY - windowSize.height, visibleFrame.minY), maximumY))
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

    mainWindow.setFrameOrigin(positionedOrigin(for: mainWindow.frame.size, on: screen))

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
    let size = mainWindow.windowSize(forContentSize: baseSize)
    let origin = getPreferredScreen().map { positionedOrigin(for: size, on: $0) } ?? .zero
    let frame = NSRect(origin: origin, size: size)
    mainWindow.setFrame(frame, display: false)
    mainWindow.layoutInstalledRootView()
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

    let frame = NSRect(
      origin: positionedOrigin(for: windowSize, on: screen),
      size: windowSize
    )
    self.mainWindow.setFrame(frame, display: true)
    self.mainWindow.layoutInstalledRootView()
  }

  @objc func setRelativeSize(_ proportion: Double) {
    guard let screenSize = NSScreen.main?.frame.size else {
      return
    }

    let contentSize = CGSize(
      width: screenSize.width * CGFloat(proportion),
      height: screenSize.height * CGFloat(proportion)
    )
    let size = mainWindow.windowSize(forContentSize: contentSize)
    let origin = getPreferredScreen().map { positionedOrigin(for: size, on: $0) } ?? .zero

    let frame = NSRect(origin: origin, size: size)
    mainWindow.setFrame(frame, display: false)
    mainWindow.layoutInstalledRootView()
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
