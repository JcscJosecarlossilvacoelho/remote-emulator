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
        case prompt = "AI agent prompt"
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

    let process = ManagedProcess(name: "agent-device proxy",
                                 logFile: HostPaths.directory.appendingPathComponent("proxy.log"))
    /// True while the user wants the host up: a proxy that dies on its own is restarted.
    private var wantsRunning = false
    /// Keeps the Mac from idle-sleeping while it hosts, so remote agents don't lose it.
    private var noSleep: NSObjectProtocol?
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
        wantsRunning = true
        if noSleep == nil {
            noSleep = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
                reason: "Hosting simulators for remote agents")
        }
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
        wantsRunning = false
        process.stop()
        status = .stopped
        if let noSleep { ProcessInfo.processInfo.endActivity(noSleep) }
        noSleep = nil
    }

    func rotateToken() {
        token = HostPaths.rotateToken()
        if process.isRunning { restart() }
    }

    /// Stops `agent-device proxy` processes on our port that this app doesn't own,
    /// e.g. one orphaned by a previous app run. They keep serving an old token.
    func stopForeignProxies() async {
        let result = await Shell.run("pgrep", ["-f", "agent-device proxy --host 127.0.0.1 --port \(port)"], timeout: 10)
        let own = process.pid
        let pids = result.stdout.split(whereSeparator: \.isNewline).compactMap { Int32($0) }.filter { $0 != own }
        guard !pids.isEmpty else { return }
        pids.forEach { kill($0, SIGTERM) }
        for _ in 0..<20 where await health() != nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
        status = .stopped
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
        } else if wantsRunning, !process.isRunning {
            // Our proxy died on its own (crash, killed): bring it back so agents reconnect.
            restartAttempts += 1
            process.appendNote("proxy is down — restarting (attempt \(restartAttempts))")
            status = .stopped
            if restartAttempts <= 5 || restartAttempts % 20 == 0 { start() }
            return
        } else if status.isUp {
            status = process.isRunning ? .failed("The proxy stopped answering.") : .stopped
        }
        if case .running = status { restartAttempts = 0 }
    }

    private var restartAttempts = 0

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
        case .prompt:
            return agentPrompt
        }
    }

    /// A prompt to paste into Claude Code / Cursor on the agent machine so the
    /// agent sets itself up, verifies the connection and runs a smoke test.
    var agentPrompt: String {
        let version = cliVersion ?? "latest"
        return """
        Set up this machine so you can drive the iOS simulators and Android emulators on my Mac (a "device host") with agent-device by Callstack (https://agent-device.dev).

        Host URL: \(remoteURL)
        Token: \(token)
        Session name: \(sessionName)

        Security rules:
        - The token is a secret: never print it back, commit it, or write it into project files.
        - Never ask me to paste secrets (this token, Tailscale auth keys) into a shared chat or channel. If your platform has a secure secret request, use it. If a secret was already posted somewhere others can read, tell me to rotate it on the Mac once we are connected.
        - Never enable Tailscale Funnel or any public URL for the host: that would expose my simulators to the internet behind only this token.

        Do these steps one at a time, show me each command before running it, and stop to tell me if one fails:
        1. Join my tailnet. The host URL only works inside it. If `tailscale status` already shows you connected, go to step 2. Otherwise:
           - Ask me for an auth key through your secure secret request. I create it at login.tailscale.com → Settings → Keys → Generate auth key: Ephemeral ON, tag:agent, short expiry. Reusable OFF if you run on one persistent machine; Reusable ON only if your sandbox restarts (a single-use key can't rejoin after a restart), and then keep it only in your secret store.
           - Without root (containers, sandboxes, shared boxes), use userspace networking and keep its files in your own folder: `tailscaled --tun=userspace-networking --state=mem: --socket=<your-dir>/tailscaled.sock --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055 &`, then `tailscale --socket=<your-dir>/tailscaled.sock up --auth-key=<key> --hostname=<agent-name>`.
           - In userspace mode, traffic to the tailnet only goes through that proxy: set ALL_PROXY=socks5://localhost:1055/ and HTTP_PROXY/HTTPS_PROXY/http_proxy/https_proxy=http://localhost:1055/ for every command below. Node.js only honours proxy variables with NODE_USE_ENV_PROXY=1 on recent versions; verify with `agent-device devices` in step 6 and tell me if it can't reach the host.
           - The node is ephemeral: it disappears from my tailnet shortly after you disconnect.
        2. Check Node.js is 22.12 or newer (`node --version`).
        3. Install the same agent-device version as the host: `npm install -g agent-device@\(version)`.
        4. Check the host answers: `curl -s \(remoteURL)/health` must contain "ok":true.
        5. Save AGENT_DEVICE_DAEMON_AUTH_TOKEN (the token) and AGENT_DEVICE_SESSION=\(sessionName) as persistent environment variables for my user (shell profile on macOS/Linux, user environment variables on Windows), so new terminals and MCP clients see them.
        6. Connect: `agent-device connect proxy --daemon-base-url \(remoteURL)`, then `agent-device devices` and list the devices you see.
        7. Make agent-device available to you: install the skill with `npx skills add callstack/agent-device`, then register the MCP server — Claude Code: `claude mcp add --transport stdio --scope user agent-device -- agent-device mcp`; Cursor: add {"mcpServers":{"agent-device":{"command":"agent-device","args":["mcp"]}}} to ~/.cursor/mcp.json.
        8. Smoke test on iOS: `agent-device open com.apple.Preferences --platform ios`, `agent-device snapshot -i`, `agent-device screenshot ./agent-device-check.png`, then `agent-device close`. Show me the screenshot.

        If you lose access later, check in this order before asking me anything:
        a. `tailscale status` (with --socket=… in userspace mode). If tailscaled is gone (sandbox restart), start it and run `tailscale up` again with the key from your secret store.
        b. `curl -s \(remoteURL)/health`. If it doesn't answer while you are on the tailnet, my Mac is asleep, offline or the app is closed: tell me.
        c. If health is ok but you get "Invalid proxy token", the token was rotated: ask me for the new one through your secure secret request.
        d. Run `agent-device connect proxy --daemon-base-url \(remoteURL)` again.

        From now on, when testing apps: open → snapshot -i → act (press/fill) → re-snapshot → verify → close. Always `close` when done so the device is released for other agents.
        """
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
