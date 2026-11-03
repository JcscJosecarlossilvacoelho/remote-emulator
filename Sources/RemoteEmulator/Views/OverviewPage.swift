import SwiftUI

struct OverviewPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService
    @EnvironmentObject private var metro: MetroService
    @EnvironmentObject private var devices: DeviceService
    @EnvironmentObject private var setup: SetupService

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HeroCard()

            if case .external = host.status, !host.demoMode {
                if !setup.externalAgents.isEmpty {
                    TakeOverBanner()
                } else {
                    Callout(symbol: "info.circle.fill",
                            text: "The host was started outside the app (terminal). Stop it there to control it from Remote Emulator.",
                            tint: .blue)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                StatTile(title: "Devices running", value: "\(devices.runningCount) / \(devices.devices.count)",
                         detail: platformSummary, symbol: "iphone.gen3", tint: Theme.ios)
                StatTile(title: "Agents connected", value: "\(agentCount)",
                         detail: agentCount == 1 ? "session using a device" : "sessions using devices",
                         symbol: "sparkles", tint: .purple)
                StatTile(title: "Metro", value: metroValue, detail: metroDetail, symbol: "shippingbox.fill", tint: .orange)
                StatTile(title: "Engine", value: host.cliVersion.map { "v\($0)" } ?? "—",
                         detail: "agent-device by Callstack", symbol: "cpu", tint: .teal)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Running now").font(.title3.weight(.bold))
                    Spacer()
                    Button("All devices →") { model.page = .devices }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .font(.callout.weight(.medium))
                }
                let running = devices.devices.filter { $0.state != .shutdown }
                if running.isEmpty {
                    EmptyDevicesCard { model.page = .devices }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 14)], spacing: 14) {
                        ForEach(running) { DeviceCard(device: $0) }
                    }
                }
            }
        }
    }

    private var platformSummary: String {
        let ios = devices.devices.filter { $0.platform == .ios }.count
        return "\(ios) iOS · \(devices.devices.count - ios) Android"
    }

    private var agentCount: Int { Set(devices.devices.compactMap(\.claimedBy)).count }

    private var metroValue: String {
        switch metro.status {
        case .running, .external: host.demoMode ? "My Expo App" : (metro.app?.name ?? "Running")
        case .starting: "Bundling"
        case .stopped: "Stopped"
        }
    }

    private var metroDetail: String {
        switch metro.status {
        case .running: "Serving on :\(metro.port)"
        case .external: "Running outside · :\(metro.port)"
        case .starting: "Starting…"
        case .stopped: metro.app == nil ? "No app selected" : "Ready to start"
        }
    }
}

// MARK: - Hero

