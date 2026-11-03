import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService

    static let background = LinearGradient(
        colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .windowBackgroundColor).opacity(0.94)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        ScrollView { DashboardContent() }
            .background(Self.background.ignoresSafeArea())
            .sheet(isPresented: $model.showLogs) {
                LogsView().environmentObject(host).environmentObject(model.metro)
            }
    }
}

/// The dashboard without the scroll view (also rendered for README screenshots).
struct DashboardContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService
    @EnvironmentObject private var devices: DeviceService

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            HStack(alignment: .top, spacing: 16) {
                HostCard()
                RemoteAccessCard()
                MetroCard()
            }
            .fixedSize(horizontal: false, vertical: true)
            DevicesSection()
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 28)
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppGlyph(size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Remote Emulator").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Let AI agents on any machine drive the simulators and emulators on this Mac.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            overallStatus
            Button { model.showLogs = true } label: { Label("Logs", systemImage: "text.alignleft") }
                .controlSize(.large)
            SettingsLink { Image(systemName: "gearshape") }
                .controlSize(.large)
                .help("Settings")
        }
    }

    @ViewBuilder private var overallStatus: some View {
        if host.status.isUp && host.isPrivatelyShared {
            StatusPill(text: "Ready for agents · \(devices.runningCount) running", color: Theme.ok, pulsing: true)
        } else if host.status.isUp {
            StatusPill(text: "Local only — start Tailscale to share", color: Theme.warn)
        } else {
            StatusPill(text: "Host offline", color: Theme.off)
        }
    }
}

/// The app mark: a phone with signal waves on the brand gradient.
struct AppGlyph: View {
    var size: CGFloat = 40
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Theme.brand)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: Color.purple.opacity(0.35), radius: size * 0.15, y: size * 0.06)
    }
}

// MARK: - Host

struct HostCard: View {
    @EnvironmentObject private var host: HostService

    var body: some View {
        Card(title: "Agent host", symbol: "server.rack", tint: .indigo) {
            statusPill
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Engine", value: "agent-device \(host.cliVersion ?? "—")")
                InfoRow(label: "Listens", value: "127.0.0.1:\(host.port)", monospaced: true)
                InfoRow(label: "Mode", value: modeText)
            }
            if host.status.isUp && !host.daemonHealthy {
                Label("The proxy answers but its agent-device daemon does not. Restart the host.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if case .failed(let message) = host.status {
                Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            switch host.status {
            case .running:
                PrimaryButton(title: "Stop host", symbol: "stop.fill", destructive: true) { host.stop() }
            case .external:
                PrimaryButton(title: "Managed outside the app", symbol: "lock.fill", tint: .gray) {}
                    .disabled(true)
            case .starting:
                PrimaryButton(title: "Starting…", symbol: "hourglass", tint: .indigo) {}.disabled(true)
            case .stopped, .failed:
                PrimaryButton(title: "Start host", symbol: "play.fill", tint: .indigo) { host.start() }
            }
        }
    }

    private var modeText: String {
        switch host.status {
        case .external: "External (launchd / terminal)"
        case .running: "Managed by this app"
        default: "—"
        }
    }

    @ViewBuilder private var statusPill: some View {
        switch host.status {
        case .running(let version), .external(let version):
            StatusPill(text: "Online · v\(version)", color: Theme.ok)
        case .starting: StatusPill(text: "Starting", color: Theme.warn)
        case .stopped: StatusPill(text: "Offline", color: Theme.off)
        case .failed: StatusPill(text: "Error", color: .red)
        }
    }
}

// MARK: - Remote access

struct RemoteAccessCard: View {
    @EnvironmentObject private var host: HostService
    @State private var revealToken = false
    @State private var copiedStyle: HostService.CommandStyle?
    @State private var confirmRotate = false

