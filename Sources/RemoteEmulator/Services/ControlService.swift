import Foundation
import SwiftUI

/// Lets a trusted remote agent drive this Mac beyond the simulators: Metro, the app's
/// git branch, and Claude Code / Codex runs confined to one projects folder.
///
/// Off by default. Listens on 127.0.0.1 only and is published inside the tailnet with
/// `tailscale serve --set-path=/control` (never Funnel). Uses its own token.
@MainActor
final class ControlService: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case claude, codex
        var id: String { rawValue }
        var title: String { self == .claude ? "Claude Code" : "Codex" }
    }

    @MainActor
    final class Job: ObservableObject, Identifiable {
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let tool: Tool
        let prompt: String
        let directory: URL
        let started = Date()
        let process: ManagedProcess

        init(tool: Tool, prompt: String, directory: URL) {
            self.tool = tool
            self.prompt = prompt
            self.directory = directory
            process = ManagedProcess(name: "\(tool.title) job")
        }

        var state: String {
            if process.isRunning { return "running" }
            return process.exitCode == 0 ? "done" : "failed"
        }

        func summary(lines: Int = 0) -> [String: Any] {
            var info: [String: Any] = [
                "id": id, "tool": tool.rawValue, "state": state, "dir": directory.path,
                "started": ISO8601DateFormatter().string(from: started),
                "prompt": String(prompt.prefix(200)),
            ]
            if let code = process.exitCode { info["exitCode"] = Int(code) }
            if lines > 0 { info["output"] = process.lines.suffix(lines).joined(separator: "\n") }
            return info
        }
    }

    @AppStorage("controlEnabled") private(set) var enabled = false
    @AppStorage("controlAllowAgents") var allowAgents = false { willSet { objectWillChange.send() } }
    @AppStorage("controlWorkRoot") private var workRootPath = ""

    @Published private(set) var token = HostPaths.readOrCreateToken(at: HostPaths.controlToken)
    @Published private(set) var jobs: [Job] = []
    @Published private(set) var lastError: String?

    let port: UInt16 = 4320
    let maxConcurrentJobs = 2
    let jobTimeout: TimeInterval = 45 * 60

    private let server = HTTPServer()
    private weak var metro: MetroService?
    private weak var host: HostService?

    var workRoot: URL? {
        workRootPath.isEmpty ? nil : URL(fileURLWithPath: workRootPath).resolvingSymlinksInPath()
    }

    var remoteURL: String {
        if let remoteHost = host?.remoteHost { return "https://\(remoteHost)/control" }
        return "http://127.0.0.1:\(port)"
    }

    func attach(metro: MetroService, host: HostService) {
        self.metro = metro
        self.host = host
        if enabled { Task { await start() } }
    }

    // MARK: - Lifecycle

    func setEnabled(_ on: Bool) {
        enabled = on
        objectWillChange.send()
        Task { on ? await start() : await stop() }
    }

    func start() async {
        do {
            try server.start(port: port) { [weak self] request in
                guard let self else { return .error(503, "Shutting down") }
                return await self.handle(request)
            }
            lastError = nil
            installHelper()
            if agentDeviceTools.isEmpty { agentDeviceTools = await Self.listAgentDeviceTools() }
        } catch {
            lastError = "Could not listen on 127.0.0.1:\(port): \(error.localizedDescription)"
            return
        }
        // Inside the tailnet only — `serve`, never `funnel`.
        if Shell.which("tailscale") != nil {
            await Shell.run("tailscale", ["serve", "--bg", "--set-path=/control", "localhost:\(port)"], timeout: 20)
        }
    }

    func stop() async {
        server.stop()
        jobs.filter { $0.process.isRunning }.forEach { $0.process.stop() }
        if Shell.which("tailscale") != nil {
            await Shell.run("tailscale", ["serve", "--set-path=/control", "off"], timeout: 20)
        }
    }

    /// agent-device MCP tool names, pre-approved for Codex runs (exec can't ask anyone).
    private var agentDeviceTools: [String] = []

    nonisolated static func listAgentDeviceTools() async -> [String] {
        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"remote-emulator","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
        ].joined(separator: "\n")
        let result = await Shell.run("sh", ["-c", "(printf '%s\\n' \"$1\"; sleep 4) | agent-device mcp 2>/dev/null", "sh", requests],
                                     timeout: 20)
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  message["id"] as? Int == 2,
                  let tools = (message["result"] as? [String: Any])?["tools"] as? [[String: Any]]
            else { continue }
            return tools.compactMap { $0["name"] as? String }
                .filter { $0.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil }
        }
        return []
    }

    nonisolated static let binDirectory = HostPaths.directory.appendingPathComponent("bin")

    /// `re-metro status|start [dir]|stop|update [branch]` — run by coding-agent jobs
    /// outside their sandbox. It reads the token itself, so the job never sees it.
    private func installHelper() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.binDirectory, withIntermediateDirectories: true)
        let script = """
        #!/bin/zsh
        # Installed by Remote Emulator. Drives the Metro bundler the app keeps running.
        set -eu
        api="http://127.0.0.1:\(port)"
        tok="$(cat "$HOME/.agent-device-host/control-token")"
        call() { curl -sS -m 900 -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' "$@"; echo; }
        json() { /usr/bin/python3 -c 'import json,sys; print(json.dumps({sys.argv[1]: sys.argv[2]}))' "$1" "$2"; }
        case "${1:-status}" in
          status) call "$api/metro" ;;
          start)  if [ -n "${2:-}" ]; then call -X POST -d "$(json dir "$2")" "$api/metro/start"; else call -X POST "$api/metro/start"; fi ;;
          stop)   call -X POST "$api/metro/stop" ;;
          update) call -X POST -d "$(json branch "${2:-main}")" "$api/app/update" ;;
          *) echo "usage: re-metro status | start [project-dir] | stop | update [branch]" >&2; exit 2 ;;
        esac
        """
        let file = Self.binDirectory.appendingPathComponent("re-metro")
        fm.createFile(atPath: file.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755])
    }

    func rotateToken() {
        token = HostPaths.rotateToken(at: HostPaths.controlToken)
    }

    func chooseWorkRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use this folder"
        panel.message = "Remote Claude Code / Codex runs can only write inside this folder (e.g. your projects folder)."
        if panel.runModal() == .OK, let url = panel.url {
            workRootPath = url.path
            objectWillChange.send()
        }
    }

    /// Paste-able instructions for the remote agent (contains the control token).
    var agentPrompt: String {
        let url = remoteURL
        let folder = workRoot?.path ?? "(not chosen yet)"
        return """
        You can also control my Mac's dev tools through the Remote Emulator control API.

        Control URL: \(url)
        Control token: \(token)
        Projects folder on the Mac: \(folder)

        Rules:
        - The control token is a secret, separate from the agent-device token. Never print it, commit it or paste it in a shared chat. Store it as REMOTE_EMULATOR_CONTROL_TOKEN in your secret store.
        - It works only inside my tailnet (same setup as agent-device). Never use Tailscale Funnel.
        - Send it as `Authorization: Bearer $REMOTE_EMULATOR_CONTROL_TOKEN` with `Content-Type: application/json`.

        Endpoints:
        - GET  \(url)/health — no token; tells you if Claude Code / Codex runs are enabled.
        - GET  \(url)/metro — Metro status and the selected app.
        - POST \(url)/metro/start  ·  POST \(url)/metro/stop
        - POST \(url)/app/update  {"branch":"main"} — fast-forwards the app's repo to that branch and reinstalls dependencies if a lockfile changed. Refuses if the Mac has uncommitted changes.
        - POST \(url)/jobs  {"tool":"claude"|"codex","dir":"<folder relative to the projects folder>","prompt":"…"} — runs Claude Code or Codex headless on the Mac. It can only write inside that folder (new folders are created, so you can start new projects). Returns a job id.
        - GET  \(url)/jobs/<id> — state (running/done/failed) and the last 400 lines of output. Poll every 15–30 s.
        - POST \(url)/jobs/<id>/stop  ·  GET \(url)/jobs — recent jobs.

        - GET  \(url)/file?path=<path relative to the projects folder> — downloads a file, e.g. a screenshot a job saved.

        Claude Code jobs on the Mac drive the simulators themselves (agent-device) and Metro (`re-metro start <project-dir>`), so you can delegate a whole task, e.g. {"tool":"claude","dir":"ddc-2027-app","prompt":"Switch to branch main, start Metro for apps/mobile, open the app on the iPhone simulator, check the login screen and save a screenshot to shots/login.png"}. When the job is done, download the screenshot with /file and send it to me in the chat.
        Jobs are sandboxed to that folder and run without MCP servers; Claude Code jobs only reach npm and GitHub. Ask me if a task needs more.
        """
    }

    // MARK: - Routing

    private func handle(_ request: HTTPServer.Request) async -> HTTPServer.Response {
        // Tailscale may or may not strip the mount point: accept both.
        var path = request.path
        if path.hasPrefix("/control") { path = String(path.dropFirst("/control".count)) }
        if path.isEmpty { path = "/" }
        let segments = path.split(separator: "/").map(String.init)

        if request.method == "GET", path == "/health" {
            return .json(200, ["ok": true, "service": "remote-emulator-control", "agents": allowAgents && workRoot != nil])
        }
        guard authorized(request) else { return .error(401, "Invalid control token") }

        switch (request.method, segments) {
        case ("GET", ["metro"]): return metroStatus()
        case ("POST", ["metro", "start"]): return startMetro(dir: request.json["dir"] as? String)
        case ("POST", ["metro", "stop"]):
            metro?.stop()
            return .json(200, ["ok": true, "status": "stopped"])
        case ("POST", ["app", "update"]): return await updateApp(branch: request.json["branch"] as? String)
        case ("GET", ["file"]): return readFile(request.query["path"] ?? "")
        case ("GET", ["jobs"]):
            return .json(200, ["ok": true, "jobs": jobs.map { $0.summary() }])
        case ("POST", ["jobs"]): return runJob(request.json)
        case ("GET", let s) where s.count == 2 && s[0] == "jobs":
            guard let job = jobs.first(where: { $0.id == s[1] }) else { return .error(404, "No such job") }
            return .json(200, ["ok": true, "job": job.summary(lines: 400)])
        case ("POST", let s) where s.count == 3 && s[0] == "jobs" && s[2] == "stop":
            guard let job = jobs.first(where: { $0.id == s[1] }) else { return .error(404, "No such job") }
            job.process.stop()
            return .json(200, ["ok": true, "job": job.summary()])
        default:
            return .error(404, "Unknown endpoint. See GET /health, /metro, /jobs")
        }
    }

    private func authorized(_ request: HTTPServer.Request) -> Bool {
        var given = request.header("x-control-token") ?? ""
        if given.isEmpty, let auth = request.header("authorization"), auth.lowercased().hasPrefix("bearer ") {
            given = String(auth.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        // Constant-time comparison.
        let a = Array(given.utf8), b = Array(token.utf8)
        guard a.count == b.count, !b.isEmpty else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// Lets the remote agent fetch results such as screenshots (max 20 MB, projects folder only).
    private func readFile(_ path: String) -> HTTPServer.Response {
        guard let root = workRoot, !path.isEmpty, let url = Self.resolve(path, inside: root) else {
            return .error(403, "path must be inside the projects folder")
        }
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
              size <= 20_000_000, let data = try? Data(contentsOf: url)
        else { return .error(404, "No such file (or larger than 20 MB)") }
        let types = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
                     "mp4": "video/mp4", "txt": "text/plain", "json": "application/json", "log": "text/plain"]
        return HTTPServer.Response(status: 200, body: data,
                                   contentType: types[url.pathExtension.lowercased()] ?? "application/octet-stream")
    }

    // MARK: - Metro & app

    private func metroStatus() -> HTTPServer.Response {
        guard let metro else { return .error(503, "Metro unavailable") }
        return .json(200, [
            "ok": true,
            "status": "\(metro.status)",
            "app": (metro.app?.directory.path).map { $0 as Any } ?? NSNull(),
            "port": metro.port,
        ])
    }

    /// `dir` (optional) switches Metro to another app inside the projects folder.
    private func startMetro(dir: String?) -> HTTPServer.Response {
        guard let metro else { return .error(503, "Metro unavailable") }
        if metro.status == .external { return .error(409, "Metro is running outside the app") }
        if let dir, !dir.isEmpty {
            guard let root = workRoot, let url = Self.resolve(dir, inside: root) else {
                return .error(403, "dir must be inside the projects folder")
            }
            guard ExpoApp.load(from: url) != nil else { return .error(404, "No package.json in \(dir)") }
            if metro.app?.directory.standardizedFileURL != url.standardizedFileURL { metro.select(url) }
        }
        guard metro.app != nil else { return .error(409, "No app selected; pass \"dir\"") }
        metro.start()
        return .json(200, ["ok": true, "status": "starting", "app": metro.app?.directory.path ?? ""])
    }

    /// Switches the selected app's repo to a branch (fast-forward only) and reinstalls
    /// dependencies when a lockfile changed. Refuses to touch uncommitted work.
    private func updateApp(branch: String?) async -> HTTPServer.Response {
        guard let metro, let app = metro.app else { return .error(409, "No app selected in Remote Emulator") }
        let branch = branch ?? "main"
        guard branch.range(of: #"^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$"#, options: .regularExpression) != nil,
              !branch.contains("..")
        else { return .error(400, "Invalid branch name") }

        let dir = app.directory
        func git(_ args: [String]) async -> Shell.Result { await Shell.run("git", args, cwd: dir, timeout: 120) }

        let root = await git(["rev-parse", "--show-toplevel"])
        guard root.ok else { return .error(409, "The app folder is not a git repository") }
        let repo = URL(fileURLWithPath: root.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        let dirty = await git(["status", "--porcelain"])
        guard dirty.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error(409, "The repo has uncommitted changes on this Mac; refusing to switch branches")
        }
        let before = await git(["rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        for step in [["fetch", "origin", branch], ["checkout", branch], ["pull", "--ff-only", "origin", branch]] {
            let result = await git(step)
            guard result.ok else {
                return .error(409, "git \(step.joined(separator: " ")) failed: \(result.stderr.suffix(400))")
            }
        }
        let after = await git(["rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = await git(["diff", "--name-only", before, after]).stdout
        let lockfiles = ["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lock", "bun.lockb"]
        var installed: String?
        if changed.split(whereSeparator: \.isNewline).contains(where: { lockfiles.contains(($0 as NSString).lastPathComponent) }) {
            let fm = FileManager.default
            let manager = fm.fileExists(atPath: repo.appendingPathComponent("pnpm-lock.yaml").path) ? "pnpm"
                : fm.fileExists(atPath: repo.appendingPathComponent("yarn.lock").path) ? "yarn"
                : fm.fileExists(atPath: repo.appendingPathComponent("bun.lock").path) ? "bun" : "npm"
            let result = await Shell.run(manager, ["install"], cwd: repo, timeout: 900)
            guard result.ok else { return .error(500, "\(manager) install failed: \(result.stderr.suffix(600))") }
            installed = manager
        }
        let wasRunning = metro.status == .running || metro.status == .starting
        if wasRunning, installed != nil {
            metro.stop()
            try? await Task.sleep(for: .seconds(1))
            metro.start()
        }
        return .json(200, [
            "ok": true, "branch": branch, "from": String(before.prefix(10)), "to": String(after.prefix(10)),
            "installed": installed.map { $0 as Any } ?? NSNull(), "metro": wasRunning ? "reloads on next bundle" : "off",
        ])
    }

    // MARK: - Coding agents

    private func runJob(_ body: [String: Any]) -> HTTPServer.Response {
        guard allowAgents else { return .error(403, "Claude Code / Codex runs are turned off on this Mac") }
        guard let root = workRoot else { return .error(409, "No projects folder chosen on this Mac") }
        guard let tool = Tool(rawValue: (body["tool"] as? String ?? "claude").lowercased()) else {
            return .error(400, "tool must be \"claude\" or \"codex\"")
        }
        guard Shell.which(tool.rawValue) != nil else { return .error(409, "\(tool.title) is not installed on this Mac") }
        guard let prompt = body["prompt"] as? String, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              prompt.count <= 50_000
        else { return .error(400, "prompt is required (max 50k characters)") }
        guard jobs.filter({ $0.process.isRunning }).count < maxConcurrentJobs else {
            return .error(429, "Already running \(maxConcurrentJobs) jobs; wait or stop one")
        }
        guard let dir = Self.resolve(body["dir"] as? String ?? "", inside: root) else {
            return .error(403, "dir must be inside the projects folder")
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return .error(500, "Could not create \(dir.lastPathComponent): \(error.localizedDescription)")
        }

        let job = Job(tool: tool, prompt: prompt, directory: dir)
        let args = tool == .claude ? claudeArguments(prompt: prompt, dir: dir) : codexArguments(prompt: prompt, dir: dir)
        do {
            try job.process.start(tool.rawValue, args, cwd: dir, redacting: [token, host?.token ?? ""],
                                  baseEnvironment: Self.cleanEnvironment())
        } catch {
            return .error(500, "Could not start \(tool.title): \(error.localizedDescription)")
        }
        jobs.insert(job, at: 0)
        if jobs.count > 20 { jobs.removeLast(jobs.count - 20) }
        let timeout = jobTimeout
        Task { [weak job] in
            try? await Task.sleep(for: .seconds(timeout))
            if let job, job.process.isRunning {
                job.process.appendNote("stopped after \(Int(timeout / 60)) min")
                job.process.stop()
            }
        }
        return .json(202, ["ok": true, "job": job.summary()])
    }

    /// `dir` is relative to the root (or absolute); the result must stay inside it.
    /// Missing folders are allowed so agents can start new projects.
    nonisolated static func resolve(_ dir: String, inside root: URL) -> URL? {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let candidate = dir.hasPrefix("/") ? URL(fileURLWithPath: dir) : URL(fileURLWithPath: rootPath).appendingPathComponent(dir)
        // Resolve symlinks on the deepest existing ancestor so links can't point outside.
        var existing = candidate.standardizedFileURL
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        rest.forEach { resolved.appendPathComponent($0) }
        let path = resolved.standardizedFileURL.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Only what the CLIs need: no tokens or keys from the app's environment.
    nonisolated static func cleanEnvironment() -> [String: String] {
        let env = Shell.environment
        var clean: [String: String] = ["TERM": "dumb", "CI": "1"]
        for key in ["PATH", "HOME", "USER", "LOGNAME", "SHELL", "LANG", "TMPDIR", "ANDROID_HOME"] {
            if let value = env[key] { clean[key] = value }
        }
        clean["PATH"] = binDirectory.path + ":" + (clean["PATH"] ?? "/usr/bin:/bin")
        return clean
    }

    /// Headless Claude Code with the OS sandbox on: shell commands can't write outside
    /// `dir` or read the rest of the home folder, file tools are confined to `dir`, hooks
    /// and MCP servers (e.g. cloud accounts) are off, and WebFetch is denied.
    private func claudeArguments(prompt: String, dir: URL) -> [String] {
        let home = NSHomeDirectory()
        // Toolchains installed under the home folder (nvm, npm-global, …) must stay readable.
        var readable = Set([dir.path, "\(home)/.npm"])
        for tool in ["node", "npm", "npx", "git", "yarn", "pnpm", "bun", "expo", "agent-device"] {
            guard let path = Shell.which(tool) else { continue }
            let real = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            let prefix = real.deletingLastPathComponent().deletingLastPathComponent().path
            if prefix.hasPrefix(home + "/") { readable.insert(prefix) }
        }
        let settings: [String: Any] = [
            "disableAllHooks": true,
            "permissions": [
                "defaultMode": "dontAsk",
                "allow": ["Read", "Edit", "Write", "Glob", "Grep", "Bash", "TodoWrite"],
                "deny": ["WebFetch"],
                "blockReadsOutsideWorkingDirectories": true,
                "blockWritesOutsideWorkingDirectories": true,
            ],
            "sandbox": [
                "enabled": true,
                "autoAllowBashIfSandboxed": true,
                "failIfUnavailable": true,
                "allowUnsandboxedCommands": false,
                // Simulators and Metro live outside the sandbox; only these two tools reach them.
                "excludedCommands": ["agent-device *", "re-metro *"],
                "filesystem": [
                    "denyRead": ["~/"],
                    "allowRead": Array(readable).sorted(),
                    "allowWrite": ["\(home)/.npm"],
                ],
                "network": [
                    "allowedDomains": ["registry.npmjs.org", "*.npmjs.org", "registry.yarnpkg.com",
                                       "github.com", "*.github.com", "*.githubusercontent.com"],
                ],
            ],
        ]
        let json = String(decoding: (try? JSONSerialization.data(withJSONObject: settings)) ?? Data(), as: UTF8.self)
        return [
            "-p", prompt,
            "--permission-mode", "dontAsk",
            "--settings", json,
            "--strict-mcp-config",
            "--no-session-persistence",
            "--output-format", "text",
            "--append-system-prompt", Self.jobHint,
        ]
    }

    nonisolated static let jobHint = """
    You run on a Mac with iOS simulators and Android emulators, on behalf of a remote agent.
    - Devices: use the `agent-device` CLI (agent-device devices, open <app> --platform ios|android, snapshot -i, press, fill, screenshot <file>, close). Save screenshots inside the current folder and print their relative paths at the end so the remote agent can download them.
    - Metro: never run `expo start` yourself. Use `re-metro start <project-dir>`, `re-metro status`, `re-metro stop`, `re-metro update <branch>`; Metro keeps running after you finish.
    - Always `agent-device close` when done.
    - Run every `agent-device` and `re-metro` command on its own line as a single command: no `&&`, `;`, pipes or `cd` in front (create folders in a separate command first). Combined commands stay sandboxed and can't reach the devices.
    """

    /// Headless Codex in its workspace-write sandbox: writes only inside `dir`.
    /// Your config.toml (MCP servers, approval overrides) is ignored for these runs.
    private func codexArguments(prompt: String, dir: URL) -> [String] {
        ["exec", "--sandbox", "workspace-write", "--cd", dir.path, "--skip-git-repo-check",
         "--ignore-user-config", "--ephemeral",
         "-c", "mcp_servers.agent-device.command=\"agent-device\"",
         "-c", "mcp_servers.agent-device.args=[\"mcp\"]",
        ] + agentDeviceTools.flatMap { ["-c", "mcp_servers.agent-device.tools.\($0).approval_mode=\"approve\""] } + [
         Self.jobHint + "\nIn this run, use the agent-device MCP tools for devices; Metro control is not available to Codex, say so if needed.\n\nTask:\n" + prompt]
    }
}
