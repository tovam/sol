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

  func open(urlString: String) {
    guard let url = URL(string: urlString), isAllowedEmbedURL(url) else {
      return
    }

    DispatchQueue.main.async {
      let player = self.playerWindow()
      self.webView?.load(URLRequest(url: url))
      player.title = "Dailymotion"
      player.makeKeyAndOrderFront(nil)
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
    guard
      url.scheme == "https",
      url.host?.lowercased() == "www.dailymotion.com"
    else {
      return false
    }
    let components = url.path.split(separator: "/")
    guard components.count == 3, components[0] == "embed", components[1] == "video" else {
      return false
    }
    return components[2].allSatisfy { $0.isLetter || $0.isNumber }
  }
}
