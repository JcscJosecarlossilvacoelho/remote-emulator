import Foundation

/// Discovers and controls iOS simulators and Android emulators on this Mac.
@MainActor
final class DeviceService: ObservableObject {
    @Published private(set) var devices: [Device] = []
    @Published private(set) var lastError: String?
    @Published private(set) var hasXcode = Shell.which("xcrun") != nil
    @Published private(set) var hasAndroidSDK = Shell.which("emulator") != nil

    /// Devices we just asked to boot/stop; keeps the spinner until the OS agrees.
    private var pending: [String: (state: DeviceState, since: Date)] = [:]
    private var refreshing = false

    var runningCount: Int { devices.filter { $0.state == .booted }.count }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        async let ios = loadIOS()
        async let android = loadAndroid()
        async let claims = loadClaims()
        var all = await ios + android
        let owners = await claims

        let now = Date()
        for index in all.indices {
            let device = all[index]
            all[index].claimedBy = owners[device.id] ?? device.serial.flatMap { owners[$0] }
            if let wanted = pending[device.id] {
                let settled = (wanted.state == .booting && device.state == .booted)
                    || (wanted.state == .shuttingDown && device.state == .shutdown)
                if settled || now.timeIntervalSince(wanted.since) > 180 {
                    pending[device.id] = nil
                } else {
                    all[index].state = wanted.state
                }
            }
        }
        devices = all.sorted { lhs, rhs in
            if (lhs.state == .shutdown) != (rhs.state == .shutdown) { return lhs.state != .shutdown }
            if lhs.platform != rhs.platform { return lhs.platform == .ios }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func boot(_ device: Device) {
        mark(device, .booting)
        Task {
            switch device.platform {
            case .ios:
                let result = await Shell.run("xcrun", ["simctl", "boot", device.id])
                if !result.ok, !result.stderr.contains("current state: Booted") { report(result.stderr) }
                await Shell.run("open", ["-a", "Simulator", "--args", "-CurrentDeviceUDID", device.id])
            case .android:
                Shell.launchDetached("emulator", ["-avd", device.id])
            }
            await refresh()
        }
    }

    func shutdown(_ device: Device) {
        mark(device, .shuttingDown)
        Task {
            switch device.platform {
            case .ios:
                let result = await Shell.run("xcrun", ["simctl", "shutdown", device.id])
                if !result.ok { report(result.stderr) }
            case .android:
                if let serial = device.serial {
                    await Shell.run("adb", ["-s", serial, "emu", "kill"])
                }
            }
            await refresh()
        }
    }

    private func mark(_ device: Device, _ state: DeviceState) {
        pending[device.id] = (state, Date())
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index].state = state
        }
    }

    private func report(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        lastError = trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - iOS

    private func loadIOS() async -> [Device] {
        guard hasXcode else { return [] }
        let result = await Shell.run("xcrun", ["simctl", "list", "devices", "available", "-j"])
        guard result.ok,
              let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let runtimes = json["devices"] as? [String: [[String: Any]]]
        else { return [] }

        var devices: [Device] = []
        for (runtime, entries) in runtimes where runtime.contains(".iOS-") {
            let version = Self.runtimeVersion(runtime)
            for entry in entries {
                guard let udid = entry["udid"] as? String, let name = entry["name"] as? String else { continue }
                let state = entry["state"] as? String
                devices.append(Device(
                    id: udid,
                    name: name,
                    platform: .ios,
                    osVersion: version,
                    state: state == "Booted" ? .booted : (state == "Booting" ? .booting : .shutdown)
                ))
            }
        }
        return devices
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-5" → "iOS 26.5"
    nonisolated static func runtimeVersion(_ runtime: String) -> String {
        guard let last = runtime.split(separator: ".").last else { return runtime }
        let parts = last.split(separator: "-")
        guard let os = parts.first else { return String(last) }
        return "\(os) " + parts.dropFirst().joined(separator: ".")
    }

    // MARK: - Android

    private func loadAndroid() async -> [Device] {
        guard hasAndroidSDK else { return [] }
        let avds = await Shell.run("emulator", ["-list-avds"])
        let names = avds.stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("INFO") }

        // Map running emulator serials to their AVD names.
        var running: [String: String] = [:]
        let adb = await Shell.run("adb", ["devices"])
        for line in adb.stdout.split(whereSeparator: \.isNewline) {
            let cols = line.split(whereSeparator: \.isWhitespace)
            guard cols.count >= 2, cols[0].hasPrefix("emulator-"), cols[1] == "device" else { continue }
            let serial = String(cols[0])
            let name = await Shell.run("adb", ["-s", serial, "emu", "avd", "name"], timeout: 5)
            if let avd = name.stdout.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespacesAndNewlines) {
                running[avd] = serial
            }
        }

        return names.map { name in
            Device(
                id: name,
                name: name.replacingOccurrences(of: "_", with: " "),
                platform: .android,
                osVersion: Self.androidVersion(avd: name),
                state: running[name] != nil ? .booted : .shutdown,
                serial: running[name]
            )
        }
    }

    nonisolated static func androidVersion(avd: String) -> String {
        let config = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".android/avd/\(avd).avd/config.ini")
        guard let text = try? String(contentsOf: config, encoding: .utf8),
              let match = text.range(of: #"android-(\d+)"#, options: .regularExpression)
        else { return "Android" }
        let api = Int(text[match].dropFirst("android-".count)) ?? 0
        let names: [Int: String] = [36: "16", 35: "15", 34: "14", 33: "13", 32: "12L", 31: "12", 30: "11", 29: "10"]
        return names[api].map { "Android \($0)" } ?? "Android API \(api)"
    }

    // MARK: - agent-device claims

    /// Which agent-device session holds each device (device id or serial → session).
    private func loadClaims() async -> [String: String] {
        guard Shell.which("agent-device") != nil else { return [:] }
        let result = await Shell.run("agent-device", ["device", "status", "--json"],
                                     cwd: FileManager.default.temporaryDirectory, timeout: 15)
        guard let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let data = json["data"] as? [String: Any],
              let claims = data["claims"] as? [[String: Any]]
        else { return [:] }

        var owners: [String: String] = [:]
        for claim in claims where (claim["classification"] as? String) == "live" {
            guard let device = claim["device"] as? [String: Any],
                  let id = device["id"] as? String else { continue }
            owners[id] = ((claim["owner"] as? [String: Any])?["session"] as? String) ?? "agent"
        }
        return owners
    }
}
