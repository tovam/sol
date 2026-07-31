import Cocoa
import CoreServices
import Sentry

class Application {
  public var name: String
  public var localizedName: String
  public var url: String
  public var isRunning: Bool

  init(name: String, localizedName: String, url: String, isRunning: Bool) {
    self.name = name
    self.localizedName = localizedName
    self.url = url
    self.isRunning = isRunning
  }

  func toDictionary() -> [String: Any] {
    return [
      "name": name,
      "localizedName": localizedName,
      "url": url,
      "isRunning": isRunning,
    ]
  }
}

@objc public class ApplicationSearcher: NSObject {
  let searchDepth = 4
  let customSearchDepth = 12
  let wildcardTraversalDepth = 32
  let wildcardTraversalLimit = 50_000
  let fileManager = FileManager()

  private let configurationLock = NSLock()
  private var configuredSearchPaths: [String] = []

  let isAliasResourceKey: [URLResourceKey] = [
    .isAliasFileKey
  ]

  let resourceKeys: [URLResourceKey] = [
    .isExecutableKey,
    .isApplicationKey,
    .isSymbolicLinkKey,
  ]

  @objc public static let shared = ApplicationSearcher()

  // File watching
  private var eventStream: FSEventStreamRef?
  private var isWatchingFolders = false
  public var onApplicationsChanged: (() -> Void)?

  var fixedUrls: [URL] = [
    URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
  ]

  let ignoredPatterns: Set<String> = [
    "Audio MIDI Setup.app",
    "Script Editor.app",
    "Grapher.app",
    "Airport Utility.app",
    "ColorSync Utility.app",
    "Bluetooth File Exchange.app",
    "Tips",
    "Siri.app",
    ".DS_Store",
    ".localized",
    "Icon",
    "en_US.strings",
    "Tips.app",
  ]

  private var watchedDirectories: [String] = []
  private var wakeObserver: NSObjectProtocol?

