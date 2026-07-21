import Foundation
import HotKey
import LaunchAtLogin
import React
import UserNotifications

// The original "Sol" item can retain an ACL from an earlier ad-hoc build and
// keep prompting after every replacement. New writes use a versioned service
// whose ACL is created by the persistently signed app.
private let keychain = Keychain(service: "com.ospfranco.sol.secure.v2")
private let legacyKeychain = Keychain(service: "Sol")

private enum SolKeychainMigrationError: LocalizedError {
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .verificationFailed:
      return "The migrated Keychain value could not be verified."
    }
  }
}

@objc(SolNative)
class SolNative: RCTEventEmitter {
  let appDelegate = NSApp.delegate as? AppDelegate

  override init() {
    super.init()
    SolEmitter.sharedInstance.registerEmitter(emitter: self)
    ApplicationSearcher.shared.onApplicationsChanged = {
      self.sendEvent(
        withName: "applicationsChanged",
        body: [])
    }
  }

  @objc override func constantsToExport() -> [AnyHashable: Any]! {
    return [
      "accentColor": NSColor.controlAccentColor.usingColorSpace(.sRGB)!
        .hexString,
      "OSVersion": ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
    ]
  }

  @objc override func startObserving() {
    SolEmitter.sharedInstance.hasListeners = true
  }

  @objc override func stopObserving() {
    SolEmitter.sharedInstance.hasListeners = false
  }

  @objc override static func requiresMainQueueSetup() -> Bool {
    return true
  }

  func sendKeyDown(characters: String) {
    sendEvent(
      withName: "keyDown",
      body: [
        "key": characters
      ])
  }

  @objc override func supportedEvents() -> [String]? {
    return [
      "keyDown",
      "keyUp",
      "onShow",
      "onHide",
      "onTextCopied",
      "onFileCopied",
      "onFileSearch",
      "onStatusBarItemClick",
      "hotkey",
      "applicationsChanged",
      "dailymotionDVRRecordingChanged",
    ]
  }

  @objc func getApps(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: RCTPromiseRejectBlock
  ) {
    let apps = ApplicationSearcher.shared.getAllApplications()
    resolve(apps)
  }

  @objc func openFile(_ path: String) {
    // This is deprecated but it opens the apps with a single line of code
    NSWorkspace.shared.openFile(path)
  }