    var body: some View {
        Card(title: "Remote access", symbol: "lock.shield.fill", tint: .teal) {
            tailscalePill
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "URL", value: host.remoteURL, monospaced: true, copyable: true)
                HStack(spacing: 8) {
                    InfoRow(label: "Token", value: tokenText, monospaced: true, copyable: false)
                    IconButton(symbol: revealToken ? "eye.slash" : "eye", help: revealToken ? "Hide token" : "Show token") {
                        if !host.demoMode { revealToken.toggle() }
                    }
                    IconButton(symbol: "arrow.triangle.2.circlepath", help: "Generate a new token") { confirmRotate = true }
                }
                Text(host.isPrivatelyShared
                     ? "Private to your tailnet over HTTPS. Never exposed to the internet."
                     : "Only reachable from this Mac until Tailscale is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            MenuButton(
                title: copiedStyle.map { "Copied for \($0.rawValue)" } ?? "Copy connect command",
                symbol: copiedStyle == nil ? "doc.on.clipboard" : "checkmark",
                tint: .teal
            ) {
                ForEach(HostService.CommandStyle.allCases) { style in
                    Button(style.rawValue) {
                        host.copy(host.connectCommand(style))
                        copiedStyle = style
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedStyle = nil }
                    }
                }
            }
        }
        .confirmationDialog("Generate a new token?", isPresented: $confirmRotate) {
            Button("Generate new token", role: .destructive) { host.rotateToken() }
        } message: {
            Text("Connected agents will need the new connect command. A host managed outside the app must be restarted to pick it up.")
        }
    }

    private var tokenText: String {
        revealToken && !host.demoMode ? host.token : String(repeating: "•", count: 24)
    }

    @ViewBuilder private var tailscalePill: some View {
        switch host.tailscale {
        case .running where host.serveActive || host.demoMode:
            StatusPill(text: "Tailscale · shared", color: Theme.ok)
        case .running:
            StatusPill(text: "Tailscale · not shared", color: Theme.warn)
        case .stopped:
            StatusPill(text: "Tailscale off", color: Theme.warn)
        case .notInstalled:
            StatusPill(text: "No Tailscale", color: Theme.off)
        }
    }
}

// MARK: - Metro

struct MetroCard: View {
    @EnvironmentObject private var metro: MetroService
    @EnvironmentObject private var host: HostService

    var body: some View {
        Card(title: "Metro", symbol: "shippingbox.fill", tint: .orange) {
            statusPill
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if host.demoMode {
                    InfoRow(label: "App", value: "My Expo App")
                    InfoRow(label: "iOS", value: "com.example.myapp", monospaced: true, copyable: true)
                    InfoRow(label: "Android", value: "com.example.myapp", monospaced: true, copyable: true)
                    InfoRow(label: "Folder", value: "~/code/my-expo-app", monospaced: true)
                } else if let app = metro.app {
                    InfoRow(label: "App", value: app.name)
                    InfoRow(label: "iOS", value: app.bundleIdentifier ?? "—", monospaced: true, copyable: app.bundleIdentifier != nil)
                    InfoRow(label: "Android", value: app.androidPackage ?? "—", monospaced: true, copyable: app.androidPackage != nil)
                    InfoRow(label: "Folder", value: app.directory.path, monospaced: true)
                } else {
                    Text("Pick the Expo / React Native app agents should test.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                switch metro.status {
                case .running, .starting:
                    PrimaryButton(title: "Stop", symbol: "stop.fill", destructive: true) { metro.stop() }
                case .external:
                    PrimaryButton(title: "Running outside", symbol: "lock.fill", tint: .gray) {}.disabled(true)
                case .stopped:
                    PrimaryButton(title: "Start Metro", symbol: "play.fill", tint: .orange) { metro.start() }
                        .disabled(metro.app == nil)
                }
                MenuButton(title: "App", symbol: "arrow.left.arrow.right", prominent: false) {
                    Button("Choose folder…") { metro.chooseFolder() }
                    if !metro.recents.isEmpty {
                        Divider()
                        ForEach(metro.recents, id: \.self) { url in
                            Button(url.lastPathComponent + "  —  " + url.deletingLastPathComponent().lastPathComponent) {
                                metro.select(url)
                            }
                        }
                    }
                }
                .fixedSize()
            }
        }
    }

    @ViewBuilder private var statusPill: some View {
        switch metro.status {
        case .running: StatusPill(text: "Serving :\(metro.port)", color: Theme.ok)
        case .external: StatusPill(text: "External :\(metro.port)", color: Theme.ok)
        case .starting: StatusPill(text: "Bundling", color: Theme.warn)
        case .stopped: StatusPill(text: "Stopped", color: Theme.off)
        }
    }
}
