import AppKit
import WebKit

private let dailymotionBridgeName = "solDailymotion"

private final class FloatingVideoPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

private struct DailymotionPlayerSource {
  enum Backend {
    case sdk(playerID: String)
    case embeddedPage
  }

  let url: URL
  let videoID: String
  let backend: Backend
  let startsMuted: Bool

  static func parse(_ urlString: String) -> DailymotionPlayerSource? {
    guard
      let url = URL(string: urlString),
      url.scheme == "https",
      let host = url.host?.lowercased()
    else {
      return nil
    }

    let components = url.path.split(separator: "/")
    let queryItems = URLComponents(
      url: url,
      resolvingAgainstBaseURL: false
    )?.queryItems
    let startsMuted = queryItems?
      .first(where: { $0.name.lowercased() == "mute" })?
      .value
      .map { ["1", "true", "yes"].contains($0.lowercased()) }
      ?? false

    if host == "www.dailymotion.com" {
      guard
        components.count == 3,
        components[0] == "embed",
        components[1] == "video"
      else {
        return nil
      }
      let videoID = String(components[2])
      guard isVideoID(videoID) else { return nil }
      return DailymotionPlayerSource(
        url: url,
        videoID: videoID,
        backend: .embeddedPage,
        startsMuted: startsMuted
      )
    }

    if host == "geo.dailymotion.com" {
      guard
        components.count == 2,
        components[0] == "player"
      else {
        return nil
      }
      let playerFile = String(components[1])
      guard playerFile.hasSuffix(".html") else { return nil }
      let playerID = String(playerFile.dropLast(5))
      guard
        isPlayerID(playerID),
        let videoID = queryItems?
          .first(where: { $0.name == "video" })?
          .value,
        isVideoID(videoID)
      else {
        return nil
      }
      return DailymotionPlayerSource(
        url: url,
        videoID: videoID,
        backend: .sdk(playerID: playerID),
        startsMuted: startsMuted
      )
    }

    return nil
  }

  private static func isVideoID(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber }
  }

  private static func isPlayerID(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy {
      $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-"
    }
  }
}

private struct DailymotionBridgeState {
  var backend = "loading"
  var ready = false
  var isPlaying = false
  var isBuffering = false
  var isMuted = false
  var currentTime = 0.0
  var duration: Double?
  var seekableStart: Double?
  var seekableEnd: Double?
  var playbackRate = 1.0
  var volume = 1.0
  var isAdPlaying = false
  var adTime = 0.0
  var adDuration: Double?
  var error: String?
}

private protocol DailymotionControlsViewDelegate: AnyObject {
  func controlsDidTogglePlayback(_ controls: DailymotionControlsView)
  func controls(_ controls: DailymotionControlsView, seekBy seconds: Double)
  func controls(_ controls: DailymotionControlsView, seekTo seconds: Double)
  func controlsDidRequestLiveEdge(_ controls: DailymotionControlsView)
  func controls(_ controls: DailymotionControlsView, didSelectRate rate: Double)
  func controls(_ controls: DailymotionControlsView, didSetVolume volume: Double)
}

private final class DailymotionTrackingSlider: NSSlider {
  private(set) var isUserTracking = false

  override func mouseDown(with event: NSEvent) {
    isUserTracking = true
    super.mouseDown(with: event)
    isUserTracking = false
  }
}

private final class DailymotionControlsView: NSVisualEffectView {
  weak var delegate: DailymotionControlsViewDelegate?

  private let playButton = NSButton()
  private let backwardButton = NSButton(title: "−10", target: nil, action: nil)
  private let forwardButton = NSButton(title: "+10", target: nil, action: nil)
  private let seekSlider = DailymotionTrackingSlider(
    value: 0,
    minValue: 0,
    maxValue: 1,
    target: nil,
    action: nil
  )
  private let timeLabel = NSTextField(labelWithString: "Loading…")
  private let liveButton = NSButton(title: "LIVE", target: nil, action: nil)
  private let ratePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
  private let volumeImage = NSImageView()
  private let volumeSlider = DailymotionTrackingSlider(
    value: 1,
    minValue: 0,
    maxValue: 1,
    target: nil,
    action: nil
  )
  private let rates = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    material = .hudWindow
    blendingMode = .withinWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = 11
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.borderWidth = 0.5
    layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

    configureButton(
      playButton,
      action: #selector(togglePlayback),
      toolTip: "Play or pause"
    )
    configureButton(
      backwardButton,
      action: #selector(skipBackward),
      toolTip: "Back 10 seconds"
    )
    configureButton(
      forwardButton,
      action: #selector(skipForward),
      toolTip: "Forward 10 seconds"
    )
    configureButton(
      liveButton,
      action: #selector(goLive),
      toolTip: "Return to live"
    )
    liveButton.contentTintColor = .systemRed
    liveButton.isHidden = true

