import AppKit
import Combine
import SwiftUI

public final class FloatingStopwatchManager {
  public static let shared = FloatingStopwatchManager()

  private var controller: FloatingStopwatchWindowController?

  private init() {}

  public func presentStopwatch() {
    onMain { [self] in
      if let controller {
        controller.bringToFront()
        return
      }

      let controller = FloatingStopwatchWindowController()
      controller.onClose = { [weak self, weak controller] in
        guard self?.controller === controller else { return }
        self?.controller = nil
      }
      self.controller = controller
      controller.presentCentered()
    }
  }

  private func onMain(_ body: @escaping () -> Void) {
    if Thread.isMainThread {
      body()
    } else {
      DispatchQueue.main.async(execute: body)
    }
  }
}

private final class FloatingStopwatchWindowController: NSWindowController, NSWindowDelegate {
  var onClose: (() -> Void)?

  private let panel = FloatingStopwatchPanel(surfaceSize: NSSize(width: 326, height: 252))
  private let model = FloatingStopwatchModel()
  private var didClose = false

  init() {
    super.init(window: panel)
    panel.delegate = self
    panel.keyboardHandler = { [weak self] action in
      self?.perform(action)
    }
    installContent()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func presentCentered() {
    positionAtScreenCenter()
    NSApp.activate(ignoringOtherApps: true)
    panel.orderFrontRegardless()
    panel.makeKey()
  }

  func bringToFront() {
    NSApp.activate(ignoringOtherApps: true)
    panel.orderFrontRegardless()
    panel.makeKey()
  }

  func windowDidBecomeKey(_ notification: Notification) {
    guard validateAlwaysOnTop() else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.1
      panel.animator().alphaValue = 1
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    guard validateAlwaysOnTop() else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.14
      panel.animator().alphaValue = 0.86
    }
  }

  func windowWillClose(_ notification: Notification) {
    guard !didClose else { return }
    didClose = true
    model.stopRefreshing()
    onClose?()
  }

  private func installContent() {
    let backdrop = panel.installRoundedContent()
    let rootView = FloatingStopwatchView(
      model: model,
      onClose: { [weak panel] in panel?.close() }
    )
    let host = NSHostingView(rootView: rootView)
    host.translatesAutoresizingMaskIntoConstraints = false
    backdrop.addSubview(host)
    NSLayoutConstraint.activate([
      host.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
      host.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
      host.topAnchor.constraint(equalTo: backdrop.topAnchor),
      host.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
    ])
  }

  private func positionAtScreenCenter() {
    let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
      ?? NSScreen.main
    guard let screen else {
      panel.center()
      return
    }
    let size = panel.frame.size
    panel.setFrameOrigin(
      NSPoint(
        x: floor(screen.visibleFrame.midX - size.width / 2),
        y: floor(screen.visibleFrame.midY - size.height / 2)
      )
    )
  }

  private func validateAlwaysOnTop() -> Bool {
    guard panel.level == .floating else {
      panel.close()
      return false
    }
    return true
  }

  private func perform(_ action: FloatingStopwatchKeyboardAction) {
    switch action {
    case .toggle:
      model.isRunning ? model.stop() : model.start()
    case .lap:
      model.lap()
    case .stop:
      model.stop()
    case .reset:
      model.reset()
    }
  }
}

private enum FloatingStopwatchKeyboardAction {
  case toggle
  case lap
  case stop
  case reset
}

private final class FloatingStopwatchPanel: NSPanel {
  static let shadowPadding: CGFloat = 14

