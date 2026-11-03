import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let host = HostService()
    let metro = MetroService()
    let devices = DeviceService()

    @AppStorage("startHostOnLaunch") var startHostOnLaunch = true
    @Published var showLogs = false

    private var pollTask: Task<Void, Never>?
    /// Screenshot runs must never touch the real host.
    private let isScreenshotRun = CommandLine.arguments.contains("--screenshot")

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch at login: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }

    func boot() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            await host.poll()
            await metro.poll()
            if startHostOnLaunch, !isScreenshotRun, !host.status.isUp { host.start() }
            var tick = 0
            while !Task.isCancelled {
                if tick % 2 == 0 { await devices.refresh() }
                await host.poll()
                await metro.poll()
                tick += 1
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func shutdown() {
        pollTask?.cancel()
        host.process.stop()
        metro.process.stop()
    }

    func openDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("dashboard") == true }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
