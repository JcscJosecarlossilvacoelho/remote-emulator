import AppKit
import Foundation

/// Runs the agent-device proxy and publishes it privately over Tailscale.
@MainActor
final class HostService: ObservableObject {
    enum Status: Equatable {
        case stopped, starting
        case running(version: String)
        /// A proxy started outside the app (terminal, launchd) answers on the port.
        case external(version: String)
        case failed(String)

        var isUp: Bool {
            switch self {
            case .running, .external: true
            default: false
            }
        }
    }

    enum Tailscale: Equatable {
        case notInstalled, stopped
        case running(host: String)
    }

    enum CommandStyle: String, CaseIterable, Identifiable {
        case posix = "macOS / Linux"
        case powershell = "Windows PowerShell"
        case claude = "Claude Code (MCP)"
        var id: String { rawValue }
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var tailscale: Tailscale = .stopped
    @Published private(set) var serveActive = false
    @Published private(set) var cliVersion: String?
    @Published private(set) var token: String = HostPaths.readOrCreateToken()
    /// False when the proxy answers but its agent-device daemon does not.
    @Published private(set) var daemonHealthy = true

    let process = ManagedProcess(name: "agent-device proxy")
    var port: Int { UserDefaults.standard.object(forKey: "proxyPort") as? Int ?? 4310 }
    var sessionName: String { UserDefaults.standard.string(forKey: "sessionName") ?? "remote-agent" }

    /// Hide machine-specific details (used for README screenshots).
    var demoMode = false

    var remoteHost: String? {
        if demoMode { return "my-mac.tailnet-name.ts.net" }
        if case .running(let host) = tailscale { return host }
        return nil
    }

    var remoteURL: String {
        if let remoteHost { return "https://\(remoteHost)/agent-device" }
        return "http://127.0.0.1:\(port)/agent-device"
    }

    var isPrivatelyShared: Bool { demoMode || (remoteHost != nil && serveActive) }

    func start() {
        guard !process.isRunning else { return }
        status = .starting
        Task {
            // Never start a second proxy on a port that already answers.
            if let version = await health() {
                status = .external(version: version)
                await shareOnTailnet()
                return
            }
            guard Shell.which("agent-device") != nil else {
                status = .failed("agent-device not found. Install it with: npm install -g agent-device")
                return
            }
            token = HostPaths.readOrCreateToken()
            do {
                try process.start("agent-device", [
                    "proxy", "--host", "127.0.0.1", "--port", String(port), "--daemon-auth-token", token,
                ], cwd: HostPaths.directory,
                   // The daemon exits after 5 min idle by default; a host must stay up.
                   environment: ["AGENT_DEVICE_DAEMON_IDLE_TIMEOUT_MS": "0"],
                   redacting: [token])
            } catch {
                status = .failed(error.localizedDescription)
                return
            }
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(500))
                if let version = await health() {
                    status = .running(version: version)
                    await shareOnTailnet()
                    return
                }
                if !process.isRunning { break }
            }
            status = .failed("The proxy did not answer on port \(port). Check the logs.")
        }
    }

    func stop() {
        process.stop()
        status = .stopped
    }

    func rotateToken() {
        token = HostPaths.rotateToken()
        if process.isRunning { restart() }
    }

    func poll() async {
        if cliVersion == nil, Shell.which("agent-device") != nil {
            let result = await Shell.run("agent-device", ["--version"], timeout: 10)
            cliVersion = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        await refreshTailscale()
        if status == .starting { return }
        token = HostPaths.readOrCreateToken()
        if let version = await health() {
            status = process.isRunning ? .running(version: version) : .external(version: version)
            // Self-heal a proxy we own whose daemon went away.
            unhealthyPolls = daemonHealthy ? 0 : unhealthyPolls + 1
            if process.isRunning, unhealthyPolls >= 2 {
                unhealthyPolls = 0
                restart()
            }
        } else if status.isUp {
            status = process.isRunning ? .failed("The proxy stopped answering.") : .stopped
        }
    }

    func restart() {
        stop()
        Task {
            try? await Task.sleep(for: .seconds(1))
            start()
        }
    }

    private var unhealthyPolls = 0

    func connectCommand(_ style: CommandStyle) -> String {
        switch style {
        case .posix:
            return """
            npm install -g agent-device@\(cliVersion ?? "latest")
            export AGENT_DEVICE_DAEMON_AUTH_TOKEN='\(token)'
            export AGENT_DEVICE_SESSION=\(sessionName)
            agent-device connect proxy --daemon-base-url \(remoteURL)
            agent-device devices
            """
        case .powershell:
            return """
            npm install -g agent-device@\(cliVersion ?? "latest")
            $env:AGENT_DEVICE_DAEMON_AUTH_TOKEN = '\(token)'
            $env:AGENT_DEVICE_SESSION = '\(sessionName)'
            agent-device connect proxy --daemon-base-url \(remoteURL)
            agent-device devices
            """
        case .claude:
            return """
            export AGENT_DEVICE_DAEMON_AUTH_TOKEN='\(token)'
            export AGENT_DEVICE_SESSION=\(sessionName)
            agent-device connect proxy --daemon-base-url \(remoteURL)
            claude mcp add --transport stdio --scope user agent-device -- agent-device mcp
            """
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Private

    /// Version of the proxy answering on the port, or nil when nothing answers.
    /// Updates `daemonHealthy` from the proxy's view of its upstream daemon.
    private func health() async -> String? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            daemonHealthy = false
            return "?"
        }
        daemonHealthy = json["ok"] as? Bool == true
        let upstream = json["upstream"] as? [String: Any]
        return (json["version"] ?? upstream?["version"]) as? String ?? "?"
    }

    private func refreshTailscale() async {
        guard Shell.which("tailscale") != nil else {
            tailscale = .notInstalled
            return
        }
        let result = await Shell.run("tailscale", ["status", "--json"], timeout: 10)
        guard let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              json["BackendState"] as? String == "Running",
              let me = json["Self"] as? [String: Any],
              let dns = me["DNSName"] as? String, !dns.isEmpty
        else {
            tailscale = .stopped
            serveActive = false
            return
        }
        tailscale = .running(host: dns.hasSuffix(".") ? String(dns.dropLast()) : dns)
        let serve = await Shell.run("tailscale", ["serve", "status"], timeout: 10)
        serveActive = serve.stdout.contains(":\(port)")
    }

    /// `tailscale serve` keeps the proxy reachable only inside your tailnet (never Funnel).
    private func shareOnTailnet() async {
        await refreshTailscale()
        guard case .running = tailscale, !serveActive else { return }
        await Shell.run("tailscale", ["serve", "--bg", "localhost:\(port)"], timeout: 20)
        await refreshTailscale()
    }
}
