import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let host = HostService()
    let metro = MetroService()
    let devices = DeviceService()
    let setup = SetupService()

    @AppStorage("startHostOnLaunch") var startHostOnLaunch = true
    @AppStorage("onboardingCompleted") var onboardingCompleted = false
    @Published var showLogs = false
    @Published var showSupport = false

    // Gentle support prompt: only after real use, at most every two weeks.
    @AppStorage("launchCount") private var launchCount = 0
    @AppStorage("firstLaunch") private var firstLaunch: Double = 0
    @AppStorage("lastSupportPrompt") private var lastSupportPrompt: Double = 0
    @AppStorage("supportPromptDisabled") private var supportPromptDisabled = false
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
        scheduleSupportPrompt()
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

    private func scheduleSupportPrompt() {
        guard !isScreenshotRun else { return }
        let now = Date().timeIntervalSince1970
        if firstLaunch == 0 { firstLaunch = now }
        launchCount += 1
        let day: Double = 86_400
        let forced = CommandLine.arguments.contains("--show-support")
        guard forced || (onboardingCompleted && !supportPromptDisabled && launchCount >= 5
                         && now - firstLaunch >= 3 * day && now - lastSupportPrompt >= 14 * day)
        else { return }
        Task {
            try? await Task.sleep(for: .seconds(forced ? 2 : 20))
            guard !showOnboarding else { return }
            lastSupportPrompt = Date().timeIntervalSince1970
            showSupport = true
        }
    }

    /// `never` = the user already supported (or doesn't want to be asked again).
    func closeSupportPrompt(never: Bool) {
        if never { supportPromptDisabled = true }
        showSupport = false
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