    seekSlider.target = self
    seekSlider.action = #selector(seek)
    seekSlider.isContinuous = false
    seekSlider.controlSize = .small
    seekSlider.toolTip = "Playback position"

    ratePopUp.addItems(withTitles: rates.map(rateTitle))
    ratePopUp.selectItem(at: 3)
    ratePopUp.target = self
    ratePopUp.action = #selector(changeRate)
    ratePopUp.controlSize = .small
    ratePopUp.toolTip = "Playback speed"

    volumeImage.image = NSImage(
      systemSymbolName: "speaker.wave.2.fill",
      accessibilityDescription: "Volume"
    )
    volumeImage.contentTintColor = .secondaryLabelColor
    volumeImage.imageScaling = .scaleProportionallyDown

    volumeSlider.target = self
    volumeSlider.action = #selector(changeVolume)
    volumeSlider.isContinuous = false
    volumeSlider.controlSize = .small
    volumeSlider.toolTip = "Volume"

    timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    timeLabel.textColor = .secondaryLabelColor
    timeLabel.alignment = .center
    timeLabel.lineBreakMode = .byClipping

    let stack = NSStackView(views: [
      playButton,
      backwardButton,
      forwardButton,
      seekSlider,
      timeLabel,
      liveButton,
      ratePopUp,
      volumeImage,
      volumeSlider,
    ])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.distribution = .fill
    stack.spacing = 6
    stack.detachesHiddenViews = true
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    seekSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
    seekSlider.setContentCompressionResistancePriority(
      .defaultLow,
      for: .horizontal
    )
    timeLabel.setContentCompressionResistancePriority(
      .required,
      for: .horizontal
    )

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
      playButton.widthAnchor.constraint(equalToConstant: 28),
      backwardButton.widthAnchor.constraint(equalToConstant: 36),
      forwardButton.widthAnchor.constraint(equalToConstant: 36),
      seekSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
      timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
      liveButton.widthAnchor.constraint(equalToConstant: 46),
      ratePopUp.widthAnchor.constraint(equalToConstant: 56),
      volumeImage.widthAnchor.constraint(equalToConstant: 16),
      volumeSlider.widthAnchor.constraint(equalToConstant: 45),
    ])

    render(DailymotionBridgeState())
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func render(_ state: DailymotionBridgeState) {
    let ready = state.ready && state.error == nil
    setPlaySymbol(state.isPlaying ? "pause.fill" : "play.fill")
    selectNearestRate(to: state.playbackRate)
    if !volumeSlider.isUserTracking {
      volumeSlider.doubleValue = state.isMuted
        ? 0
        : clamped(state.volume, lower: 0, upper: 1)
    }
    setVolumeSymbol(muted: state.isMuted, volume: state.volume)

    playButton.isEnabled = ready
    volumeSlider.isEnabled = ready
    liveButton.isHidden = true

    if state.isAdPlaying {
      let duration = state.adDuration ?? 0
      setTimeline(
        start: 0,
        end: max(duration, 1),
        position: state.adTime,
        enabled: false
      )
      backwardButton.isEnabled = false
      forwardButton.isEnabled = false
      ratePopUp.isEnabled = false
      timeLabel.textColor = .systemOrange
      timeLabel.stringValue = duration > 0
        ? "AD · \(formatTime(state.adTime)) / \(formatTime(duration))"
        : "AD"
      return
    }

    guard ready else {
      setTimeline(start: 0, end: 1, position: 0, enabled: false)
      backwardButton.isEnabled = false
      forwardButton.isEnabled = false
      ratePopUp.isEnabled = false
      timeLabel.textColor = state.error == nil ? .secondaryLabelColor : .systemRed
      timeLabel.stringValue = state.error == nil ? "Loading…" : "Unavailable"
      return
    }

    ratePopUp.isEnabled = true
    timeLabel.textColor = .secondaryLabelColor
    guard let duration = state.duration, duration > 0 else {
      setTimeline(start: 0, end: 1, position: 0, enabled: false)
      backwardButton.isEnabled = false
      forwardButton.isEnabled = false
      timeLabel.stringValue = state.isBuffering ? "Buffering…" : "Playing"
      return
    }

    setTimeline(
      start: 0,
      end: duration,
      position: state.currentTime,
      enabled: true
    )
    backwardButton.isEnabled = true
    forwardButton.isEnabled = true
    timeLabel.stringValue = "\(formatTime(state.currentTime)) / \(formatTime(duration))"
  }

  private func configureButton(
    _ button: NSButton,
    action: Selector,
    toolTip: String
  ) {
    button.target = self
    button.action = action
    button.bezelStyle = .texturedRounded
    button.controlSize = .small
    button.font = .systemFont(ofSize: 11, weight: .medium)
    button.toolTip = toolTip
  }

  private func setTimeline(
    start: Double,
    end: Double,
    position: Double,
    enabled: Bool
  ) {
    let safeStart = start.isFinite ? start : 0
    let safeEnd = end.isFinite ? max(end, safeStart + 0.001) : safeStart + 1
    seekSlider.minValue = safeStart
    seekSlider.maxValue = safeEnd
    if !seekSlider.isUserTracking {
      seekSlider.doubleValue = clamped(
        position,
        lower: safeStart,
        upper: safeEnd
      )
    }
    seekSlider.isEnabled = enabled
  }

  private func setVolumeSymbol(muted: Bool, volume: Double) {
    let symbol: String
    if muted || volume <= 0 {
      symbol = "speaker.slash.fill"
    } else if volume < 0.35 {
      symbol = "speaker.wave.1.fill"
    } else {
      symbol = "speaker.wave.2.fill"
    }
    volumeImage.image = NSImage(
      systemSymbolName: symbol,
      accessibilityDescription: muted ? "Muted" : "Volume"
    )
  }

  private func setPlaySymbol(_ name: String) {
    if let image = NSImage(
      systemSymbolName: name,
      accessibilityDescription: name == "pause.fill" ? "Pause" : "Play"
    ) {
      playButton.image = image
      playButton.title = ""
    } else {
      playButton.image = nil
      playButton.title = name == "pause.fill" ? "Ⅱ" : "▶"
    }
  }

  private func selectNearestRate(to rate: Double) {
    guard
      let index = rates.indices.min(by: {
        abs(rates[$0] - rate) < abs(rates[$1] - rate)
      })
    else {
      return
    }
    ratePopUp.selectItem(at: index)
  }

  private func rateTitle(_ rate: Double) -> String {
    rate == rate.rounded() ? "\(Int(rate))×" : "\(rate)×"
  }

  private func formatTime(_ seconds: Double) -> String {
    let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
    let hours = total / 3600
    let minutes = total % 3600 / 60
    let remainingSeconds = total % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
      : String(format: "%d:%02d", minutes, remainingSeconds)
  }

  private func clamped(
    _ value: Double,
    lower: Double,
    upper: Double
  ) -> Double {
    min(max(value.isFinite ? value : lower, lower), upper)
  }

  @objc private func togglePlayback() {
    delegate?.controlsDidTogglePlayback(self)
  }

  @objc private func skipBackward() {
    delegate?.controls(self, seekBy: -10)
  }

  @objc private func skipForward() {
    delegate?.controls(self, seekBy: 10)
  }

  @objc private func seek() {
    guard seekSlider.isEnabled else { return }
    delegate?.controls(self, seekTo: seekSlider.doubleValue)
  }

  @objc private func goLive() {
    delegate?.controlsDidRequestLiveEdge(self)
  }

  @objc private func changeRate() {
    let index = ratePopUp.indexOfSelectedItem
    guard rates.indices.contains(index) else { return }
    delegate?.controls(self, didSelectRate: rates[index])
  }

  @objc private func changeVolume() {
    setVolumeSymbol(
      muted: volumeSlider.doubleValue <= 0,
      volume: volumeSlider.doubleValue
    )
    delegate?.controls(self, didSetVolume: volumeSlider.doubleValue)
  }
}

