import Foundation

enum Platform: String, CaseIterable, Identifiable {
    case ios, android
    var id: String { rawValue }
    var label: String { self == .ios ? "iOS" : "Android" }
}

enum DeviceState: Equatable {
    case shutdown, booting, booted, shuttingDown

    var label: String {
        switch self {
        case .shutdown: "Off"
        case .booting: "Booting…"
        case .booted: "Running"
        case .shuttingDown: "Stopping…"
        }
    }
}

struct Device: Identifiable, Hashable {
    /// Simulator UDID or Android AVD name.
    let id: String
    let name: String
    let platform: Platform
    let osVersion: String
    var state: DeviceState
    /// Android emulator serial (e.g. emulator-5554) while running.
    var serial: String?
    /// agent-device session that currently holds this device.
    var claimedBy: String?

    var isTablet: Bool {
        let lower = name.lowercased()
        return lower.contains("ipad") || lower.contains("tablet")
    }

    var symbol: String {
        switch platform {
        case .ios: isTablet ? "ipad" : "iphone"
        case .android: isTablet ? "flipphone" : "candybarphone"
        }
    }

    /// The selector a remote agent passes to agent-device for this device.
    var agentSelector: String {
        switch platform {
        case .ios: "--platform ios --udid \(id)"
        case .android: serial.map { "--platform android --serial \($0)" } ?? "--platform android --device \(id)"
        }
    }
}

struct ExpoApp: Equatable {
    let directory: URL
    let name: String
    let bundleIdentifier: String?
    let androidPackage: String?
    let sdkVersion: String?

    static func load(from directory: URL) -> ExpoApp? {
        let fm = FileManager.default
        let packageURL = directory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageURL),
              let package = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let deps = (package["dependencies"] as? [String: String]) ?? [:]
        var name = (package["name"] as? String) ?? directory.lastPathComponent
        var bundle: String?, androidPackage: String?

        let appJSON = directory.appendingPathComponent("app.json")
        if fm.fileExists(atPath: appJSON.path),
           let data = try? Data(contentsOf: appJSON),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let expo = (root["expo"] as? [String: Any]) ?? root
            name = (expo["name"] as? String) ?? name
            bundle = (expo["ios"] as? [String: Any])?["bundleIdentifier"] as? String
            androidPackage = (expo["android"] as? [String: Any])?["package"] as? String
        }
        return ExpoApp(
            directory: directory,
            name: name,
            bundleIdentifier: bundle,
            androidPackage: androidPackage,
            sdkVersion: deps["expo"]
        )
    }
}
