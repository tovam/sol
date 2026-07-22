import AppKit
import QuartzCore

enum PreferredScreen {
  case frontmost
  case withMouse
}

private enum PresentationPhase {
  case hidden
  case opening
  case visible
  case closing
}

private enum FrameAnimationCurve {
  case easeIn
  case easeOut
  case easeInOut
  case singleBounce(amount: CGFloat)

  func value(at progress: CGFloat) -> CGFloat {
    let t = min(max(progress, 0), 1)
    switch self {
    case .easeIn:
      return t * t * t
    case .easeOut:
      let inverse = 1 - t
      return 1 - inverse * inverse * inverse
    case .easeInOut:
      if t < 0.5 {
        return 4 * t * t * t
      }
      let inverse = -2 * t + 2
      return 1 - inverse * inverse * inverse / 2
    case let .singleBounce(amount):
      let safeAmount = max(0, amount)
      let smoothStep: (CGFloat) -> CGFloat = { value in
        value * value * (3 - 2 * value)
      }

      guard safeAmount > 0 else {
        return smoothStep(t)
      }

      // Progress above 1 interpolates past the target frame, making the
      // window slightly smaller. The second phase returns exactly to 1, so
      // the sequence is: larger -> smaller -> final, with no completion snap.
      let bouncePeak: CGFloat = 0.68
      if t <= bouncePeak {
        return (1 + safeAmount) * smoothStep(t / bouncePeak)
      }

      let reboundProgress = (t - bouncePeak) / (1 - bouncePeak)
      return 1 + safeAmount * (1 - smoothStep(reboundProgress))
    }
  }
}

private struct SearchWindowAnimationConfiguration {
  var openingWidthExtra: CGFloat = 50
  var openingHeightExtraPercent: CGFloat = 1.8
  var openingDuration: TimeInterval = 0.1
  var openingBounce: Double = 0.2
  var openingInitialOpacity: CGFloat = 0.62
  var closingWidthExtraPercent: CGFloat = 1.8
  var closingHeightExtraPercent: CGFloat = 1.2
  var closingDuration: TimeInterval = 0.085
  var resultsExpandDuration: TimeInterval = 0.24
  var resultsCollapseDuration: TimeInterval = 0.18
}

private struct GlassAppearanceConfiguration {
  var style = "clear"
  var cornerRadius = 24.0
  var tintHex: String?
  var tintOpacity = 0.0
  var shadowOpacity = 0.32
  var shadowRadius = 12.0
  var shadowOffsetY = 3.0

  func apply(to panel: Panel) {
    panel.applyGlassAppearance(
      style: style,
      cornerRadius: cornerRadius,
      tintHex: tintHex,
      tintOpacity: tintOpacity,
      shadowOpacity: shadowOpacity,
      shadowRadius: shadowRadius,
      shadowOffsetY: shadowOffsetY
    )
  }
}

private final class ClosingAnimationPanel: NSPanel {
  init(frame: NSRect, image: NSImage, sourceWindow: NSWindow) {
    super.init(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = true
    isMovable = false
    isReleasedWhenClosed = false
    animationBehavior = .none
    level = sourceWindow.level
    collectionBehavior = sourceWindow.collectionBehavior

    let imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
    imageView.image = image
    imageView.imageScaling = .scaleAxesIndependently
    imageView.autoresizingMask = [.width, .height]
    contentView = imageView
  }

  override var canBecomeKey: Bool {
    return false
  }

  override var canBecomeMain: Bool {
    return false
  }
}

@objc class PanelManager: NSObject {
  let baseSize = NSSize(width: 680, height: 450)
  public var preferredScreen: PreferredScreen = .frontmost
  private let mainWindow: Panel = Panel(contentRect: .zero)
  private var rootView: NSView?
  private var searchWindowPosition = NSPoint(x: 50, y: 20)
  private var currentContentSize = NSSize(width: 680, height: 64)
  private var presentationPhase: PresentationPhase = .hidden
  private var restingFrame: NSRect?
  private var pendingPresentationFrame: NSRect?
  private var frameAnimationTimer: Timer?
  private var frameAnimationGeneration = 0
  private var frameAnimationTarget: NSRect?
  private var closingAnimationWindow: ClosingAnimationPanel?
  private var searchWindowAnimation = SearchWindowAnimationConfiguration()
  private var glassAppearance = GlassAppearanceConfiguration()
  private var isInitialPresentationReady = false
  private var hasPendingShowRequest = false
  private var pendingShowTarget: String?

