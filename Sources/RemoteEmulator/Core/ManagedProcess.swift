import Foundation

/// A long-running child process (proxy, Metro) owned by the app.
/// Keeps the last lines of output for the Logs view and dies with the app.
@MainActor
final class ManagedProcess: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lines: [String] = []

    let name: String
    private var process: Process?
    private let maxLines = 1_000
    private let redact: [String]
    /// Output is also appended here (already redacted), so crashes can be diagnosed after the fact.
    private let logFile: URL?

    init(name: String, redact: [String] = [], logFile: URL? = nil) {
        self.name = name
        self.redact = redact
        self.logFile = logFile
    }

    func start(_ tool: String, _ args: [String], cwd: URL? = nil, environment extra: [String: String] = [:],
               redacting secrets: [String] = []) throws {
        stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + args
        process.environment = Shell.environment.merging(extra) { _, new in new }
        if let cwd { process.currentDirectoryURL = cwd }
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let hidden = redact + secrets
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            var text = String(decoding: data, as: UTF8.self)
            for secret in hidden where !secret.isEmpty {
                text = text.replacingOccurrences(of: secret, with: "••••••••")
            }
            Task { @MainActor in self?.append(text) }
        }
        process.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self, self.process === proc else { return }
                self.isRunning = false
                self.append("— \(self.name) exited (code \(proc.terminationStatus)) —\n")
            }
        }

        append("— starting \(name) —\n")
        try process.run()
        self.process = process
        isRunning = true
    }

    var pid: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }

    func stop() {
        guard let process, process.isRunning else { return }
        process.interrupt()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
        self.process = nil
        isRunning = false
    }

    func clear() { lines.removeAll() }

    /// A line from the app itself (not the child), shown in the logs.
    func appendNote(_ note: String) { append("— \(note) —\n") }

    private func append(_ text: String) {
        let stripped = text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        let new = stripped.split(whereSeparator: \.isNewline).map(String.init)
        lines.append(contentsOf: new)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        writeToLogFile(new)
    }

    private func writeToLogFile(_ new: [String]) {
        guard let logFile, !new.isEmpty else { return }
        let fm = FileManager.default
        // Keep the file small: start over past 1 MB.
        if let size = try? fm.attributesOfItem(atPath: logFile.path)[.size] as? Int, size > 1_000_000 {
            try? fm.removeItem(at: logFile)
        }
        if !fm.fileExists(atPath: logFile.path) {
            fm.createFile(atPath: logFile.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: logFile) else { return }
        defer { try? handle.close() }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = new.map { "\(stamp) \($0)\n" }.joined()
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }
}
