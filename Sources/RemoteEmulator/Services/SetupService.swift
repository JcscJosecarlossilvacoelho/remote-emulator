import AppKit
import Foundation

/// First-run checks (Xcode, Android SDK, Node, agent-device, Tailscale) and
/// taking over hosts that were started outside the app (e.g. LaunchAgents).
@MainActor
final class SetupService: ObservableObject {
    enum Check: Equatable {
        case checking
        case ok(String)
        case warning(String)
        case missing(String)

        var isOK: Bool { if case .ok = self { true } else { false } }
        var isBlocking: Bool { if case .missing = self { true } else { false } }
        var detail: String {
            switch self {
            case .checking: "Checking…"
            case .ok(let s), .warning(let s), .missing(let s): s
            }
        }
    }

    @Published private(set) var xcode: Check = .checking
    @Published private(set) var android: Check = .checking
    @Published private(set) var node: Check = .checking
    @Published private(set) var agentDevice: Check = .checking
    @Published private(set) var tailscale: Check = .checking
    @Published private(set) var installing = false
    @Published private(set) var installError: String?
    /// LaunchAgents in ~/Library/LaunchAgents that run an agent-device host or Metro.
    @Published private(set) var externalAgents: [URL] = []

    /// Hide machine-specific details (README screenshots).
    var demoMode = false

    /// At least one device platform and the engine are ready.
    var canHost: Bool { (xcode.isOK || android.isOK) && agentDevice.isOK && !node.isBlocking }

    func runChecks() async {
        xcode = .checking; android = .checking; node = .checking; agentDevice = .checking; tailscale = .checking
        async let x = checkXcode()
        async let a = checkAndroid()
        async let n = checkNode()
        async let d = checkAgentDevice()
        async let t = checkTailscale()
        (xcode, android, node, agentDevice, tailscale) = await (x, a, n, d, t)
        findExternalAgents()
    }

    func installAgentDevice() async {
        installing = true
        installError = nil
        let result = await Shell.run("npm", ["install", "-g", "agent-device@latest"], timeout: 300)
        installing = false
        if !result.ok {
            installError = result.stderr.split(whereSeparator: \.isNewline).suffix(3).joined(separator: "\n")
        }
        agentDevice = await checkAgentDevice()
    }

    func openTailscale() {
        if Shell.which("tailscale") == nil {
            NSWorkspace.shared.open(URL(string: "https://tailscale.com/download/mac")!)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Tailscale.app"))
        }
    }

    // MARK: - Take over external hosts

    func findExternalAgents() {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        externalAgents = files.filter { url in
            guard url.pathExtension == "plist",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return text.contains("agent-device") || text.contains("agent-host")
        }
    }

    /// Unloads those LaunchAgents and archives their plists (nothing is deleted),
    /// so this app becomes the single owner of the host and Metro.
    func takeOver() async {
        let archive = HostPaths.directory.appendingPathComponent("disabled-launch-agents")
        try? FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        for plist in externalAgents {
            await Shell.run("launchctl", ["bootout", "gui/\(getuid())", plist.path], timeout: 15)
            let target = archive.appendingPathComponent(plist.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.moveItem(at: plist, to: target)
        }
        findExternalAgents()
    }

    // MARK: - Checks

    private func checkXcode() async -> Check {
        guard Shell.which("xcrun") != nil else { return .missing("Install Xcode for iOS simulators") }
        let result = await Shell.run("xcrun", ["simctl", "list", "runtimes", "-j"], timeout: 30)
        guard result.ok else { return .missing("Open Xcode once to finish installing it") }
        let count = result.stdout.components(separatedBy: "\"platform\" : \"iOS\"").count - 1
        return count > 0 ? .ok("\(count) iOS runtime\(count == 1 ? "" : "s")") : .warning("No iOS runtime — add one in Xcode › Settings › Components")
    }

    private func checkAndroid() async -> Check {
        guard Shell.which("emulator") != nil, Shell.which("adb") != nil else {
            return .missing("Install Android Studio for emulators")
        }
        let avds = await Shell.run("emulator", ["-list-avds"], timeout: 20)
        let count = avds.stdout.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("INFO") && !$0.isEmpty }.count
        return count > 0 ? .ok("\(count) emulator\(count == 1 ? "" : "s")") : .warning("Create an emulator in Android Studio › Device Manager")
    }

    private func checkNode() async -> Check {
        guard Shell.which("node") != nil else { return .missing("Install Node.js 22.12 or newer") }
        let raw = await Shell.run("node", ["--version"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.dropFirst().split(separator: ".").compactMap { Int($0) }
        let ok = parts.count >= 2 && (parts[0] > 22 || (parts[0] == 22 && parts[1] >= 12))
        return ok ? .ok("Node \(raw)") : .missing("Node \(raw) — needs 22.12 or newer")
    }

    private func checkAgentDevice() async -> Check {
        guard Shell.which("agent-device") != nil else { return .missing("Not installed") }
        let version = await Shell.run("agent-device", ["--version"], timeout: 15).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .ok("agent-device \(version)")
    }

    private func checkTailscale() async -> Check {
        guard Shell.which("tailscale") != nil else { return .missing("Install Tailscale to share privately") }
        let result = await Shell.run("tailscale", ["status", "--json"], timeout: 10)
        guard let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              json["BackendState"] as? String == "Running" else {
            return .warning("Installed but not connected — open Tailscale and sign in")
        }
        let certs = json["CertDomains"] as? [String] ?? []
        guard let host = certs.first else {
            return .warning("Enable MagicDNS + HTTPS certificates in the Tailscale admin console")
        }
        return .ok(demoMode ? "my-mac.tailnet-name.ts.net" : host)
    }
}