  @objc static public let shared = PanelManager()

  public func setRootView(_ rootView: NSView) {
    mainWindow.installRootView(rootView)
    self.rootView = rootView
    resizeForCurrentContentSize()
  }

  func setGlassAppearance(
    style: String,
    cornerRadius: Double,
    tintHex: String?,
    tintOpacity: Double,
    shadowOpacity: Double,
    shadowRadius: Double,
    shadowOffsetY: Double
  ) {
    glassAppearance = GlassAppearanceConfiguration(
      style: style,
      cornerRadius: cornerRadius,
      tintHex: tintHex,
      tintOpacity: tintOpacity,
      shadowOpacity: shadowOpacity,
      shadowRadius: shadowRadius,
      shadowOffsetY: shadowOffsetY
    )
    glassAppearance.apply(to: mainWindow)
    resizeForCurrentContentSize()
  }

  func applyCurrentGlassAppearance(to panel: Panel) {
    glassAppearance.apply(to: panel)
  }

  func setSearchWindowPosition(x: Double, y: Double) {
    searchWindowPosition = NSPoint(
      x: min(max(x, 0), 100),
      y: min(max(y, 0), 100)
    )

    guard let screen = getPreferredScreen() else {
      return
    }

    let targetSize = restingFrame?.size ?? mainWindow.frame.size
    let frame = NSRect(
      origin: positionedOrigin(for: targetSize, on: screen),
      size: targetSize
    )
    restingFrame = frame
    if presentationPhase == .opening || presentationPhase == .closing {
      pendingPresentationFrame = frame
      return
    }
    stopFrameAnimation()
    mainWindow.setFrame(frame, display: mainWindow.isVisible)
  }

  func setSearchWindowAnimation(
    openingWidthExtra: Double,
    openingHeightExtraPercent: Double,
    openingDurationMs: Double,
    openingBounce: Double,
    openingInitialOpacity: Double,
    closingWidthExtraPercent: Double,
    closingHeightExtraPercent: Double,
    closingDurationMs: Double,
    resultsExpandDurationMs: Double,
    resultsCollapseDurationMs: Double
  ) {
    searchWindowAnimation = SearchWindowAnimationConfiguration(
      openingWidthExtra: CGFloat(min(max(openingWidthExtra, 0), 200)),
      openingHeightExtraPercent: CGFloat(min(max(openingHeightExtraPercent, 0), 20)),
      openingDuration: min(max(openingDurationMs, 0), 1000) / 1000,
      openingBounce: min(max(openingBounce, 0), 1),
      openingInitialOpacity: CGFloat(min(max(openingInitialOpacity, 0), 1)),
      closingWidthExtraPercent: CGFloat(min(max(closingWidthExtraPercent, 0), 20)),
      closingHeightExtraPercent: CGFloat(min(max(closingHeightExtraPercent, 0), 20)),
      closingDuration: min(max(closingDurationMs, 0), 1000) / 1000,
      resultsExpandDuration: min(max(resultsExpandDurationMs, 0), 1000) / 1000,
      resultsCollapseDuration: min(max(resultsCollapseDurationMs, 0), 1000) / 1000
    )
  }

  private func positionedOrigin(for windowSize: NSSize, on screen: NSScreen) -> NSPoint {
    let visibleFrame = screen.visibleFrame
    let contentInsets = mainWindow.contentInsets
    let contentWidth = max(0, windowSize.width - contentInsets.left - contentInsets.right)
    let contentHeight = max(0, windowSize.height - contentInsets.top - contentInsets.bottom)
    let requestedCenterX =
      visibleFrame.minX + visibleFrame.width * searchWindowPosition.x / 100
    let requestedTopY =
      visibleFrame.maxY - visibleFrame.height * searchWindowPosition.y / 100
    let maximumX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
    let maximumY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height)

    return NSPoint(
      x: floor(
        min(
          max(requestedCenterX - contentWidth / 2 - contentInsets.left, visibleFrame.minX),
          maximumX
        )
      ),
      y: floor(
        min(
          max(requestedTopY - contentHeight - contentInsets.bottom, visibleFrame.minY),
          maximumY
        )
      )
    )
  }

