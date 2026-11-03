import AppKit
import SwiftUI

@main
struct RemoteEmulatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Remote Emulator", id: "dashboard") {
            MainView()
                .withServices(model)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { model.boot() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)

        MenuBarExtra {
            MenuBarView(openDashboard: { openWindow(id: "dashboard"); model.openDashboard() })
                .withServices(model)
        } label: {
            MenuBarIcon(host: model.host)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().withServices(model)
        }
    }
}

extension View {
    func withServices(_ model: AppModel) -> some View {
        environmentObject(model)
            .environmentObject(model.host)
            .environmentObject(model.metro)
            .environmentObject(model.devices)
            .environmentObject(model.setup)
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
            let page = args.firstIndex(of: "--page").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "main"
            Task { @MainActor in await Screenshot.capture(page: page, to: URL(fileURLWithPath: args[index + 1])) }
        }
    }

    /// Keep serving devices from the menu bar after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.shutdown() }
    }
}

/// `RemoteEmulator --screenshot out.png [--page main|onboarding]`
/// renders a page offscreen (machine details hidden) for the README, then quits.
enum Screenshot {
    @MainActor
    static func capture(page: String, to url: URL) async {
        let model = AppModel.shared
        model.host.demoMode = true
        model.setup.demoMode = true
        try? await Task.sleep(for: .seconds(10))

        let content: AnyView = page == "onboarding"
            ? AnyView(OnboardingView(step: .requirements).frame(width: 780, height: 600))
            : AnyView(MainView().frame(width: 1080, height: 720))

        // Render offscreen with SwiftUI: needs no Screen Recording permission.
        let renderer = ImageRenderer(content:
            content
                .environment(\.colorScheme, .light)
                .environment(\.snapshotMode, true)
                .withServices(model)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { exit(1) }
        try? png.write(to: url)
        exit(0)
    }
}
