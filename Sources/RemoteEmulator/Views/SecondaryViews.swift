import SwiftUI

// MARK: - Log output

struct LogText: View {
    @ObservedObject var process: ManagedProcess
    let externalHint: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let externalHint, process.lines.isEmpty {
                        Text(externalHint).foregroundStyle(.white.opacity(0.5))
                    }
                    ForEach(Array(process.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).foregroundStyle(color(for: line))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.16))
            .onChange(of: process.lines.count) { proxy.scrollTo("bottom") }
            .onAppear { proxy.scrollTo("bottom") }
        }
    }

    private func color(for line: String) -> Color {
        if line.contains("ERROR") || line.contains("Error") { return Color(red: 1, green: 0.45, blue: 0.45) }
        if line.contains("WARN") { return Color(red: 1, green: 0.8, blue: 0.4) }
        if line.hasPrefix("—") { return Color(red: 0.6, green: 0.55, blue: 1) }
        return Color(red: 0.86, green: 0.88, blue: 0.95)
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    let openDashboard: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService
    @EnvironmentObject private var metro: MetroService
    @EnvironmentObject private var devices: DeviceService
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppGlyph(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Remote Emulator").font(.headline)
                    Text(host.status.isUp ? (host.isPrivatelyShared ? "Ready for agents" : "Local only") : "Host offline")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(host.status.isUp ? Theme.ok : .secondary).frame(width: 9, height: 9)
            }

            let running = devices.devices.filter { $0.state != .shutdown }
            VStack(alignment: .leading, spacing: 6) {
                Text("RUNNING").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                if running.isEmpty {
                    Text("No devices running").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(running) { device in
                    HStack(spacing: 8) {
                        Image(systemName: device.symbol).foregroundStyle(Theme.tint(device.platform)).frame(width: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(device.name).font(.callout).lineLimit(1)
                            Text(device.claimedBy.map { "agent: \($0)" } ?? device.osVersion)
                                .font(.caption2).foregroundStyle(device.claimedBy == nil ? .secondary : Color.purple)
                        }
                        Spacer()
                        Button { devices.shutdown(device) } label: { Image(systemName: "power") }
                            .buttonStyle(.borderless)
                            .help("Shut down")
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                if case .running = host.status {
                    Button("Stop host", role: .destructive) { host.stop() }
                } else if !host.status.isUp {
                    Button("Start host") { host.start() }
                }
                if metro.status == .stopped, metro.app != nil {
                    Button("Start Metro") { metro.start() }
                } else if metro.status == .running || metro.status == .starting {
                    Button("Stop Metro") { metro.stop() }
                }
            }
            .controlSize(.small)

            Button {
                host.copy(host.agentPrompt)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Label(copied ? "Prompt copied!" : "Copy prompt for remote agent", systemImage: copied ? "checkmark" : "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)

            HStack {
                Button("Open dashboard", action: openDashboard)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 300)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService
    @AppStorage("proxyPort") private var port = 4310
    @AppStorage("sessionName") private var sessionName = "remote-agent"

    var body: some View {
        Form {
            Section("Host") {
                TextField("Proxy port", value: $port, format: .number.grouping(.never))
                TextField("Default agent session name", text: $sessionName)
                Toggle("Start the host when the app opens", isOn: $model.startHostOnLaunch)
                Toggle("Open Remote Emulator at login", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }
                ))
            }
            Section("Data") {
                LabeledContent("Folder", value: "~/.agent-device-host")
                Button("Show in Finder") { NSWorkspace.shared.open(HostPaths.directory) }
            }
            Section {
                Text("The proxy only listens on 127.0.0.1. Remote access goes through `tailscale serve` (your tailnet only). Anyone with the token can control the devices — share it through a secure channel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
