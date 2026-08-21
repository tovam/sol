import Foundation
import Security

private enum AISecretsStoreError: LocalizedError {
  case invalidEncoding
  case keychain(operation: String, status: OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidEncoding:
      return "The AI credentials could not be encoded."
    case .keychain(let operation, let status):
      let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
      return "Could not \(operation) AI credentials in the macOS Keychain: \(detail)"
    }
  }
}

final class AISecretsStore {
  static let shared = AISecretsStore()

  // This intentionally uses a new item identity. Previous experimental
  // Keychain entries were signed ad hoc and can retain stale ACLs that prompt
  // on every build. The installer now gives Sol a stable designated
  // requirement, so the default macOS Keychain ACL follows future installs.
  private let service = "com.ospfranco.sol.ai-credentials.v3"
  private let account = "provider-api-keys"

  private init() {}

  func read() throws -> String? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard
        let data = result as? Data,
        let value = String(data: data, encoding: .utf8)
      else {
        throw AISecretsStoreError.invalidEncoding
      }
      return value
    case errSecItemNotFound:
      return nil
    default:
      throw AISecretsStoreError.keychain(operation: "read", status: status)
    }
  }

  func write(_ value: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw AISecretsStoreError.invalidEncoding
    }

    var lookup = baseQuery
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    lookup[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    let update: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrLabel as String: "Sol AI API keys",
      kSecAttrDescription as String: "API credentials used only by Sol",
    ]

    // Probe with UI explicitly forbidden before updating. If an unexpected ACL
    // no longer trusts this build, Sol reports the error instead of opening a
    // password dialog. The actual update uses the clean item query accepted by
    // SecItemUpdate after this access check succeeds.
    let lookupStatus = SecItemCopyMatching(lookup as CFDictionary, nil)
    switch lookupStatus {
    case errSecSuccess:
      let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
      guard updateStatus == errSecSuccess else {
        throw AISecretsStoreError.keychain(operation: "update", status: updateStatus)
      }
    case errSecItemNotFound:
      var item = baseQuery
      item[kSecValueData as String] = data
      item[kSecAttrLabel as String] = "Sol AI API keys"
      item[kSecAttrDescription as String] = "API credentials used only by Sol"

      // Omitting kSecAttrAccess is deliberate. The default file-keychain ACL
      // trusts only the creating app and tracks its designated requirement.
      let addStatus = SecItemAdd(item as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw AISecretsStoreError.keychain(operation: "save", status: addStatus)
      }
    default:
      throw AISecretsStoreError.keychain(operation: "access", status: lookupStatus)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
