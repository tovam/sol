import AppKit
import WebKit

private final class FloatingVideoPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

final class DailymotionPlayerController: NSObject, NSWindowDelegate {
  static let shared = DailymotionPlayerController()

  private var panel: FloatingVideoPanel?
  private var webView: WKWebView?

  func open(urlString: String, completion: @escaping (Bool) -> Void) {
    guard let url = URL(string: urlString), isAllowedEmbedURL(url) else {
      completion(false)
      return
    }

    DispatchQueue.main.async {
      let player = self.playerWindow()
      self.webView?.load(URLRequest(url: url))
      player.title = "Dailymotion"
      player.makeKeyAndOrderFront(nil)
      player.orderFrontRegardless()
      completion(player.isVisible)
    }
  }

  func windowWillClose(_ notification: Notification) {
    webView?.stopLoading()
    webView = nil
    panel = nil
  }

  private func playerWindow() -> FloatingVideoPanel {
    if let panel {
      return panel
    }

    let configuration = WKWebViewConfiguration()
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.allowsAirPlayForMediaPlayback = true

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.autoresizingMask = [.width, .height]

    let panel = FloatingVideoPanel(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    panel.contentView = webView
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
    self.webView = webView
    return panel
  }

  private func isAllowedEmbedURL(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host?.lowercased() else {
      return false
    }

    let components = url.path.split(separator: "/")
    if host == "www.dailymotion.com" {
      guard components.count == 3, components[0] == "embed", components[1] == "video" else {
        return false
      }
      return components[2].allSatisfy { $0.isLetter || $0.isNumber }
    }

    if host == "geo.dailymotion.com" {
      guard components.count == 2, components[0] == "player" else {
        return false
      }
      let playerFile = String(components[1])
      guard playerFile.hasSuffix(".html") else {
        return false
      }
      let playerID = playerFile.dropLast(5)
      guard
        !playerID.isEmpty,
        playerID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }),
        let videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
          .queryItems?
          .first(where: { $0.name == "video" })?
          .value,
        !videoID.isEmpty,
        videoID.allSatisfy({ $0.isLetter || $0.isNumber })
      else {
        return false
      }
      return true
    }

    return false
  }
}