final class DailymotionPlayerController: NSObject, NSWindowDelegate {
  static let shared = DailymotionPlayerController()

  private var panel: FloatingVideoPanel?
  private var webView: WKWebView?
  private var controlsView: DailymotionControlsView?
  private var userContentController: WKUserContentController?
  private var source: DailymotionPlayerSource?
  private var sessionID = ""
  private var mediaFrame: WKFrameInfo?
  private var mediaFrameToken: String?
  private var mediaFrameIsMain = false
  private var mediaFrameIsPlaying = false
  private var mediaFrameArea = 0.0
  private var mediaFrameLastSeen = Date.distantPast
  private var sdkFallbackWorkItem: DispatchWorkItem?
  private var sdkFallbackDidStart = false
  private var state = DailymotionBridgeState()

  func open(urlString: String, completion: @escaping (Bool) -> Void) {
    guard let source = DailymotionPlayerSource.parse(urlString) else {
      completion(false)
      return
    }

    DispatchQueue.main.async {
      let player = self.playerWindow()
      self.load(source, in: player)
      player.title = "Dailymotion"
      player.makeKeyAndOrderFront(nil)
      player.orderFrontRegardless()
      completion(player.isVisible)
    }
  }

  func windowWillClose(_ notification: Notification) {
    teardownWebView()
    source = nil
    panel = nil
    state = DailymotionBridgeState()
  }

