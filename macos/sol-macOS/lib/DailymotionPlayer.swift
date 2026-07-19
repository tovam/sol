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

final class DailymotionPlayerController: NSObject, NSWindowDelegate {
  static let shared = DailymotionPlayerController()

  private var panel: FloatingVideoPanel?
  private var webView: WKWebView?
  private var userContentController: WKUserContentController?
  private var source: DailymotionPlayerSource?
  private var sessionID = ""
  private var mediaFrame: WKFrameInfo?
  private var mediaFrameIsMain = false
  private var mediaFrameIsPlaying = false
  private var mediaFrameArea = 0.0
  private var sdkFallbackWorkItem: DispatchWorkItem?
  private var state = DailymotionBridgeState()
  private var onStateChange: ((DailymotionBridgeState) -> Void)?

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
    panel.minSize = NSSize(width: 360, height: 203)
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
    mediaFrameIsMain = false
    mediaFrameIsPlaying = false
    mediaFrameArea = 0
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
    webView.autoresizingMask = [.width, .height]
    webView.navigationDelegate = self
    webView.uiDelegate = self
    panel.contentView = webView

    self.userContentController = contentController
    self.webView = webView

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
    webView = nil
    userContentController = nil
    mediaFrame = nil
    mediaFrameIsMain = false
    mediaFrameIsPlaying = false
    mediaFrameArea = 0
    sessionID = ""
  }

  private func notifyStateChange() {
    onStateChange?(state)
  }

  private func handleSDKState(_ body: [String: Any]) {
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
    guard bool(body["ready"]) == true else { return }
    let area = finiteDouble(body["area"]) ?? 0
    let isPlaying = bool(body["isPlaying"]) ?? false
    let currentFrameURL = mediaFrame?.request.url
    let incomingFrameURL = frameInfo.request.url
    let isCurrentFrame = mediaFrameIsMain == frameInfo.isMainFrame
      && currentFrameURL != nil
      && currentFrameURL == incomingFrameURL
    let shouldUseFrame = isCurrentFrame
      || mediaFrame == nil
      || isPlaying && !mediaFrameIsPlaying
      || area > mediaFrameArea * 1.25
      || frameInfo.isMainFrame && area >= mediaFrameArea

    guard shouldUseFrame else { return }
    mediaFrame = frameInfo
    mediaFrameIsMain = frameInfo.isMainFrame
    mediaFrameIsPlaying = isPlaying
    mediaFrameArea = area

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
