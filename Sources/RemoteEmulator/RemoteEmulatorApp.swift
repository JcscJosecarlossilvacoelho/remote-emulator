import AppKit
import SwiftUI

@main
struct RemoteEmulatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Remote Emulator", id: "dashboard") {
            DashboardView()
                .environmentObject(model)
                .environmentObject(model.host)
                .environmentObject(model.metro)
                .environmentObject(model.devices)
                .frame(minWidth: 1000, minHeight: 700)
                .onAppear { model.boot() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 780)

        MenuBarExtra {
            MenuBarView(openDashboard: { openWindow(id: "dashboard"); model.openDashboard() })
                .environmentObject(model)
                .environmentObject(model.host)
                .environmentObject(model.metro)
                .environmentObject(model.devices)
        } label: {
            MenuBarIcon(host: model.host)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.host)
        }
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var host: HostService
    var body: some View {
        Image(systemName: host.status.isUp ? "iphone.radiowaves.left.and.right" : "iphone.slash")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in AppModel.shared.boot() }
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--screenshot"), index + 1 < args.count {
            Task { @MainActor in await Screenshot.capture(to: URL(fileURLWithPath: args[index + 1])) }
        }
    }

    /// Keep serving devices from the menu bar after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.shutdown() }
    }
}

/// `RemoteEmulator --screenshot out.png` renders the dashboard (with machine
/// details hidden) for the README, then quits.
enum Screenshot {
    @MainActor
    static func capture(to url: URL) async {
        AppModel.shared.host.demoMode = true
        try? await Task.sleep(for: .seconds(10))
        // Render offscreen with SwiftUI: needs no Screen Recording permission.
        let model = AppModel.shared
        let content = DashboardContent()
            .background(DashboardView.background)
            .environment(\.colorScheme, .light)
            .environment(\.snapshotMode, true)
            .environmentObject(model)
            .environmentObject(model.host)
            .environmentObject(model.metro)
            .environmentObject(model.devices)
            .frame(width: 1120)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { exit(1) }
        try? png.write(to: url)
        exit(0)
    }
}
