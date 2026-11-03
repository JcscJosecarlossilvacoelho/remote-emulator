import AppKit
import ServiceManagement
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview, devices, app, connect, logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .devices: "Devices"
        case .app: "App & Metro"
        case .connect: "Connect agents"
        case .logs: "Logs"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .devices: "iphone.gen3"
        case .app: "shippingbox.fill"
        case .connect: "point.3.connected.trianglepath.dotted"
        case .logs: "text.alignleft"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let host = HostService()
    let metro = MetroService()
    let devices = DeviceService()
    let setup = SetupService()

    @AppStorage("startHostOnLaunch") var startHostOnLaunch = true
    @AppStorage("onboardingCompleted") var onboardingCompleted = false
    @Published var page: Page = .overview
    @Published var showOnboarding = false
    @Published private(set) var takingOver = false

    private var pollTask: Task<Void, Never>?
    /// Screenshot runs must never touch the real host.
    let isScreenshotRun = CommandLine.arguments.contains("--screenshot")

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
        if !onboardingCompleted && !isScreenshotRun { showOnboarding = true }
        pollTask = Task { [weak self] in
            guard let self else { return }
            await setup.runChecks()
            await host.poll()
            await metro.poll()
            if onboardingCompleted, startHostOnLaunch, !isScreenshotRun, !host.status.isUp { host.start() }
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

    /// Stops hosts started outside the app (LaunchAgents), then runs them from here.
    func takeOver() async {
        takingOver = true
        defer { takingOver = false }
        let metroWasExternal = metro.status == .external
        await setup.takeOver()
        for _ in 0..<20 {
            await host.poll()
            await metro.poll()
            if !host.status.isUp && metro.status != .external { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        host.start()
        if metroWasExternal, metro.app != nil { metro.start() }
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