private struct HeroCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService
    @EnvironmentObject private var devices: DeviceService
    @EnvironmentObject private var setup: SetupService

    private enum Mode { case ready, localOnly, starting, offline, failed(String) }

    private var mode: Mode {
        switch host.status {
        case .starting: return .starting
        case .stopped: return .offline
        case .failed(let message): return .failed(message)
        case .running, .external:
            if !host.daemonHealthy { return .failed("The proxy is up but its agent-device daemon is not answering.") }
            return host.isPrivatelyShared ? .ready : .localOnly
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            decorations
            VStack(alignment: .leading, spacing: 14) {
                livePill
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 15))
                        .opacity(0.88)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560, alignment: .leading)
                }
                if host.status.isUp {
                    urlCapsule
                }
                actions.padding(.top, 4)
            }
            .foregroundStyle(.white)
            .padding(30)
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: shadowColor.opacity(0.35), radius: 22, y: 10)
    }

    @ViewBuilder private var background: some View {
        switch mode {
        case .ready, .starting: Rectangle().fill(Theme.heroReady)
        case .localOnly, .failed: Rectangle().fill(Theme.heroWarn)
        case .offline: Rectangle().fill(Theme.heroOff)
        }
    }

    private var shadowColor: Color {
        switch mode {
        case .ready, .starting: .purple
        case .localOnly, .failed: .orange
        default: .black
        }
    }

    private var decorations: some View {
        GeometryReader { geo in
            ZStack {
                Circle().fill(.white.opacity(0.08)).frame(width: 360).position(x: geo.size.width - 60, y: 10)
                Circle().fill(.white.opacity(0.06)).frame(width: 220).position(x: geo.size.width - 230, y: geo.size.height + 30)
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 150, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.16))
                    .position(x: geo.size.width - 150, y: geo.size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }

    private var livePill: some View {
        HStack(spacing: 6) {
            Circle().fill(pillDot).frame(width: 7, height: 7)
            Text(pillText).font(.caption.weight(.bold)).tracking(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.18)))
    }

    private var pillDot: Color {
        switch mode {
        case .ready: Color(red: 0.45, green: 1, blue: 0.6)
        case .offline: .white.opacity(0.6)
        default: .yellow
        }
    }

    private var pillText: String {
        switch mode {
        case .ready: "LIVE ON YOUR TAILNET"
        case .localOnly: "LOCAL ONLY"
        case .starting: "STARTING"
        case .offline: "OFFLINE"
        case .failed: "ATTENTION"
        }
    }

    private var title: String {
        switch mode {
        case .ready: "Ready for agents"
        case .localOnly: "Running on this Mac only"
        case .starting: "Starting the host…"
        case .offline: "Host is offline"
        case .failed: "Something needs attention"
        }
    }

    private var subtitle: String {
        let running = devices.runningCount
        let deviceText = "\(running) device\(running == 1 ? "" : "s") running"
        switch mode {
        case .ready: return "\(deviceText) · shared privately with your tailnet over HTTPS. Agents on any machine can connect now."
        case .localOnly: return "Connect Tailscale so agents on other machines can reach this Mac — nothing is exposed to the internet."
        case .starting: return "Launching agent-device and publishing it to your tailnet."
        case .offline: return "Start the host so AI agents can drive the simulators and emulators on this Mac."
        case .failed(let message): return message
        }
    }

    private var urlCapsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.caption)
            Text(host.remoteURL).font(.system(size: 12.5, design: .monospaced)).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(.black.opacity(0.18)))
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 10) {
            switch mode {
            case .ready:
                HeroMenuButton(title: "Copy connect command", symbol: "doc.on.clipboard") {
                    ForEach(HostService.CommandStyle.allCases) { style in
                        Button(style.rawValue) { host.copy(host.connectCommand(style)) }
                    }
                }
                HeroButton(title: "Connect guide", symbol: "arrow.right", filled: false) { model.page = .connect }
            case .localOnly:
                HeroButton(title: "Open Tailscale", symbol: "network") { setup.openTailscale() }
                HeroButton(title: "Why?", symbol: "questionmark", filled: false) { model.page = .connect }
            case .starting:
                ProgressView().controlSize(.small).tint(.white)
            case .offline:
                HeroButton(title: "Start host", symbol: "play.fill") { host.start() }
                HeroButton(title: "Setup guide", symbol: "wand.and.stars", filled: false) { model.showOnboarding = true }
            case .failed:
                HeroButton(title: "Restart host", symbol: "arrow.clockwise") { host.restart() }
                HeroButton(title: "View logs", symbol: "text.alignleft", filled: false) { model.page = .logs }
            }
            if case .running = host.status {
                HeroButton(title: "Stop", symbol: "stop.fill", filled: false) { host.stop() }
            }
        }
    }
}

struct HeroButton: View {
    let title: String
    let symbol: String
    var filled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HeroButtonLabel(title: title, symbol: symbol, filled: filled, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct HeroButtonLabel: View {
    let title: String
    let symbol: String
    var filled = true
    var hovering = false

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 13.5, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(filled ? Color.white : Color.white.opacity(hovering ? 0.26 : 0.16)))
            .foregroundStyle(filled ? Color(red: 0.32, green: 0.22, blue: 0.85) : .white)
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.spring(duration: 0.2), value: hovering)
    }
}

struct HeroMenuButton<Items: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var items: Items
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        if snapshotMode {
            HeroButtonLabel(title: title, symbol: symbol)
        } else {
            Menu { items } label: { HeroButtonLabel(title: title, symbol: symbol) }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
        }
    }
}

// MARK: - Take over / empty state

private struct TakeOverBanner: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var setup: SetupService

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.blue.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text("A host is running outside the app").font(.headline)
                Text("Found \(setup.externalAgents.count) LaunchAgent\(setup.externalAgents.count == 1 ? "" : "s") running agent-device / Metro. Take over to control everything from here — they're archived, not deleted.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                Task { await model.takeOver() }
            } label: {
                if model.takingOver { ProgressView().controlSize(.small) } else { Text("Take over") }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.takingOver)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.blue.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.blue.opacity(0.2)))
    }
}

private struct EmptyDevicesCard: View {
    let browse: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "iphone.gen3.badge.play")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("No devices running").font(.headline)
                Text("Boot a simulator or emulator — or let your agent boot one with `agent-device open`.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Browse devices", action: browse).buttonStyle(.bordered).controlSize(.large)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(Color.primary.opacity(0.15)))
    }
}