  private func playerWindow() -> FloatingVideoPanel {
    if let panel {
      return panel
    }

    let panel = FloatingVideoPanel(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    panel.delegate = self
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.hasShadow = true
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.minSize = NSSize(width: 480, height: 270)
    panel.aspectRatio = NSSize(width: 16, height: 9)
    panel.center()

    self.panel = panel
    return panel
  }

  private func load(
    _ source: DailymotionPlayerSource,
    in panel: FloatingVideoPanel
  ) {
    teardownWebView()

    self.source = source
    sessionID = UUID().uuidString
    mediaFrame = nil
    mediaFrameToken = nil
    mediaFrameIsMain = false
    mediaFrameIsPlaying = false
    mediaFrameArea = 0
    mediaFrameLastSeen = .distantPast
    sdkFallbackDidStart = false
    state = DailymotionBridgeState()

    let contentController = WKUserContentController()
    contentController.add(self, name: dailymotionBridgeName)
    contentController.addUserScript(
      WKUserScript(
        source: mediaBridgeScript(sessionID: sessionID),
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: false
      )
    )

    let configuration = WKWebViewConfiguration()
    configuration.userContentController = contentController
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.allowsAirPlayForMediaPlayback = true
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

    let webView = WKWebView(frame: panel.contentView?.bounds ?? .zero, configuration: configuration)
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.navigationDelegate = self
    webView.uiDelegate = self

    let controlsView = DailymotionControlsView(frame: .zero)
    controlsView.translatesAutoresizingMaskIntoConstraints = false
    controlsView.delegate = self

    let contentView = NSView(frame: panel.contentView?.bounds ?? .zero)
    contentView.addSubview(webView)
    contentView.addSubview(controlsView)
    NSLayoutConstraint.activate([
      webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      webView.topAnchor.constraint(equalTo: contentView.topAnchor),
      webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      controlsView.leadingAnchor.constraint(
        equalTo: contentView.leadingAnchor,
        constant: 10
      ),
      controlsView.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor,
        constant: -10
      ),
      controlsView.topAnchor.constraint(
        equalTo: contentView.topAnchor,
        constant: 10
      ),
      controlsView.heightAnchor.constraint(equalToConstant: 42),
    ])
    panel.contentView = contentView

    self.userContentController = contentController
    self.webView = webView
    self.controlsView = controlsView

    switch source.backend {
    case let .sdk(playerID):
      state.backend = "sdk"
      webView.loadHTMLString(
        sdkPlayerHTML(
          playerID: playerID,
          videoID: source.videoID,
          startsMuted: source.startsMuted,
          sessionID: sessionID
        ),
        baseURL: URL(string: "https://sol.invalid/dailymotion/")
      )
      let fallbackWorkItem = DispatchWorkItem { [weak self, weak webView] in
        guard
          let self,
          let webView,
          self.webView === webView,
          self.state.backend == "sdk",
          !self.state.ready
        else {
          return
        }
        self.sdkFallbackDidStart = true
        self.clearMediaFrame()
        self.state = DailymotionBridgeState(backend: "media")
        self.notifyStateChange()
        webView.load(URLRequest(url: source.url))
      }
      sdkFallbackWorkItem = fallbackWorkItem
      DispatchQueue.main.asyncAfter(
        deadline: .now() + 10,
        execute: fallbackWorkItem
      )
    case .embeddedPage:
      state.backend = "media"
      webView.load(URLRequest(url: source.url))
    }
    notifyStateChange()
  }

  private func teardownWebView() {
    sdkFallbackWorkItem?.cancel()
    sdkFallbackWorkItem = nil
    webView?.stopLoading()
    webView?.navigationDelegate = nil
    webView?.uiDelegate = nil
    userContentController?.removeScriptMessageHandler(
      forName: dailymotionBridgeName
    )
    webView?.removeFromSuperview()
    controlsView?.delegate = nil
    controlsView?.removeFromSuperview()
    webView = nil
    controlsView = nil
    userContentController = nil
    mediaFrame = nil
    mediaFrameToken = nil
    mediaFrameIsMain = false
    mediaFrameIsPlaying = false
    mediaFrameArea = 0
    mediaFrameLastSeen = .distantPast
    sdkFallbackDidStart = false
    sessionID = ""
  }

  private func notifyStateChange() {
    controlsView?.render(state)
  }