  @objc func openWithFinder(_ path: String) {
    guard let URL = URL(string: path) else {
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.promptsUserIfNeeded = true

    let finder = NSWorkspace.shared
      .urlForApplication(withBundleIdentifier: "com.apple.finder")
    NSWorkspace.shared.open(
      [URL],
      withApplicationAt: finder!,
      configuration: configuration
    )
  }

  @objc func toggleDarkMode() {
    DarkMode.isEnabled = !DarkMode.isEnabled
  }

  @objc func prepareTimerNotifications() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, error in
      if let error {
        print("Could not request timer notification permission: \(error.localizedDescription)")
      }
    }
  }

  @objc func notifyTimerFinished() {
    DispatchQueue.main.async {
      if NSSound(named: NSSound.Name("Glass"))?.play() != true {
        NSSound.beep()
      }
    }

    let center = UNUserNotificationCenter.current()
    let deliverNotification = {
      let content = UNMutableNotificationContent()
      content.title = "Sol Timer"
      content.body = "Time is up"
      let request = UNNotificationRequest(
        identifier: "sol-timer-\(UUID().uuidString)",
        content: content,
        trigger: nil
      )
      center.add(request) { error in
        if let error {
          print("Could not show timer notification: \(error.localizedDescription)")
        }
      }
    }

    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional:
        deliverNotification()
      case .notDetermined:
        center.requestAuthorization(options: [.alert]) { granted, error in
          if granted {
            deliverNotification()
          } else if let error {
            print("Could not authorize timer notification: \(error.localizedDescription)")
          }
        }
      case .denied:
        break
      @unknown default:
        break
      }
    }
  }

  @objc func executeAppleScript(
    _ source: String, resolve: RCTPromiseResolveBlock,
    reject: RCTPromiseRejectBlock
  ) {

    let error = AppleScriptHelper.runAppleScript(source)
    if error == nil {
      resolve(nil)
    } else {
      reject(
        "AppleScriptError",
        error!["NSAppleScriptErrorMessage"] as? String,
        nil
      )
    }
  }

  @objc func executeBashScript(
    _ source: String,
    resolver: RCTPromiseResolveBlock,
    rejecter _: RCTPromiseRejectBlock
  ) {
    let output = ShellHelper.shWithFloatingPanel(source)
    resolver(output)
  }

  @objc func executeBashScriptWithOutput(
    _ source: String,
    resolver resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let task = Process()
      let pipe = Pipe()
      task.executableURL = URL(fileURLWithPath: "/bin/zsh")
      task.arguments = ["-l", "-c", source]
      task.standardOutput = pipe
      task.standardError = pipe

      do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        if task.terminationStatus == 0 {
          resolve(output)
        } else {
          reject("ShellCommandError", output.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
      } catch {
        reject("ShellCommandError", error.localizedDescription, error)
      }
    }
  }

  @objc func getMediaInfo(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter _: RCTPromiseRejectBlock
  ) {
    MediaHelper.getCurrentMedia(callback: { information in
      let pathUrl = NSWorkspace.shared
        .urlForApplication(
          withBundleIdentifier: information["bundleIdentifier"]! as! String
        )?
        .path
      let imageData =
        information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

      if imageData == nil {
        resolve([
          "title": information["kMRMediaRemoteNowPlayingInfoTitle"],
          "artist": information["kMRMediaRemoteNowPlayingInfoArtist"],
          "bundleIdentifier": information["bundleIdentifier"],
          "url": pathUrl,
        ])
      } else {
        let bitmap = NSBitmapImageRep(data: imageData!)
        let data = bitmap?.representation(using: .jpeg, properties: [:])
        let base64 =
          data != nil
          ? "data:image/jpeg;base64,"
            + data!
            .base64EncodedString() : nil
        resolve([
          "title": information["kMRMediaRemoteNowPlayingInfoTitle"],
          "artist": information["kMRMediaRemoteNowPlayingInfoArtist"],
          "artwork": base64,
          "bundleIdentifier": information["bundleIdentifier"],
          "url": pathUrl,
        ])
      }

    })
  }

  @objc func setGlobalShortcut(_ key: String) {
    HotKeyManager.shared.mainHotKey.isPaused = true
    if key == "command" {
      HotKeyManager.shared.mainHotKey = HotKey(
        key: .space,
        modifiers: [.command],
        keyDownHandler: PanelManager.shared.toggle
      )
    } else if key == "option" {
      HotKeyManager.shared.mainHotKey = HotKey(
        key: .space,
        modifiers: [.option],
        keyDownHandler: PanelManager.shared.toggle
      )
    } else if key == "control" {
      HotKeyManager.shared.mainHotKey = HotKey(
        key: .space,
        modifiers: [.control],
        keyDownHandler: PanelManager.shared.toggle
      )
    }
  }

  @objc func getAccessibilityStatus(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter _: RCTPromiseRejectBlock
  ) {
    resolve(AXIsProcessTrusted())
  }

  @objc func requestAccessibilityAccess(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter _: RCTPromiseRejectBlock
  ) {
    let options: NSDictionary = [
      kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true
    ]
    let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
    resolve(accessibilityEnabled)
  }

  @objc func setLaunchAtLogin(_ enabled: Bool) {
    if LaunchAtLogin.isEnabled != enabled {
      LaunchAtLogin.isEnabled = enabled
    }
  }

  @objc func resizeFrontmostTopHalf() {
    WindowManager.sharedInstance.moveHalf(.top)
  }

  @objc func resizeFrontmostBottomHalf() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveHalf(.bottom) }
  }

  @objc func resizeFrontmostRightHalf() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveHalf(.right) }
  }

  @objc func resizeFrontmostLeftHalf() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveHalf(.left) }
  }

  @objc func resizeFrontmostFullscreen() {
    DispatchQueue.main.async { WindowManager.sharedInstance.fullscreen() }
  }

  @objc func resizeTopLeft() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveQuarter(.topLeft) }
  }

  @objc func resizeTopRight() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveQuarter(.topRight) }
  }

  @objc func resizeBottomLeft() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveQuarter(.bottomLeft) }
  }

  @objc func resizeBottomRight() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveQuarter(.bottomRight) }
  }

  @objc func resizeLeftThird() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveThird(.left) }
  }

  @objc func resizeCenterThird() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveThird(.center) }
  }

  @objc func resizeRightThird() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveThird(.right) }
  }

  @objc func resizeLeftTwoThirds() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveTwoThirds(.left) }
  }

  @objc func resizeRightTwoThirds() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveTwoThirds(.right) }
  }

  @objc func moveFrontmostNextScreen() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveToNextScreen() }
  }

  @objc func moveFrontmostPrevScreen() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveToPrevScreen() }
  }

  @objc func moveFrontmostCenter() {
    DispatchQueue.main.async { WindowManager.sharedInstance.center() }
  }

  @objc func moveFrontmostToNextSpace() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveFrontmostToNextSpace() }
  }

  @objc func moveFrontmostToPreviousSpace() {
    DispatchQueue.main.async { WindowManager.sharedInstance.moveFrontmostToPreviousSpace() }
  }

  @objc func pasteToFrontmostApp(_ content: String) {
    ClipboardHelper.pasteToFrontmostApp(content)
  }

  @objc func pasteImageToFrontmostApp(_ path: String) {
    ClipboardHelper.pasteImageFileToFrontmostApp(path)
  }

  @objc func insertToFrontmostApp(_ content: String) {
    ClipboardHelper.insertToFrontmostApp(content)
  }

  @objc func turnOnHorizontalArrowsListeners() {
    HotKeyManager.shared.catchHorizontalArrowsPress = true
  }

  @objc func turnOffHorizontalArrowsListeners() {
    HotKeyManager.shared.catchHorizontalArrowsPress = false
  }

  @objc func turnOnVerticalArrowsListeners() {
    HotKeyManager.shared.catchVerticalArrowsPress = true
  }

  @objc func turnOffVerticalArrowsListeners() {
    HotKeyManager.shared.catchVerticalArrowsPress = false
  }

  @objc func turnOnEnterListener() {
    HotKeyManager.shared.catchEnterPress = true
  }

  @objc func turnOffEnterListener() {
    HotKeyManager.shared.catchEnterPress = false
  }

  @objc func turnOnCommandEnterListener() {
    HotKeyManager.shared.catchCommandEnterPress = true
  }

  @objc func turnOffCommandEnterListener() {
    HotKeyManager.shared.catchCommandEnterPress = false
  }

  @objc func checkForUpdates() {
    appDelegate?.checkForUpdates()
  }

  @objc func setWindowRelativeSize(_ relative: NSNumber) {
    DispatchQueue.main.async {
      PanelManager.shared.setRelativeSize(relative as! Double)
    }
  }

  @objc func openFinderAt(_ path: String) {
    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
  }

  @objc func revealFileInFinder(_ path: String) {
    DispatchQueue.main.async {
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
  }

  @objc func setShowWindowOn(_ on: String) {
    switch on {
    case "screenWithFrontmost":
      PanelManager.shared.setPreferredScreen(.frontmost)
      break
    default:
      PanelManager.shared.setPreferredScreen(.withMouse)
      break
    }
  }

  @objc func setGlassAppearance(_ settings: NSDictionary) {
    let style = settings["style"] as? String ?? "clear"
    let cornerRadius = (settings["cornerRadius"] as? NSNumber)?.doubleValue ?? 24
    let tintHex = settings["tintColor"] as? String
    let tintOpacity = (settings["tintOpacity"] as? NSNumber)?.doubleValue ?? 0
    let shadowOpacity = (settings["shadowOpacity"] as? NSNumber)?.doubleValue ?? 0.32
    let shadowRadius = (settings["shadowRadius"] as? NSNumber)?.doubleValue ?? 12
    let shadowOffsetY = (settings["shadowOffsetY"] as? NSNumber)?.doubleValue ?? 3

    DispatchQueue.main.async {
      PanelManager.shared.setGlassAppearance(
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

  @objc func setSearchWindowPosition(_ position: NSDictionary) {
    let x = (position["x"] as? NSNumber)?.doubleValue ?? 50
    let y = (position["y"] as? NSNumber)?.doubleValue ?? 20

    DispatchQueue.main.async {
      PanelManager.shared.setSearchWindowPosition(x: x, y: y)
    }
  }

  @objc func setSearchWindowAnimation(_ settings: NSDictionary) {
    let openingWidthExtra =
      (settings["openingWidthExtra"] as? NSNumber)?.doubleValue ?? 50
    let openingHeightExtraPercent =
      (settings["openingHeightExtraPercent"] as? NSNumber)?.doubleValue ?? 1.8
    let openingDurationMs =
      (settings["openingDurationMs"] as? NSNumber)?.doubleValue ?? 100
    let openingBounce =
      (settings["openingBounce"] as? NSNumber)?.doubleValue ?? 0.2
    let openingInitialOpacity =
      (settings["openingInitialOpacity"] as? NSNumber)?.doubleValue ?? 0.62
    let closingWidthExtraPercent =
      (settings["closingWidthExtraPercent"] as? NSNumber)?.doubleValue ?? 1.8
    let closingHeightExtraPercent =
      (settings["closingHeightExtraPercent"] as? NSNumber)?.doubleValue ?? 1.2
    let closingDurationMs =
      (settings["closingDurationMs"] as? NSNumber)?.doubleValue ?? 85
    let resultsExpandDurationMs =
      (settings["resultsExpandDurationMs"] as? NSNumber)?.doubleValue ?? 240
    let resultsCollapseDurationMs =
      (settings["resultsCollapseDurationMs"] as? NSNumber)?.doubleValue ?? 180

    DispatchQueue.main.async {
      PanelManager.shared.setSearchWindowAnimation(
        openingWidthExtra: openingWidthExtra,
        openingHeightExtraPercent: openingHeightExtraPercent,
        openingDurationMs: openingDurationMs,
        openingBounce: openingBounce,
        openingInitialOpacity: openingInitialOpacity,
        closingWidthExtraPercent: closingWidthExtraPercent,
        closingHeightExtraPercent: closingHeightExtraPercent,
        closingDurationMs: closingDurationMs,
        resultsExpandDurationMs: resultsExpandDurationMs,
        resultsCollapseDurationMs: resultsCollapseDurationMs
      )
    }
  }

  @objc func toggleDND() {
    DoNotDisturb.toggle()
  }

  @objc func toggleScreenRuler() {
    ScreenRulerController.shared.toggle()
  }

  @objc func openDailymotionPlayer(
    _ url: String,
    resolver resolve: @escaping RCTPromiseResolveBlock,
    rejecter _: RCTPromiseRejectBlock
  ) {
    DailymotionPlayerController.shared.open(urlString: url) { opened in
      resolve(opened)
    }
  }

  @objc func inspectDailymotionDVR(
    _ url: String,
    qualityHeight: NSNumber?,
    resolver resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    DailymotionDVRRecordingManager.shared.inspect(
      pageURL: url,
      qualityHeight: qualityHeight?.intValue
    ) { result in
      DispatchQueue.main.async {
        switch result {
        case .success(let inspection):
          resolve(inspection)
        case .failure(let error):
          reject("DailymotionDVRInspectionError", error.localizedDescription, error)
        }
      }
    }
  }

  @objc func startDailymotionDVRRecording(
    _ options: NSDictionary,
    resolver resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    guard let request = options as? [String: Any] else {
      reject("DailymotionDVRRecordingError", "Invalid recording options", nil)
      return
    }
    DailymotionDVRRecordingManager.shared.start(options: request) { result in
      DispatchQueue.main.async {
        switch result {
        case .success(let state):
          resolve(state)
        case .failure(let error):
          reject("DailymotionDVRRecordingError", error.localizedDescription, error)
        }
      }
    }
  }

  @objc func cancelDailymotionDVRRecording(
    _ jobID: String,
    resolver resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    DailymotionDVRRecordingManager.shared.cancel(jobID: jobID) { result in
      DispatchQueue.main.async {
        switch result {
        case .success(let cancelled):
          resolve(cancelled)
        case .failure(let error):
          reject("DailymotionDVRRecordingError", error.localizedDescription, error)
        }
      }
    }
  }

  @objc func getDailymotionDVRRecordingState(
    _ resolve: RCTPromiseResolveBlock,
    rejecter _: RCTPromiseRejectBlock
  ) {
    resolve(DailymotionDVRRecordingManager.shared.currentState())
  }

  @objc func getDailymotionDVRDestinationCapacity(
    _ path: String,
    resolver resolve: RCTPromiseResolveBlock,
    rejecter _: RCTPromiseRejectBlock
  ) {
    resolve(DailymotionDVRRecordingManager.shared.availableCapacity(path: path))
  }

  @objc func getNetworkInfo(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter _: RCTPromiseRejectBlock
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      resolve(NetworkInfoProvider.current())
    }
  }

  @objc func securelyStore(
    _ key: NSString,
    payload: NSString,
    resolver: RCTPromiseResolveBlock,
    rejecter reject: RCTPromiseRejectBlock
  ) {
    do {
      try keychain.set(payload as String, key: key as String)
      resolver(true)
    } catch {
      reject("KeychainStoreError", error.localizedDescription, error)
    }
  }

  @objc func securelyRetrieve(
    _ key: NSString,
    resolver resolve: RCTPromiseResolveBlock,
    rejecter reject: RCTPromiseRejectBlock
  ) {
    do {
      let keyString = key as String
      if let value = try keychain.get(keyString) {
        resolve(value)
        return
      }

      guard let legacyValue = try legacyKeychain.get(keyString) else {
        resolve(nil)
        return
      }

      // Copy first and verify before leaving the legacy item untouched as a
      // fallback. Future reads stop here at the new service and never ask the
      // old ACL for access again.
      try keychain.set(legacyValue, key: keyString)
      guard try keychain.get(keyString) == legacyValue else {
        throw SolKeychainMigrationError.verificationFailed
      }
      resolve(legacyValue)
    } catch {
      reject("KeychainRetrieveError", error.localizedDescription, error)
    }
  }

  @objc func securelyRemove(
    _ key: NSString,
    resolver resolve: RCTPromiseResolveBlock,
    rejecter reject: RCTPromiseRejectBlock
  ) {
    do {
      let keyString = key as String
      try keychain.remove(keyString)
      try legacyKeychain.remove(keyString)
      resolve(true)
    } catch {
      reject("KeychainRemoveError", error.localizedDescription, error)
    }
  }

  @objc func showToast(_ text: String, variant: String, timeout: NSNumber) {
    DispatchQueue.main.async {
      ToastManager.shared.showToast(
        text, variant: variant, timeout: timeout, image: nil)
    }
  }

  @objc func useBackgroundOverlay(_ v: Bool) {
    //    appDelegate?.useBackgroundOverlay = v
  }

  @objc func hideNotch() {
    NotchHelper.shared.hideNotch()
  }

  @objc func showWifiQR(_ SSID: String, password: String) {
    let image = WifiQR(name: SSID, password: password)
    DispatchQueue.main.async {
      let wifiInfo = "SSID: \(SSID)\nPassword: \(password)"
      ToastManager.shared.showToast(
        wifiInfo, variant: "none", timeout: 30, image: image)
    }
  }

  @objc func generateQRCode(
    _ text: String,
    resolver resolve: RCTPromiseResolveBlock,
    rejecter reject: RCTPromiseRejectBlock
  ) {
    guard
      let image = QR(from: text, size: 10),
      let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
    else {
      reject("QRCodeError", "Could not generate QR code", nil)
      return
    }

    resolve("data:image/png;base64," + pngData.base64EncodedString())
  }

  @objc func hasFullDiskAccess(
    _ resolve: RCTPromiseResolveBlock,
    rejecter _: RCTPromiseRejectBlock
  ) {
    resolve(BookmarkHelper.hasFullDiskAccess())
  }

  @objc func getSafariBookmarks(
    _ resolve: RCTPromiseResolveBlock,
    rejecter _: RCTPromiseRejectBlock
  ) {
    let bookmarks = BookmarkHelper.getSafariBookmars()
    resolve(bookmarks)
  }

  @objc func quit() {
    DispatchQueue.main.async {
      NSApplication.shared.terminate(self)
    }
  }

  @objc func setStatusBarItemTitle(_ title: String) {
    StatusBarItemManager.shared.setStatusBarTitle(title)
  }

  @objc func setMediaKeyForwardingEnabled(_ v: Bool) {
    DispatchQueue.main.async {
      self.appDelegate?.setMediaKeyForwardingEnabled(v)
    }
  }

  @objc func openFilePicker(
    _ resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    DispatchQueue.main.async {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      if panel.runModal() == .OK {
        let fileName = panel.url?.absoluteString
        resolve(fileName)
      } else {
        reject(nil, nil, nil)
      }
    }
  }

  @objc func updateHotkeys(_ hotkeys: NSDictionary) {
    guard let hotkeys = hotkeys as? [String: String] else { return }
    HotKeyManager.shared.updateHotkeys(hotkeyMap: hotkeys)
  }

  @objc func setUpcomingEventEnabled(_ enabled: Bool) {
    StatusBarCalendarManager.shared.enabled = enabled
  }

  @objc func setHyperKeyEnabled(_ enabled: Bool) {
    if enabled {
      DispatchQueue.main.async {
        HotKeyManager.shared.setupCapsLockMonitoring()
      }
    } else {
      DispatchQueue.main.async {

        HotKeyManager.shared.resetCapsLockMonitoring()
      }
    }
  }

}
