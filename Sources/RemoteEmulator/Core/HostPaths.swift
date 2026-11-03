import Foundation
import Security

/// Files shared with the shell scripts and the agent-device CLI.
/// Everything lives in ~/.agent-device-host so the app and terminal setups agree.
enum HostPaths {
    static let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".agent-device-host")
    static let token = directory.appendingPathComponent("token")
    static let appDir = directory.appendingPathComponent("app-dir")

    static func ensureDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    /// Reads the proxy token, creating a strong random one (0600) on first use.
    static func readOrCreateToken() -> String {
        ensureDirectory()
        if let existing = try? String(contentsOf: token, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            return existing
        }
        return rotateToken()
    }

    @discardableResult
    static func rotateToken() -> String {
        ensureDirectory()
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        FileManager.default.createFile(atPath: token.path, contents: Data(value.utf8), attributes: [.posixPermissions: 0o600])
        return value
    }

    static func readAppDirectory() -> URL? {
        guard let raw = try? String(contentsOf: appDir, encoding: .utf8) else { return nil }
        let path = raw.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return path.isEmpty ? nil : URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    static func writeAppDirectory(_ url: URL) {
        ensureDirectory()
        try? (url.path + "\n").write(to: appDir, atomically: true, encoding: .utf8)
    }
}