  private func resizeForCurrentContentSize() {
    guard let screen = getPreferredScreen() else { return }
    let windowSize = mainWindow.windowSize(forContentSize: currentContentSize)
    let frame = NSRect(
      origin: positionedOrigin(for: windowSize, on: screen),
      size: windowSize
    )
    restingFrame = frame
    if presentationPhase == .opening || presentationPhase == .closing {
      pendingPresentationFrame = frame
      return
    }
    stopFrameAnimation()
    mainWindow.setFrame(frame, display: mainWindow.isVisible)
    mainWindow.layoutInstalledRootView()
  }

  @objc func markInitialPresentationReady() {
    guard !isInitialPresentationReady else { return }

    isInitialPresentationReady = true
    mainWindow.layoutInstalledRootView()

    guard hasPendingShowRequest else { return }
    let target = pendingShowTarget
    hasPendingShowRequest = false
    pendingShowTarget = nil
    showWindow(target: target)
  }

  @objc func showWindow(target: String? = nil) {
    HotKeyManager.shared.settingsHotKey.isPaused = false

    guard isInitialPresentationReady else {
      hasPendingShowRequest = true
      pendingShowTarget = target
      return
    }

    guard
      let screen =
        (preferredScreen == .frontmost ? getFrontmostScreen() : getScreenWithMouse())
    else {
      return
    }

    if presentationPhase == .visible || presentationPhase == .opening {
      mainWindow.makeKeyAndOrderFront(self)
      return
    }

    let wasClosing = presentationPhase == .closing
    let reopeningFrame = closingAnimationWindow?.frame
    let reopeningAlpha = closingAnimationWindow?.alphaValue
    stopFrameAnimation()
    dismissClosingAnimationWindow()
    pendingPresentationFrame = nil

    var finalFrame = restingFrame ?? mainWindow.frame
    finalFrame.origin = positionedOrigin(for: finalFrame.size, on: screen)
    restingFrame = finalFrame

    let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      && finalFrame.width > 1
      && finalFrame.height > 1
      && searchWindowAnimation.openingDuration > 0

    presentationPhase = .opening
    if wasClosing, let reopeningFrame, let reopeningAlpha {
      mainWindow.setFrame(reopeningFrame, display: false)
      mainWindow.alphaValue = reopeningAlpha
    } else {
      mainWindow.setFrame(openingFrame(around: finalFrame), display: false)
      mainWindow.alphaValue = shouldAnimate ? searchWindowAnimation.openingInitialOpacity : 1
    }
    mainWindow.setIsVisible(true)
    mainWindow.makeKeyAndOrderFront(self)
    mainWindow.displayIfNeeded()
    SolEmitter.sharedInstance.onShow(target: nil)

    guard shouldAnimate else {
      mainWindow.setFrame(finalFrame, display: true)
      mainWindow.alphaValue = 1
      mainWindow.layoutInstalledRootView()
      presentationPhase = .visible
      applyPendingPresentationFrame()
      return
    }

    // Let AppKit present the slightly larger initial frame once before the
    // contraction starts; otherwise both states can be coalesced in one draw.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.presentationPhase == .opening else { return }
      self.animateFrame(
        to: finalFrame,
        alpha: 1,
        duration: self.searchWindowAnimation.openingDuration,
        curve: .singleBounce(
          amount: CGFloat(self.searchWindowAnimation.openingBounce)
        )
      ) { [weak self] in
        guard let self, self.presentationPhase == .opening else { return }
        self.presentationPhase = .visible
        self.applyPendingPresentationFrame()
      }
    }
  }

  @objc func hideWindow() {
    guard presentationPhase != .hidden, presentationPhase != .closing else {
      return
    }

    let wasOpening = presentationPhase == .opening
    stopFrameAnimation()
    presentationPhase = .closing
    pendingPresentationFrame = nil
    HotKeyManager.shared.settingsHotKey.isPaused = true

    let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      && mainWindow.frame.width > 1
      && mainWindow.frame.height > 1
      && searchWindowAnimation.closingDuration > 0
    guard shouldAnimate else {
      finishHiding()
      return
    }

    let closingBaseFrame = wasOpening ? (restingFrame ?? mainWindow.frame) : mainWindow.frame
    guard let snapshot = mainWindow.snapshotImage() else {
      finishHiding()
      return
    }

    let animationWindow = ClosingAnimationPanel(
      frame: mainWindow.frame,
      image: snapshot,
      sourceWindow: mainWindow
    )
    animationWindow.alphaValue = mainWindow.alphaValue
    closingAnimationWindow = animationWindow
    animationWindow.orderFrontRegardless()

    // Relinquish key status immediately. The remaining animation is a
    // non-key, mouse-transparent bitmap and cannot capture keyboard input.
    mainWindow.setIsVisible(false)
    mainWindow.alphaValue = 1
    animateFrame(
      to: closingFrame(around: closingBaseFrame),
      alpha: 0,
      duration: searchWindowAnimation.closingDuration,
      curve: .easeIn,
      window: animationWindow
    ) { [weak self] in
      guard let self, self.presentationPhase == .closing else { return }
      self.finishHiding()
    }
  }

  private func finishHiding() {
    stopFrameAnimation()
    dismissClosingAnimationWindow()
    mainWindow.setIsVisible(false)
    mainWindow.alphaValue = 1
    presentationPhase = .hidden
    pendingPresentationFrame = nil
    SolEmitter.sharedInstance.onHide()
  }

  private func dismissClosingAnimationWindow() {
    closingAnimationWindow?.orderOut(self)
    closingAnimationWindow = nil
  }

  private func openingFrame(around frame: NSRect) -> NSRect {
    let width = frame.width + searchWindowAnimation.openingWidthExtra
    let height = frame.height * (1 + searchWindowAnimation.openingHeightExtraPercent / 100)
    return NSRect(
      x: frame.midX - width / 2,
      y: frame.midY - height / 2,
      width: width,
      height: height
    )
  }

  private func closingFrame(around frame: NSRect) -> NSRect {
    return scaledFrame(
      frame,
      widthScale: 1 + searchWindowAnimation.closingWidthExtraPercent / 100,
      heightScale: 1 + searchWindowAnimation.closingHeightExtraPercent / 100
    )
  }

  private func scaledFrame(
    _ frame: NSRect,
    widthScale: CGFloat,
    heightScale: CGFloat
  ) -> NSRect {
    let size = NSSize(
      width: frame.width * widthScale,
      height: frame.height * heightScale
    )
    return NSRect(
      x: frame.midX - size.width / 2,
      y: frame.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }

  private func animateFrame(
    to targetFrame: NSRect,
    alpha targetAlpha: CGFloat,
    duration: TimeInterval,
    curve: FrameAnimationCurve,
    window: NSWindow? = nil,
    completion: @escaping () -> Void
  ) {
    stopFrameAnimation()
    let animatedWindow = window ?? mainWindow

    guard duration > 0 else {
      animatedWindow.setFrame(targetFrame, display: true)
      animatedWindow.alphaValue = targetAlpha
      if animatedWindow === mainWindow {
        mainWindow.layoutInstalledRootView()
      }
      completion()
      return
    }

    let startFrame = animatedWindow.frame
    let startAlpha = animatedWindow.alphaValue
    let startTime = CACurrentMediaTime()
    frameAnimationTarget = targetFrame
    frameAnimationGeneration += 1
    let generation = frameAnimationGeneration

    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
      guard let self, self.frameAnimationGeneration == generation else {
        timer.invalidate()
        return
      }

      let elapsed = CACurrentMediaTime() - startTime
      let rawProgress = CGFloat(min(max(elapsed / duration, 0), 1))
      let progress = curve.value(at: rawProgress)
      let frame = self.interpolatedFrame(from: startFrame, to: targetFrame, progress: progress)
      let alphaProgress = min(max(progress, 0), 1)
      animatedWindow.setFrame(frame, display: true)
      animatedWindow.alphaValue = startAlpha + (targetAlpha - startAlpha) * alphaProgress
      if animatedWindow === self.mainWindow {
        self.mainWindow.layoutInstalledRootView()
      }

      guard rawProgress >= 1 else { return }
      timer.invalidate()
      if self.frameAnimationTimer === timer {
        self.frameAnimationTimer = nil
      }
      self.frameAnimationTarget = nil
      animatedWindow.setFrame(targetFrame, display: true)
      animatedWindow.alphaValue = targetAlpha
      if animatedWindow === self.mainWindow {
        self.mainWindow.layoutInstalledRootView()
      }
      completion()
    }

    frameAnimationTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func stopFrameAnimation() {
    frameAnimationGeneration += 1
    frameAnimationTimer?.invalidate()
    frameAnimationTimer = nil
    frameAnimationTarget = nil
  }

  private func interpolatedFrame(
    from start: NSRect,
    to target: NSRect,
    progress: CGFloat
  ) -> NSRect {
    return NSRect(
      x: start.origin.x + (target.origin.x - start.origin.x) * progress,
      y: start.origin.y + (target.origin.y - start.origin.y) * progress,
      width: start.width + (target.width - start.width) * progress,
      height: start.height + (target.height - start.height) * progress
    )
  }

  private func applyPendingPresentationFrame() {
    guard let frame = pendingPresentationFrame else { return }
    pendingPresentationFrame = nil
    guard let screen = getPreferredScreen() else { return }
    setSearchFrame(frame, on: screen)
  }

  @objc func resetSize() {
    currentContentSize = baseSize
    let size = mainWindow.windowSize(forContentSize: baseSize)
    let origin = getPreferredScreen().map { positionedOrigin(for: size, on: $0) } ?? .zero
    let frame = NSRect(origin: origin, size: size)
    restingFrame = frame
    if presentationPhase == .opening || presentationPhase == .closing {
      pendingPresentationFrame = frame
      return
    }
    stopFrameAnimation()
    mainWindow.setFrame(frame, display: false)
    mainWindow.layoutInstalledRootView()
  }

  @objc func setHeight(_ height: Int) {
    var finalHeight = height
    if height == 0 {
      finalHeight = Int(baseSize.height)
    }

    let contentSize = NSSize(width: Int(baseSize.width), height: finalHeight)
    currentContentSize = contentSize
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
    restingFrame = frame
    if presentationPhase == .opening || presentationPhase == .closing {
      pendingPresentationFrame = frame
      return
    }
    setSearchFrame(frame, on: screen)
  }

  private func setSearchFrame(_ frame: NSRect, on screen: NSScreen) {
    if let frameAnimationTarget, framesAreNearlyEqual(frameAnimationTarget, frame) {
      return
    }

    let currentFrame = mainWindow.frame
    if framesAreNearlyEqual(currentFrame, frame) {
      stopFrameAnimation()
      mainWindow.setFrame(frame, display: mainWindow.isVisible)
      mainWindow.layoutInstalledRootView()
      return
    }

    let staysOnSameScreen = mainWindow.screen.map {
      framesAreNearlyEqual($0.frame, screen.frame)
    } ?? false
    let shouldAnimate = presentationPhase == .visible
      && mainWindow.isVisible
      && staysOnSameScreen
      && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    guard shouldAnimate else {
      stopFrameAnimation()
      mainWindow.setFrame(frame, display: mainWindow.isVisible)
      mainWindow.layoutInstalledRootView()
      return
    }

    let isExpanding = frame.height > currentFrame.height
    let duration = isExpanding
      ? searchWindowAnimation.resultsExpandDuration
      : searchWindowAnimation.resultsCollapseDuration

    guard duration > 0 else {
      stopFrameAnimation()
      mainWindow.setFrame(frame, display: mainWindow.isVisible)
      mainWindow.layoutInstalledRootView()
      return
    }

    animateFrame(
      to: frame,
      alpha: mainWindow.alphaValue,
      duration: duration,
      curve: .easeInOut
    ) {}
  }

  private func framesAreNearlyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
    return abs(lhs.minX - rhs.minX) < 0.5
      && abs(lhs.minY - rhs.minY) < 0.5
      && abs(lhs.width - rhs.width) < 0.5
      && abs(lhs.height - rhs.height) < 0.5
  }

  @objc func setRelativeSize(_ proportion: Double) {
    guard let screenSize = NSScreen.main?.frame.size else {
      return
    }

    let contentSize = CGSize(
      width: screenSize.width * CGFloat(proportion),
      height: screenSize.height * CGFloat(proportion)
    )
    currentContentSize = contentSize
    let size = mainWindow.windowSize(forContentSize: contentSize)
    let origin = getPreferredScreen().map { positionedOrigin(for: size, on: $0) } ?? .zero

    let frame = NSRect(origin: origin, size: size)
    restingFrame = frame
    if presentationPhase == .opening || presentationPhase == .closing {
      pendingPresentationFrame = frame
      return
    }
    stopFrameAnimation()
    mainWindow.setFrame(frame, display: false)
    mainWindow.layoutInstalledRootView()
  }

  func toggle() {
    if presentationPhase == .visible || presentationPhase == .opening {
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