  @objc public func setSearchPaths(_ paths: [String]) {
    var seen = Set<String>()
    let normalizedPaths = paths.compactMap(normalizeSearchPath).filter {
      seen.insert($0).inserted
    }

    configurationLock.lock()
    let changed = normalizedPaths != configuredSearchPaths
    configuredSearchPaths = normalizedPaths
    configurationLock.unlock()

    guard changed else { return }

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.stopWatchingFolders()
      self.startWatchingFolders()
    }
  }

  override init() {
    super.init()

    // Observe system wake notification to restart FSEventStream
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: OperationQueue.main
    ) { [weak self] _ in
      self?.handleWakeFromSleep()
    }

    startWatchingFolders()

    if #unavailable(macOS 14) {
      fixedUrls.append(
        URL(
          fileURLWithPath:
            "/System/Library/CoreServices/Applications/Screen Sharing.app"
        )
      )
    }

    if #available(macOS 15, *) {
      fixedUrls.append(
        URL(
          fileURLWithPath:
            "/System/Library/CoreServices/Applications/Keychain Access.app")
      )
    }
  }

  deinit {
    stopWatchingFolders()

    // Remove wake observer
    if let observer = wakeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      wakeObserver = nil
    }
  }

  // Start watching application directories for changes
  public func startWatchingFolders() {
    if isWatchingFolders {
      return
    }

    do {
      // Get all the application directories we want to watch
      let directoriesUrls = try getWatchedDirectories()
      for url in directoriesUrls {
        watchedDirectories.append(url.path)
      }

      var context = FSEventStreamContext(
        version: 0,
        info: Unmanaged.passUnretained(self).toOpaque(),
        retain: nil,
        release: nil,
        copyDescription: nil
      )

      let callback: FSEventStreamCallback = {
        (
          streamRef: ConstFSEventStreamRef,
          clientCallBackInfo: UnsafeMutableRawPointer?,
          numEvents: Int,
          eventPaths: UnsafeMutableRawPointer,
          eventFlags: UnsafePointer<FSEventStreamEventFlags>,
          eventIds: UnsafePointer<FSEventStreamEventId>
        ) in

        guard let info = clientCallBackInfo else { return }
        let myself = Unmanaged<ApplicationSearcher>.fromOpaque(info)
          .takeUnretainedValue()

        // Notify if a file was added, removed, renamed, or inode metadata changed
        for i in 0..<numEvents {
          let flags = eventFlags[i]
          if (flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0)
            || (flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0)
            || (flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0)
            || (flags & UInt32(kFSEventStreamEventFlagItemInodeMetaMod) != 0)
          {
            myself.processFileChanges()
            break
          }
        }
      }

      let pathsToWatch = watchedDirectories as CFArray

      // Create event stream
      eventStream = FSEventStreamCreate(
        kCFAllocatorDefault,
        callback,
        &context,
        pathsToWatch,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        10.0,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
      )

      if let eventStream = eventStream {
        let backgroundQueue = DispatchQueue(
          label: "com.sol.fsevents", qos: .utility)
        FSEventStreamSetDispatchQueue(eventStream, backgroundQueue)
        FSEventStreamStart(eventStream)
        isWatchingFolders = true
      }
    } catch {
      //      let breadcrumb = Breadcrumb(level: .error, category: "custom")
      //      breadcrumb.message =
      //        "Failed to start watching application folders: \(error.localizedDescription)"
      //      SentrySDK.addBreadcrumb(breadcrumb)
      //      SentrySDK.capture(error: error)
      print("💔 COuld not watch applications")
    }
  }

  public func stopWatchingFolders() {
    if let eventStream = eventStream, isWatchingFolders {
      FSEventStreamStop(eventStream)
      FSEventStreamInvalidate(eventStream)
      FSEventStreamRelease(eventStream)
      self.eventStream = nil
      isWatchingFolders = false
    }

    watchedDirectories.removeAll()
  }

  // Restart FSEventStream after wake
  private func handleWakeFromSleep() {
    stopWatchingFolders()
    startWatchingFolders()
  }

  private var debounceWorkItem: DispatchWorkItem?

  private func processFileChanges() {
    debounceWorkItem?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      guard let self = self else { return }

      DispatchQueue.main.async {
        self.onApplicationsChanged?()
      }
    }

    debounceWorkItem = workItem
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0, execute: workItem)
  }

  private func getApplicationDirectories() throws -> [URL] {
    var directories: [URL] = []

    // Get local application directory
    if let localApplicationUrl = try? FileManager.default.url(
      for: .applicationDirectory,
      in: .localDomainMask,
      appropriateFor: nil,
      create: false
    ) {
      directories.append(localApplicationUrl)
    }

    // Get system application directory
    if let systemApplicationUrl = try? FileManager.default.url(
      for: .applicationDirectory,
      in: .systemDomainMask,
      appropriateFor: nil,
      create: false
    ) {
      directories.append(systemApplicationUrl)
    }

    // Get user application directory
    if let userApplicationUrl = try? FileManager.default.url(
      for: .applicationDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: false
    ) {
      directories.append(userApplicationUrl)
    }

    return directories
  }

  private func currentSearchPaths() -> [String] {
    configurationLock.lock()
    let paths = configuredSearchPaths
    configurationLock.unlock()
    return paths
  }

  private func normalizeSearchPath(_ rawPath: String) -> String? {
    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let expanded = (trimmed as NSString).expandingTildeInPath
    guard expanded.hasPrefix("/") else { return nil }

    var standardized = (expanded as NSString).standardizingPath
    while standardized.count > 1 && standardized.hasSuffix("/") {
      standardized.removeLast()
    }
    return standardized
  }

  private func containsWildcard(_ path: String) -> Bool {
    return path.contains("*") || path.contains("?")
  }

  private func wildcardSearchRoot(for path: String) -> URL? {
    guard let wildcardIndex = path.firstIndex(where: { $0 == "*" || $0 == "?" }) else {
      let url = URL(fileURLWithPath: path)
      return url.pathExtension.lowercased() == "app"
        ? url.deletingLastPathComponent()
        : url
    }

    var prefix = String(path[..<wildcardIndex])
    if !prefix.hasSuffix("/") {
      prefix = (prefix as NSString).deletingLastPathComponent
    }
    if prefix.isEmpty {
      prefix = "/"
    }
    return URL(fileURLWithPath: prefix)
  }

  private func getWatchedDirectories() throws -> [URL] {
    var urls = try getApplicationDirectories()
    urls.append(contentsOf: currentSearchPaths().compactMap(wildcardSearchRoot))

    var seen = Set<String>()
    return urls.filter { url in
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        return false
      }
      return seen.insert(url.standardizedFileURL.path).inserted
    }
  }

  @objc public func getAllApplications() -> [[String: Any]] {
    var appUrls: [URL] = []
    appUrls.append(contentsOf: fixedUrls)

    let runningApps = NSWorkspace.shared.runningApplications

    do {
      let directories = try getApplicationDirectories()
      for directory in directories {
        appUrls.append(contentsOf: getApplicationUrlsAt(directory))
      }
    } catch {
      let breadcrumb = Breadcrumb(level: .info, category: "custom")
      breadcrumb.message = "Error getting all applications at localDomainMask"
      SentrySDK.addBreadcrumb(breadcrumb)
      SentrySDK.capture(error: error)
    }

    for searchPath in currentSearchPaths() {
      appUrls.append(contentsOf: getApplicationUrls(for: searchPath))
    }

    var applications = [String: Application]()

    for var url in appUrls {
      do {
        let resourceValues = try url.resourceValues(
          forKeys: Set(isAliasResourceKey))
        if resourceValues.isAliasFile! {
          url = try URL(resolvingAliasFileAt: url)
        }
      } catch {
        // Could not resolve an alias file. More than likely just a dangling alias from a botched de-installation
        continue
      }

      do {
        // File doesn't exist but it was listed?! I don't know how this is happening but it does
        // at least on sentry it is showing
        if !fileManager.fileExists(atPath: url.path) {
          continue
        }

        let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))

        if resourceValues.isExecutable! && resourceValues.isApplication! {
          let name = url.deletingPathExtension().lastPathComponent
          var localizedName = name
          if let mdItem = MDItemCreateWithURL(nil, url as CFURL),
            let displayName = MDItemCopyAttribute(mdItem, kMDItemDisplayName) as? String
          {
            localizedName =
              displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
          }
          let urlStr = url.absoluteString

          applications[urlStr] = Application(
            name: name, localizedName: localizedName, url: urlStr, isRunning: false)
        }
      } catch {
        let breadcrumb = Breadcrumb(level: .info, category: "custom")
        breadcrumb.message =
          "Error resolving info for application at \(url): \(error.localizedDescription)"
        SentrySDK.addBreadcrumb(breadcrumb)
        SentrySDK.capture(error: error)
      }
    }

    // Iterate through the running apps and mark those running
    for runningApp in runningApps {
      if let runningBundleUrl = runningApp.bundleURL?.absoluteString {
        if let application = applications[runningBundleUrl] {
          application.isRunning = true
        }
      }
    }

    return applications.values.map { $0.toDictionary() }
  }

  private func getApplicationUrls(for searchPath: String) -> [URL] {
    if containsWildcard(searchPath) {
      return getApplicationUrlsMatching(searchPath)
    }
    return getApplicationUrlsAt(
      URL(fileURLWithPath: searchPath),
      maximumDepth: customSearchDepth
    )
  }

  private func componentMatcher(for wildcard: String) -> NSRegularExpression? {
    var pattern = "^"
    for character in wildcard {
      switch character {
      case "*":
        pattern += ".*"
      case "?":
        pattern += "."
      default:
        pattern += NSRegularExpression.escapedPattern(for: String(character))
      }
    }
    pattern += "$"
    return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
  }

  private func component(_ value: String, matches wildcard: String) -> Bool {
    guard let matcher = componentMatcher(for: wildcard) else { return false }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return matcher.firstMatch(in: value, options: [], range: range) != nil
  }

  private func directoryContents(at url: URL) -> [URL] {
    do {
      return try fileManager.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      )
    } catch {
      return []
    }
  }

  private func isDirectory(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private func getApplicationUrlsMatching(_ searchPath: String) -> [URL] {
    guard let root = wildcardSearchRoot(for: searchPath), isDirectory(root) else {
      return []
    }

    let rootPath = root.standardizedFileURL.path
    var suffix = String(searchPath.dropFirst(min(rootPath.count, searchPath.count)))
    suffix = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let components = suffix.isEmpty
      ? []
      : (suffix as NSString).pathComponents.filter { $0 != "/" }

    var applicationUrls: [URL] = []
    var seenApplications = Set<String>()
    var visitedDirectories = Set<String>()
    var traversedEntries = 0

    func addMatchedPath(_ url: URL) {
      if url.pathExtension.lowercased() == "app" {
        let path = url.standardizedFileURL.path
        if seenApplications.insert(path).inserted {
          applicationUrls.append(url)
        }
        return
      }

      guard isDirectory(url) else { return }
      for appURL in getApplicationUrlsAt(url, maximumDepth: customSearchDepth) {
        let path = appURL.standardizedFileURL.path
        if seenApplications.insert(path).inserted {
          applicationUrls.append(appURL)
        }
      }
    }

    func expand(_ url: URL, componentIndex: Int, depth: Int) {
      guard traversedEntries < wildcardTraversalLimit,
        depth <= wildcardTraversalDepth
      else {
        return
      }

      if componentIndex >= components.count {
        addMatchedPath(url)
        return
      }

      let wildcard = components[componentIndex]
      if wildcard == "**" {
        // ** can match no directory at all.
        expand(url, componentIndex: componentIndex + 1, depth: depth)

        guard depth < wildcardTraversalDepth else { return }
        let resolvedDirectory = url.resolvingSymlinksInPath().standardizedFileURL.path
        let visitKey = "\(componentIndex):\(resolvedDirectory)"
        guard visitedDirectories.insert(visitKey).inserted else { return }

        for child in directoryContents(at: url) {
          traversedEntries += 1
          if traversedEntries >= wildcardTraversalLimit { return }
          if child.pathExtension.lowercased() == "app" {
            if componentIndex == components.count - 1 {
              addMatchedPath(child)
            }
          } else if isDirectory(child) {
            expand(child, componentIndex: componentIndex, depth: depth + 1)
          }
        }
        return
      }

      if containsWildcard(wildcard) {
        for child in directoryContents(at: url) {
          traversedEntries += 1
          if traversedEntries >= wildcardTraversalLimit { return }
          guard component(child.lastPathComponent, matches: wildcard) else {
            continue
          }
          expand(child, componentIndex: componentIndex + 1, depth: depth + 1)
        }
        return
      }

      let child = url.appendingPathComponent(wildcard)
      traversedEntries += 1
      guard fileManager.fileExists(atPath: child.path) else { return }
      expand(child, componentIndex: componentIndex + 1, depth: depth + 1)
    }

    expand(root, componentIndex: 0, depth: 0)
    return applicationUrls
  }

  private func getApplicationUrlsAt(
    _ url: URL,
    depth: Int = 0,
    maximumDepth: Int? = nil
  ) -> [URL] {
    if !fileManager.fileExists(atPath: url.path) {
      return []
    }

    let depthLimit = maximumDepth ?? searchDepth
    if depth > depthLimit {
      return []
    }

    if ignoredPatterns.contains(url.lastPathComponent) {
      return []
    }

    if url.pathExtension == "app" {
      return [url]
    }

    // Check if this is a symbolic link and resolve it
    var resolvedUrl = url
    do {
      let resourceValues = try url.resourceValues(forKeys: Set([.isSymbolicLinkKey]))
      if resourceValues.isSymbolicLink == true {
        resolvedUrl = url.resolvingSymlinksInPath()

        // Check if the resolved path still exists and is not in ignored patterns
        if !fileManager.fileExists(atPath: resolvedUrl.path) {
          return []
        }

        if ignoredPatterns.contains(resolvedUrl.lastPathComponent) {
          return []
        }

        // If the symbolic link points to an app, return it
        if resolvedUrl.pathExtension == "app" {
          return [resolvedUrl]
        }
      }
    } catch {
      // If we can't determine if it's a symbolic link, continue with the original URL
    }

    do {
      if resolvedUrl.hasDirectoryPath {
        var urls: [URL] = []
        let contents = try fileManager.contentsOfDirectory(
          at: resolvedUrl,
          includingPropertiesForKeys: [],
          options: [
            .skipsSubdirectoryDescendants,
            .skipsPackageDescendants,
          ]
        )

        contents.forEach {
          let subUrls = getApplicationUrlsAt(
            $0,
            depth: depth + 1,
            maximumDepth: depthLimit
          )
          urls.append(contentsOf: subUrls)
        }

        return urls
      } else {
        return []
      }
    } catch {
      let nsError = error as NSError

      // Silently ignore permission errors
      if nsError.domain == NSCocoaErrorDomain
        && nsError.code == NSFileReadNoPermissionError
      {
        return []
      }

      // Silently ignore "file not found" errors - these occur with broken symlinks
      // or race conditions where files are deleted between directory listing and access
      if nsError.domain == NSPOSIXErrorDomain && nsError.code == 2 {
        return []
      }
      if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
        return []
      }

      let breadcrumb = Breadcrumb(level: .info, category: "custom")
      breadcrumb.message =
        "Could not resolve apps url at \(url): \(error.localizedDescription)"
      SentrySDK.addBreadcrumb(breadcrumb)
      SentrySDK.capture(error: error)
      return []
    }
  }
}