  var keyboardHandler: ((FloatingStopwatchKeyboardAction) -> Void)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  convenience init(surfaceSize: NSSize) {
    self.init(
      contentRect: NSRect(
        origin: .zero,
        size: NSSize(
          width: surfaceSize.width + Self.shadowPadding * 2,
          height: surfaceSize.height + Self.shadowPadding * 2
        )
      ),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
    isMovableByWindowBackground = true
    animationBehavior = .utilityWindow
  }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown {
      if event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1B}" {
        close()
        return
      }
      let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
      if event.modifierFlags.intersection(disallowedModifiers).isEmpty {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case " ":
          keyboardHandler?(.toggle)
          return
        case "l":
          keyboardHandler?(.lap)
          return
        case "s":
          keyboardHandler?(.stop)
          return
        case "r":
          keyboardHandler?(.reset)
          return
        default:
          break
        }
      }
    }
    super.sendEvent(event)
  }

  override func cancelOperation(_ sender: Any?) {
    close()
  }

  func installRoundedContent() -> FloatingStopwatchBackdropView {
    let host = FloatingStopwatchShadowHostView(frame: contentView?.bounds ?? .zero)
    host.autoresizingMask = [.width, .height]
    contentView = host
    return host.backdrop
  }
}

private final class FloatingStopwatchShadowHostView: NSView {
  let backdrop = FloatingStopwatchBackdropView(frame: .zero)
  private let shadowLayer = CALayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.masksToBounds = true

    shadowLayer.masksToBounds = false
    shadowLayer.shadowColor = NSColor.black.cgColor
    shadowLayer.shadowOpacity = 0.24
    shadowLayer.shadowRadius = 10
    shadowLayer.shadowOffset = CGSize(width: 0, height: -2)
    layer?.addSublayer(shadowLayer)
    addSubview(backdrop)
    applyColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isOpaque: Bool { false }

  override func layout() {
    super.layout()
    let padding = FloatingStopwatchPanel.shadowPadding
    let surfaceFrame = bounds.insetBy(dx: padding, dy: padding)
    backdrop.frame = surfaceFrame

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shadowLayer.frame = surfaceFrame
    shadowLayer.cornerRadius = 15
    shadowLayer.cornerCurve = .continuous
    shadowLayer.shadowPath = CGPath(
      roundedRect: shadowLayer.bounds,
      cornerWidth: 15,
      cornerHeight: 15,
      transform: nil
    )
    CATransaction.commit()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  private func applyColors() {
    shadowLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
  }
}

private final class FloatingStopwatchBackdropView: NSVisualEffectView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    material = .popover
    blendingMode = .behindWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = 15
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.borderWidth = 0.5
    applyColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  private func applyColors() {
    layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.8).cgColor
  }
}

private struct FloatingStopwatchLap: Identifiable {
  let id = UUID()
  let number: Int
  let split: TimeInterval
  let total: TimeInterval
}

private final class FloatingStopwatchModel: ObservableObject {
  @Published private(set) var elapsed: TimeInterval = 0
  @Published private(set) var isRunning = false
  @Published private(set) var laps: [FloatingStopwatchLap] = []

  private var accumulated: TimeInterval = 0
  private var startedAt: TimeInterval?
  private var refreshTimer: Timer?

  func start() {
    guard !isRunning else { return }
    startedAt = ProcessInfo.processInfo.systemUptime
    isRunning = true
    refreshElapsed()
    startRefreshing()
  }

  func stop() {
    guard isRunning else { return }
    refreshElapsed()
    accumulated = elapsed
    startedAt = nil
    isRunning = false
    stopRefreshing()
  }

  func lap() {
    guard isRunning else { return }
    refreshElapsed()
    let previousTotal = laps.last?.total ?? 0
    laps.append(
      FloatingStopwatchLap(
        number: laps.count + 1,
        split: max(0, elapsed - previousTotal),
        total: elapsed
      )
    )
  }

  func reset() {
    stopRefreshing()
    accumulated = 0
    startedAt = nil
    elapsed = 0
    laps = []
    isRunning = false
  }

  func stopRefreshing() {
    refreshTimer?.invalidate()
    refreshTimer = nil
  }

  private func startRefreshing() {
    stopRefreshing()
    let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      self?.refreshElapsed()
    }
    refreshTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func refreshElapsed() {
    guard let startedAt else {
      elapsed = accumulated
      return
    }
    elapsed = accumulated + max(0, ProcessInfo.processInfo.systemUptime - startedAt)
  }
}

