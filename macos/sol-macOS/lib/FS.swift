import Foundation

@objc public class FS: NSObject {
  @objc static func ls(path: String) throws -> [String] {
    return try FileManager.default.contentsOfDirectory(atPath: path)
  }

  @objc static func exists(path: String) -> Bool {
    return FileManager.default.fileExists(atPath: path)
  }

  @objc static func readFile(path: String) -> String? {
    if FileManager.default.fileExists(atPath: path) {
      guard let data = FileManager.default.contents(atPath: path) else {
        return nil
      }
      
      let str = String(decoding: data, as: UTF8.self)
      return str
    } else {
      return nil
    }
  }
  
  @objc static func writeFile(path: String, contents: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    let parentDir = url.deletingLastPathComponent()

    if !FileManager.default.fileExists(atPath: parentDir.path) {
      do {
        try FileManager.default.createDirectory(
          at: parentDir,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
      } catch {
        return false
      }
    }

    do {
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: parentDir.path)
    } catch {
      return false
    }

    guard let data = contents.data(using: .utf8) else {
      return false
    }

    let temporaryURL = parentDir.appendingPathComponent(
      ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    guard
      FileManager.default.createFile(
        atPath: temporaryURL.path,
        contents: data,
        attributes: [.posixPermissions: 0o600])
    else {
      return false
    }

    defer {
      try? FileManager.default.removeItem(at: temporaryURL)
    }

    do {
      if FileManager.default.fileExists(atPath: path) {
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o600],
          ofItemAtPath: path)
        _ = try FileManager.default.replaceItemAt(
          url,
          withItemAt: temporaryURL)
      } else {
        try FileManager.default.moveItem(at: temporaryURL, to: url)
      }
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: path)
      return true
    } catch {
      return false
    }
  }

  static func copyFileFromUrl(_ url: URL, toPath path: String) throws {
    if exists(path: path) {
      try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }
    try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: path))
  }
  
  static func delete(_ path: String) throws {
    try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
  }
}