  private func handleSDKState(_ body: [String: Any]) {
    guard !sdkFallbackDidStart else { return }
    state.backend = "sdk"
    state.ready = bool(body["ready"]) ?? state.ready
    state.isPlaying = bool(body["isPlaying"]) ?? state.isPlaying
    state.isBuffering = bool(body["isBuffering"]) ?? state.isBuffering
    state.isMuted = bool(body["isMuted"]) ?? state.isMuted
    state.currentTime = finiteDouble(body["time"]) ?? state.currentTime
    state.duration = positiveFiniteDouble(body["duration"])
    state.playbackRate = finiteDouble(body["rate"]) ?? state.playbackRate
    state.volume = finiteDouble(body["volume"]).map {
      min(max($0, 0), 1)
    } ?? state.volume
    state.isAdPlaying = bool(body["adPlaying"]) ?? state.isAdPlaying
    state.adTime = finiteDouble(body["adTime"]) ?? state.adTime
    state.adDuration = positiveFiniteDouble(body["adDuration"])
    state.error = body["error"] as? String
    if state.ready {
      sdkFallbackWorkItem?.cancel()
      sdkFallbackWorkItem = nil
    }
    notifyStateChange()
  }

  private func handleMediaState(
    _ body: [String: Any],
    frameInfo: WKFrameInfo
  ) {
    guard let frameToken = body["frame"] as? String else { return }
    guard bool(body["ready"]) == true else {
      if frameToken == mediaFrameToken {
        clearMediaFrame()
        if state.backend == "media" {
          state.ready = false
          notifyStateChange()
        }
      }
      return
    }
    let area = finiteDouble(body["area"]) ?? 0
    let isPlaying = bool(body["isPlaying"]) ?? false
    let isCurrentFrame = frameToken == mediaFrameToken
    let currentFrameExpired = Date().timeIntervalSince(mediaFrameLastSeen) > 2
    let shouldUseFrame = isCurrentFrame
      || mediaFrame == nil
      || currentFrameExpired
      || isPlaying && !mediaFrameIsPlaying
      || area > mediaFrameArea * 1.25
      || frameInfo.isMainFrame && area >= mediaFrameArea

    guard shouldUseFrame else { return }
    mediaFrame = frameInfo
    mediaFrameToken = frameToken
    mediaFrameIsMain = frameInfo.isMainFrame
    mediaFrameIsPlaying = isPlaying
    mediaFrameArea = area
    mediaFrameLastSeen = Date()

    if !(state.backend == "sdk" && state.isAdPlaying) {
      let seekableStart = finiteDouble(body["seekableStart"])
      let seekableEnd = finiteDouble(body["seekableEnd"])
      if
        let seekableStart,
        let seekableEnd,
        seekableEnd > seekableStart
      {
        state.seekableStart = seekableStart
        state.seekableEnd = seekableEnd
      } else {
        state.seekableStart = nil
        state.seekableEnd = nil
      }
    }

    // The SDK is canonical for playback and advertising. The media bridge is
    // still useful there because the public SDK does not expose DVR ranges.
    if state.backend == "sdk" {
      if !state.isAdPlaying {
        state.isMuted = bool(body["isMuted"]) ?? state.isMuted
      }
      notifyStateChange()
      return
    }

    state.backend = "media"
    state.ready = bool(body["ready"]) ?? state.ready
    state.isPlaying = bool(body["isPlaying"]) ?? state.isPlaying
    state.isBuffering = bool(body["isBuffering"]) ?? state.isBuffering
    state.isMuted = bool(body["isMuted"]) ?? state.isMuted
    state.currentTime = finiteDouble(body["time"]) ?? state.currentTime
    state.duration = positiveFiniteDouble(body["duration"])
    state.playbackRate = finiteDouble(body["rate"]) ?? state.playbackRate
    state.volume = finiteDouble(body["volume"]).map {
      min(max($0, 0), 1)
    } ?? state.volume
    state.error = body["error"] as? String
    notifyStateChange()
  }

  private func handleBridgeError(_ body: [String: Any]) {
    state.error = body["message"] as? String ?? "Dailymotion player error"
    notifyStateChange()
  }

  private func clearMediaFrame() {
    mediaFrame = nil
    mediaFrameToken = nil
    mediaFrameIsMain = false
    mediaFrameIsPlaying = false
    mediaFrameArea = 0
    mediaFrameLastSeen = .distantPast
  }

  private func bool(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    return (value as? NSNumber)?.boolValue
  }

  private func finiteDouble(_ value: Any?) -> Double? {
    guard let value = value as? NSNumber else { return nil }
    let result = value.doubleValue
    return result.isFinite ? result : nil
  }

  private func positiveFiniteDouble(_ value: Any?) -> Double? {
    guard let value = finiteDouble(value), value > 0 else { return nil }
    return value
  }