private struct FloatingStopwatchView: View {
  @ObservedObject var model: FloatingStopwatchModel
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      timeDisplay
      controls
      Divider()
        .padding(.top, 10)
      laps
    }
    .frame(width: 326, height: 252)
    .background(Color.clear)
  }

  private var toolbar: some View {
    HStack(spacing: 7) {
      Image(systemName: "stopwatch")
        .foregroundStyle(.secondary)
      Text("Stopwatch")
        .font(.system(size: 12, weight: .semibold))
      Spacer()
      Text(model.isRunning ? "RUNNING" : (model.elapsed > 0 ? "STOPPED" : "READY"))
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundStyle(model.isRunning ? Color.green : Color.secondary)
      Button(action: onClose) {
        Image(systemName: "xmark")
          .frame(width: 18, height: 18)
      }
      .buttonStyle(.plain)
      .help("Close (Esc)")
    }
    .padding(.horizontal, 9)
    .frame(height: 30)
    .contentShape(Rectangle())
  }

  private var timeDisplay: some View {
    Text(Self.format(model.elapsed, centiseconds: true))
      .font(.system(size: 36, weight: .medium, design: .monospaced))
      .monospacedDigit()
      .contentTransition(.numericText())
      .frame(maxWidth: .infinity)
      .padding(.top, 12)
      .padding(.bottom, 9)
  }

  private var controls: some View {
    HStack(spacing: 7) {
      controlButton(
        title: "Start",
        symbol: "play.fill",
        tint: .green,
        enabled: !model.isRunning,
        action: model.start
      )
      controlButton(
        title: "Lap",
        symbol: "flag.fill",
        tint: .blue,
        enabled: model.isRunning,
        action: model.lap
      )
      controlButton(
        title: "Stop",
        symbol: "stop.fill",
        tint: .red,
        enabled: model.isRunning,
        action: model.stop
      )
      controlButton(
        title: "Reset",
        symbol: "arrow.counterclockwise",
        tint: .secondary,
        enabled: model.elapsed > 0 || !model.laps.isEmpty,
        action: model.reset
      )
    }
    .padding(.horizontal, 10)
  }

  private func controlButton(
    title: String,
    symbol: String,
    tint: Color,
    enabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: symbol)
          .font(.system(size: 11, weight: .semibold))
        Text(title)
          .font(.system(size: 10, weight: .medium))
      }
      .foregroundStyle(enabled ? tint : Color.secondary.opacity(0.45))
      .frame(maxWidth: .infinity, minHeight: 39)
      .background(Color.primary.opacity(enabled ? 0.055 : 0.025))
      .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .help("\(title) (\(shortcut(for: title)))")
  }

  private var laps: some View {
    Group {
      if model.laps.isEmpty {
        HStack {
          Text("LAPS")
          Spacer()
          Text("Press L while running")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(model.laps.reversed()) { lap in
              HStack(spacing: 8) {
                Text("Lap \(lap.number)")
                  .foregroundStyle(.secondary)
                Spacer()
                Text("+\(Self.format(lap.split, centiseconds: true))")
                Text(Self.format(lap.total, centiseconds: true))
                  .frame(width: 76, alignment: .trailing)
              }
              .font(.system(size: 11, design: .monospaced))
              .monospacedDigit()
              .padding(.horizontal, 12)
              .frame(height: 25)
            }
          }
        }
      }
    }
  }

  private func shortcut(for title: String) -> String {
    switch title {
    case "Start": return "Space"
    case "Lap": return "L"
    case "Stop": return "S"
    default: return "R"
    }
  }

  private static func format(_ interval: TimeInterval, centiseconds: Bool) -> String {
    let safe = max(0, interval)
    let hours = Int(safe / 3_600)
    let minutes = Int(safe / 60) % 60
    let seconds = safe.truncatingRemainder(dividingBy: 60)
    if hours > 0 {
      return centiseconds
        ? String(format: "%d:%02d:%05.2f", hours, minutes, seconds)
        : String(format: "%d:%02d:%02d", hours, minutes, Int(seconds))
    }
    return centiseconds
      ? String(format: "%02d:%05.2f", minutes, seconds)
      : String(format: "%02d:%02d", minutes, Int(seconds))
  }
}
