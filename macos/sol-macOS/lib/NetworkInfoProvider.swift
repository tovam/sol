import CoreWLAN
import Foundation
import SystemConfiguration

enum NetworkInfoProvider {
  static func current() -> [String: Any] {
    guard
      let store = SCDynamicStoreCreate(
        nil, "SolNetworkInfo" as CFString, nil, nil)
    else {
      return [:]
    }

    let globalIPv4 = value(
      store: store, key: "State:/Network/Global/IPv4")
    let interface = globalIPv4?["PrimaryInterface"] as? String
    let router = globalIPv4?["Router"] as? String

    let interfaceIPv4 = interface.flatMap {
      value(store: store, key: "State:/Network/Interface/\($0)/IPv4")
    }
    let localAddress =
      (interfaceIPv4?["Addresses"] as? [String])?.first

    let globalDNS = value(
      store: store, key: "State:/Network/Global/DNS")
    let dnsServers = globalDNS?["ServerAddresses"] as? [String] ?? []

    var result: [String: Any] = [
      "hostname": Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
      "dns": dnsServers,
    ]

    if let interface {
      result["interface"] = interface
    }
    if let localAddress {
      result["localIp"] = localAddress
    }
    if let router {
      result["gateway"] = router
    }

    let wifiInterface = interface.flatMap {
      CWWiFiClient.shared().interface(withName: $0)
    }
    if let ssid = wifiInterface?.ssid(), !ssid.isEmpty {
      result["ssid"] = ssid
      result["connection"] = "Wi-Fi"
    } else if interface?.hasPrefix("en") == true {
      result["connection"] = "Ethernet"
    } else if interface != nil {
      result["connection"] = "Network"
    }

    return result
  }

  private static func value(
    store: SCDynamicStore, key: String
  ) -> [String: Any]? {
    return SCDynamicStoreCopyValue(store, key as CFString)
      as? [String: Any]
  }
}