  private func sendCommand(
    _ command: String,
    value: Double? = nil,
    completion: ((Bool) -> Void)? = nil
  ) {
    let allowedCommands = [
      "play", "pause", "seek", "seekBy", "goLive", "rate", "volume",
    ]
    guard allowedCommands.contains(command), let webView else {
      completion?(false)
      return
    }

    let normalizedValue: Double?
    switch command {
    case "rate":
      let rates = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
      guard let value, value.isFinite, rates.contains(value) else {
        completion?(false)
        return
      }
      normalizedValue = value
    case "volume":
      guard let value, value.isFinite else {
        completion?(false)
        return
      }
      normalizedValue = min(max(value, 0), 1)
    case "seek", "seekBy", "goLive":
      guard let value, value.isFinite else {
        completion?(false)
        return
      }
      normalizedValue = value
    default:
      normalizedValue = nil
    }

    // A live edge comes from HTMLMediaElement.seekable, so execute that seek
    // in the exact frame that supplied the range instead of assuming the SDK
    // and media timelines use identical coordinates.
    let primaryFrame: WKFrameInfo? = command == "goLive" && mediaFrame != nil
      ? mediaFrame
      : state.backend == "sdk" ? nil : mediaFrame
    executeCommand(
      command,
      value: normalizedValue,
      in: primaryFrame,
      webView: webView
    ) { [weak self] succeeded in
      guard let self else { return }
      if succeeded {
        // Dailymotion models mute and volume separately. Moving Sol's volume
        // slider is an explicit request for audible output, so mirror it in
        // the media frame to clear an initial autoplay mute when possible.
        if command == "volume", let mediaFrame = self.mediaFrame {
          self.executeCommand(
            command,
            value: normalizedValue,
            in: mediaFrame,
            webView: webView,
            completion: nil
          )
        }
        completion?(true)
        return
      }

      if primaryFrame != nil {
        self.clearMediaFrame()
      }

      guard let mediaFrame = self.mediaFrame, primaryFrame == nil else {
        completion?(false)
        return
      }
      self.executeCommand(
        command,
        value: normalizedValue,
        in: mediaFrame,
        webView: webView,
        completion: completion
      )
    }
  }

  private func executeCommand(
    _ command: String,
    value: Double?,
    in frame: WKFrameInfo?,
    webView: WKWebView,
    completion: ((Bool) -> Void)?
  ) {
    let scriptValue: Any = value.map { NSNumber(value: $0) } ?? NSNull()
    webView.callAsyncJavaScript(
      """
      return await window.__solDailymotionBridge?.command(command, value) ?? false;
      """,
      arguments: [
        "command": command,
        "value": scriptValue,
      ],
      in: frame,
      in: .page
    ) { result in
      switch result {
      case let .success(value):
        completion?(self.bool(value) ?? false)
      case .failure:
        completion?(false)
      }
    }
  }

