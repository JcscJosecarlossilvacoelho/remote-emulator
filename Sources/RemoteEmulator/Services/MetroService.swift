import AppKit
import Foundation

/// Runs Metro (`npx expo start`) for the active Expo app so simulators,
/// emulators and development builds load JavaScript from this Mac.
@MainActor
final class MetroService: ObservableObject {
    enum Status: Equatable {
        case stopped, starting, running
        /// Metro started outside the app is answering on the port.
        case external
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var app: ExpoApp?
    @Published private(set) var recents: [URL] = []

    let process = ManagedProcess(name: "Metro")
    let port = 8081

    init() {
        recents = (UserDefaults.standard.stringArray(forKey: "recentApps") ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("package.json").path) }
        if let dir = HostPaths.readAppDirectory() { app = ExpoApp.load(from: dir) }
    }

    func start() {
        guard let app, !process.isRunning else { return }
        status = .starting
        Task {
            await reverseAndroidPort()
            do {
                try process.start("npx", ["expo", "start", "--port", String(port)], cwd: app.directory)
            } catch {
                status = .stopped
            }
        }
    }

    func stop() {
        process.stop()
        status = .stopped
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use this app"
        panel.message = "Choose the folder of an Expo / React Native app (the one with package.json)."
        if panel.runModal() == .OK, let url = panel.url { select(url) }
    }

    func select(_ directory: URL) {
        guard let loaded = ExpoApp.load(from: directory) else {
            let alert = NSAlert()
            alert.messageText = "This folder has no package.json"
            alert.informativeText = directory.path
            alert.runModal()
            return
        }
        let wasRunning = process.isRunning
        stop()
        app = loaded
        HostPaths.writeAppDirectory(directory)
        recents.removeAll { $0 == directory }
        recents.insert(directory, at: 0)
        recents = Array(recents.prefix(8))
        UserDefaults.standard.set(recents.map(\.path), forKey: "recentApps")
        if wasRunning { start() }
    }

    func poll() async {
        let up = await isPackagerRunning()
        if process.isRunning {
            status = up ? .running : .starting
        } else {
            status = up ? .external : .stopped
        }
    }

    private func isPackagerRunning() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/status") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return false }
        return String(decoding: data, as: UTF8.self).contains("packager-status:running")
    }

    /// Lets Android emulators reach Metro on their own localhost:8081.
    func reverseAndroidPort() async {
        let adb = await Shell.run("adb", ["devices"])
        for line in adb.stdout.split(whereSeparator: \.isNewline) {
            let cols = line.split(whereSeparator: \.isWhitespace)
            guard cols.count >= 2, cols[1] == "device" else { continue }
            await Shell.run("adb", ["-s", String(cols[0]), "reverse", "tcp:\(port)", "tcp:\(port)"], timeout: 5)
        }
    }
}