  private func sdkPlayerHTML(
    playerID: String,
    videoID: String,
    startsMuted: Bool,
    sessionID: String
  ) -> String {
    let muted = startsMuted ? "true" : "false"
    return #"""
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
          html,body,#sol-player{width:100%;height:100%;margin:0;background:#000;overflow:hidden}
        </style>
      </head>
      <body>
        <div id="sol-player"></div>
        <script src="https://geo.dailymotion.com/libs/player/\#(playerID).js"></script>
        <script>
          (() => {
            const SESSION = "\#(sessionID)";
            const post = (payload) => {
              window.webkit?.messageHandlers?.solDailymotion?.postMessage({
                ...payload,
                session: SESSION,
              });
            };
            const number = (value) => Number.isFinite(value) ? value : null;
            let player = null;
            let pollingTimer = null;

            async function report() {
              if (!player) return;
              try {
                const state = await player.getState();
                post({
                  type: "sdkState",
                  ready: Boolean(state.playerIsCriticalPathReady),
                  isPlaying: Boolean(state.playerIsPlaying),
                  isBuffering: Boolean(state.playerIsBuffering),
                  isMuted: Boolean(state.playerIsMuted),
                  time: number(state.videoTime),
                  duration: number(state.videoDuration),
                  rate: number(state.playerPlaybackSpeed),
                  volume: number(state.playerVolume),
                  adPlaying: Boolean(state.adIsPlaying),
                  adTime: number(state.adTime),
                  adDuration: number(state.adDuration),
                  error: state.playerError?.message ?? null,
                });
              } catch (error) {
                post({type: "error", message: String(error)});
              }
            }

            window.__solDailymotionBridge = {
              async command(command, rawValue) {
                if (!player) return false;
                const value = Number(rawValue);
                try {
                  switch (command) {
                    case "play": await player.play(); break;
                    case "pause": await player.pause(); break;
                    case "seek": await player.seek(value); break;
                    case "seekBy": {
                      const state = await player.getState();
                      await player.seek((number(state.videoTime) ?? 0) + value);
                      break;
                    }
                    case "goLive": await player.seek(value); break;
                    case "rate": await player.setPlaybackSpeed(value); break;
                    case "volume": await player.setVolume(value); break;
                    default: return false;
                  }
                  setTimeout(report, 0);
                  return true;
                } catch (error) {
                  post({type: "error", message: String(error)});
                  return false;
                }
              },
            };

            dailymotion.createPlayer("sol-player", {
              video: "\#(videoID)",
              params: {autoplay: true, mute: \#(muted)},
            }).then((createdPlayer) => {
              player = createdPlayer;
              const eventNames = [
                "PLAYER_CRITICALPATHREADY", "PLAYER_VIDEOCHANGE",
                "VIDEO_DURATIONCHANGE", "VIDEO_TIMECHANGE", "VIDEO_PLAY",
                "VIDEO_PLAYING", "VIDEO_PAUSE", "VIDEO_END",
                "VIDEO_SEEKSTART", "VIDEO_SEEKEND", "VIDEO_BUFFERING",
                "PLAYER_PLAYBACKSPEEDCHANGE", "PLAYER_VOLUMECHANGE",
                "AD_START", "AD_END", "AD_TIMECHANGE", "PLAYER_ERROR",
              ];
              for (const name of eventNames) {
                const event = dailymotion.events?.[name];
                if (event) player.on(event, report);
              }
              pollingTimer = setInterval(report, 500);
              report();
            }).catch((error) => {
              post({type: "error", message: String(error)});
            });

            window.addEventListener("pagehide", () => {
              if (pollingTimer) clearInterval(pollingTimer);
            });
          })();
        </script>
      </body>
    </html>
    """#
  }

  private func mediaBridgeScript(sessionID: String) -> String {
    #"""
    (() => {
      const SESSION = "\#(sessionID)";
      const FRAME = crypto.randomUUID?.()
        ?? `${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const host = location.hostname.toLowerCase();
      const trustedHost = host === "dailymotion.com"
        || host.endsWith(".dailymotion.com")
        || host === "dmcdn.net"
        || host.endsWith(".dmcdn.net");
      if (!trustedHost) return;
      if (window.__solDailymotionBridge?.session === SESSION) return;

      const post = (payload) => {
        window.webkit?.messageHandlers?.solDailymotion?.postMessage({
          ...payload,
          session: SESSION,
          frame: FRAME,
        });
      };
      const finite = (value) => Number.isFinite(value) ? value : null;
      let media = null;
      let buffering = false;
      let boundMedia = null;

      function collectVideos(root, result = []) {
        if (!root?.querySelectorAll) return result;
        result.push(...root.querySelectorAll("video"));
        for (const element of root.querySelectorAll("*")) {
          if (element.shadowRoot) collectVideos(element.shadowRoot, result);
        }
        return result;
      }

      function locateMedia() {
        const videos = collectVideos(document).sort((first, second) => {
          const firstArea = first.clientWidth * first.clientHeight;
          const secondArea = second.clientWidth * second.clientHeight;
          return secondArea - firstArea;
        });
        const selected = videos.find((video) => !video.ended && !video.paused)
          ?? videos[0]
          ?? null;
        if (selected !== media) media = selected;
        bindMediaEvents();
        return media;
      }

      function seekableRange(video) {
        try {
          if (!video?.seekable?.length) return [null, null];
          return [
            finite(video.seekable.start(0)),
            finite(video.seekable.end(video.seekable.length - 1)),
          ];
        } catch (_) {
          return [null, null];
        }
      }

      function report() {
        const video = locateMedia();
        if (!video) {
          post({type: "mediaState", ready: false, area: 0});
          return;
        }
        const [seekableStart, seekableEnd] = seekableRange(video);
        post({
          type: "mediaState",
          ready: video.readyState >= 1,
          isPlaying: !video.paused && !video.ended,
          isBuffering: buffering,
          isMuted: Boolean(video.muted),
          time: finite(video.currentTime),
          duration: finite(video.duration),
          seekableStart,
          seekableEnd,
          rate: finite(video.playbackRate),
          volume: finite(video.volume),
          area: video.clientWidth * video.clientHeight,
          error: video.error ? `Media error ${video.error.code}` : null,
        });
      }

      function bindMediaEvents() {
        if (!media || media === boundMedia) return;
        boundMedia = media;
        const reportEvents = [
          "loadedmetadata", "durationchange", "timeupdate", "play", "pause",
          "ended", "progress", "ratechange", "volumechange", "seeking",
          "seeked", "error",
        ];
        for (const eventName of reportEvents) {
          media.addEventListener(eventName, report, {passive: true});
        }
        media.addEventListener("waiting", () => {
          buffering = true;
          report();
        }, {passive: true});
        media.addEventListener("playing", () => {
          buffering = false;
          report();
        }, {passive: true});
      }

      async function command(command, rawValue) {
        const video = locateMedia();
        if (!video) return false;
        const value = Number(rawValue);
        try {
          switch (command) {
            case "play": await video.play(); break;
            case "pause": video.pause(); break;
            case "seek":
            case "seekBy":
            case "goLive": {
              const [rangeStart, rangeEnd] = seekableRange(video);
              let target = command === "seekBy"
                ? video.currentTime + value
                : value;
              if (rangeStart !== null && rangeEnd !== null) {
                target = Math.min(Math.max(target, rangeStart), Math.max(rangeStart, rangeEnd - 0.05));
              } else if (Number.isFinite(video.duration)) {
                target = Math.min(Math.max(target, 0), video.duration);
              } else {
                return false;
              }
              video.currentTime = target;
              break;
            }
            case "rate": video.playbackRate = value; break;
            case "volume":
              video.volume = Math.min(Math.max(value, 0), 1);
              if (value > 0) video.muted = false;
              break;
            default: return false;
          }
          setTimeout(report, 0);
          return true;
        } catch (error) {
          post({type: "error", message: String(error)});
          return false;
        }
      }

      window.__solDailymotionBridge = {session: SESSION, command};
      new MutationObserver(() => {
        if (!media?.isConnected) {
          media = null;
          locateMedia();
        }
      }).observe(document.documentElement, {childList: true, subtree: true});
      locateMedia();
      report();
      setInterval(report, 500);
    })();
    """#
  }
}

extension DailymotionPlayerController: DailymotionControlsViewDelegate {
  fileprivate func controlsDidTogglePlayback(
    _ controls: DailymotionControlsView
  ) {
    sendCommand(state.isPlaying ? "pause" : "play")
  }

  fileprivate func controls(
    _ controls: DailymotionControlsView,
    seekBy seconds: Double
  ) {
    guard !state.isAdPlaying else { return }
    sendCommand("seekBy", value: seconds)
  }

  fileprivate func controls(
    _ controls: DailymotionControlsView,
    seekTo seconds: Double
  ) {
    guard !state.isAdPlaying else { return }
    sendCommand("seek", value: seconds)
  }

  fileprivate func controlsDidRequestLiveEdge(
    _ controls: DailymotionControlsView
  ) {
    guard
      !state.isAdPlaying,
      let liveEdge = state.seekableEnd
    else {
      return
    }
    sendCommand("goLive", value: max(0, liveEdge - 0.25))
  }

  fileprivate func controls(
    _ controls: DailymotionControlsView,
    didSelectRate rate: Double
  ) {
    guard !state.isAdPlaying else { return }
    sendCommand("rate", value: rate)
  }

  fileprivate func controls(
    _ controls: DailymotionControlsView,
    didSetVolume volume: Double
  ) {
    sendCommand("volume", value: volume)
  }
}

extension DailymotionPlayerController: WKScriptMessageHandler {
  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard
      message.name == dailymotionBridgeName,
      isTrustedMessageOrigin(message.frameInfo.securityOrigin),
      let body = message.body as? [String: Any],
      body["session"] as? String == sessionID,
      let type = body["type"] as? String
    else {
      return
    }

    switch type {
    case "sdkState":
      handleSDKState(body)
    case "mediaState":
      handleMediaState(body, frameInfo: message.frameInfo)
    case "error":
      handleBridgeError(body)
    default:
      break
    }
  }

  private func isTrustedMessageOrigin(_ origin: WKSecurityOrigin) -> Bool {
    guard origin.protocol.lowercased() == "https" else { return false }
    let host = origin.host.lowercased()
    return host == "sol.invalid"
      || host == "dailymotion.com"
      || host.hasSuffix(".dailymotion.com")
      || host == "dmcdn.net"
      || host.hasSuffix(".dmcdn.net")
  }
}

extension DailymotionPlayerController: WKNavigationDelegate {
  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }

    if navigationAction.targetFrame?.isMainFrame != true {
      let allowedSchemes = ["https", "about", "blob", "data"]
      decisionHandler(allowedSchemes.contains(url.scheme?.lowercased() ?? "") ? .allow : .cancel)
      return
    }

    if url.scheme == "about" || url.host?.lowercased() == "sol.invalid" {
      decisionHandler(.allow)
      return
    }

    guard url.scheme == "https", let host = url.host?.lowercased() else {
      decisionHandler(.cancel)
      return
    }
    let isDailymotion = host == "dailymotion.com"
      || host.hasSuffix(".dailymotion.com")
      || host == "dmcdn.net"
      || host.hasSuffix(".dmcdn.net")
    decisionHandler(isDailymotion ? .allow : .cancel)
  }
}

extension DailymotionPlayerController: WKUIDelegate {
  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    nil
  }
}
