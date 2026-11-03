import SwiftUI

/// One window, no navigation: devices on the left, everything else on the right.
struct MainView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider()
            HStack(spacing: 0) {
                DeviceList()
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                Inspector()
                    .frame(width: 360)
                    .frame(maxHeight: .infinity)
                    .background(Theme.sidebar)
            }
        }
        .background(Theme.canvas)
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView().withServices(model)
        }
        .sheet(isPresented: $model.showLogs) {
            LogsSheet().withServices(model)
        }
        .sheet(isPresented: $model.showSupport) {
            SupportSheet().environmentObject(model)
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService
    @EnvironmentObject private var setup: SetupService

    var body: some View {
        HStack(spacing: 12) {
            AppGlyph(size: 26)
            Text("Remote Emulator").font(Theme.display(15)).tracking(-0.3)
            Spacer()
            statusChip
            hostControl
            CompactMenu {
                Image(systemName: "ellipsis.circle").font(.system(size: 15)).foregroundStyle(.secondary)
            } items: {
                Button("Setup guide…") { model.showOnboarding = true }
                Button("Logs…") { model.showLogs = true }
                Divider()
                SettingsLink { Text("Settings…") }
                Divider()
                Button("☕ Buy me a coffee") { Links.open(Links.coffee) }
                Button("About the author") { Links.open(Links.author) }
                Button("Report an issue…") { Links.open(Links.issues) }
                Button("GitHub repository") { Links.open(Links.repository) }
            }
        }
        .padding(.leading, 84) // room for the window's traffic lights
        .padding(.trailing, 16)
        .frame(height: 52)
    }

    private var statusChip: some View {
        HStack(spacing: 7) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.7), radius: host.status.isUp ? 3 : 0)
            Text(statusText).font(.system(size: 12.5, weight: .semibold))
            if let remote = host.remoteHost, host.status.isUp {
                Text(remote).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 230)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(statusColor.opacity(0.10)))
    }

    @ViewBuilder private var hostControl: some View {
        if case .external = host.status, !setup.externalAgents.isEmpty, !host.demoMode {
            Button {
                Task { await model.takeOver() }
            } label: {
                if model.takingOver { ProgressView().controlSize(.small) } else { Text("Take over host") }
            }
            .help("A host started outside the app (LaunchAgent) is running. Take over to control it here.")
        } else {
            HStack(spacing: 8) {
                Text("Host").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                PillSwitch(
                    isOn: host.status.isUp,
                    busy: host.status == .starting,
                    disabled: { if case .external = host.status { return true } else { return false } }()
                ) {
                    host.status.isUp ? host.stop() : host.start()
                }
                .help(host.status.isUp ? "Stop the host" : "Start the host")
            }
        }
    }

    private var statusColor: Color {
        switch host.status {
        case .running, .external:
            if !host.daemonHealthy { return .red }
            return host.isPrivatelyShared ? Theme.ok : Theme.warn
        case .starting: return Theme.agent
        case .failed: return .red
        case .stopped: return .secondary
        }
    }

    private var statusText: String {
        switch host.status {
        case .running, .external:
            if !host.daemonHealthy { return "Daemon not responding" }
            return host.isPrivatelyShared ? "Ready for agents" : "Local only — start Tailscale"
        case .starting: return "Starting…"
        case .failed: return "Host error"
        case .stopped: return "Host off"
        }
    }
}

// MARK: - Devices

private struct DeviceList: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", ios = "iOS", android = "Android"
        var id: String { rawValue }
    }

    @EnvironmentObject private var devices: DeviceService
    @Environment(\.snapshotMode) private var snapshotMode
    @State private var filter: Filter = .all
    @State private var query = ""

    private var filtered: [Device] {
        let source = snapshotMode
            ? Array(devices.devices.filter { ["iPhone", "iPad", "Pixel"].contains(where: $0.name.hasPrefix) }.prefix(9))
            : devices.devices
        return source.filter { device in
            (filter == .all || (filter == .ios) == (device.platform == .ios))
                && (query.isEmpty || device.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Devices").font(.system(size: 17, weight: .bold))
                    Text("\(devices.runningCount) running · \(devices.devices.count) available")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                SearchField(text: $query, prompt: "Search").frame(width: 150)
                SegmentedControl(options: Filter.allCases, selection: $filter) { $0.rawValue }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if devices.devices.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Looking for simulators and emulators…").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AdaptiveScroll {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        section("Running", filtered.filter { $0.state != .shutdown })
                        section("iOS simulators", filtered.filter { $0.state == .shutdown && $0.platform == .ios })
                        section("Android emulators", filtered.filter { $0.state == .shutdown && $0.platform == .android })
                    }
                    .padding(.bottom, 16)
                }
            }

            if let error = devices.lastError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).lineLimit(2)
                    .padding(10)
            }
        }
    }

    @ViewBuilder private func section(_ title: String, _ items: [Device]) -> some View {
        if !items.isEmpty {
            HStack {
                SectionLabel(text: title)
                Text("\(items.count)").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)
            ForEach(items) { DeviceRow(device: $0) }
        }
    }
}

private struct DeviceRow: View {
    let device: Device
    @EnvironmentObject private var devices: DeviceService
    @State private var hovering = false
    @State private var copied = false

    private var tint: Color { Theme.tint(device.platform) }
    private var isOn: Bool { device.state == .booted }
    private var isBusy: Bool { device.state == .booting || device.state == .shuttingDown }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOn ? .white : tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.11)))
                )
                .symbolEffect(.pulse, isActive: isBusy)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(device.osVersion)
                    if isBusy {
                        Text("· \(device.state.label)").foregroundStyle(Theme.warn)
                    }
                    if let owner = device.claimedBy {
                        Label(owner, systemImage: "sparkles")
                            .foregroundStyle(Theme.agent)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.agent.opacity(0.1)))
                            .help("In use by agent session “\(owner)”")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if hovering {
                IconButton(symbol: copied ? "checkmark" : "terminal", help: "Copy agent-device selector: \(device.agentSelector)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(device.agentSelector, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
            }
            PillSwitch(isOn: isOn || device.state == .booting, tint: tint, busy: isBusy) {
                isOn ? devices.shutdown(device) : devices.boot(device)
            }
            .help(isOn ? "Shut down" : "Boot")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(hovering ? 0.04 : 0))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Inspector

private struct Inspector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        AdaptiveScroll {
            VStack(alignment: .leading, spacing: 22) {
                ConnectSection()
                Divider()
                AppSection()
                Divider()
                HostSection()
                Divider()
                ActivitySection()
                CoffeeFooter()
            }
            .padding(20)
        }
    }
}

private struct ConnectSection: View {
    @EnvironmentObject private var host: HostService
    @State private var copied = false
    @State private var showPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Connect a remote agent")
            Text("Paste this prompt into **Claude Code** or **Cursor** on the other machine. The agent installs agent-device, connects to this Mac and runs a quick test.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            BrandButton(title: copied ? "Prompt copied!" : "Copy prompt",
                        symbol: copied ? "checkmark" : "sparkles",
                        disabled: !host.status.isUp) {
                host.copy(host.agentPrompt)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
            }

            if !host.status.isUp {
                Label("Turn the host on first.", systemImage: "power").font(.caption).foregroundStyle(.secondary)
            } else if !host.isPrivatelyShared {
                Label("Start Tailscale so other machines can reach this Mac.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Label("Includes your token — send it privately.", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button(showPreview ? "Hide prompt" : "Preview prompt") {
                    withAnimation(.easeInOut(duration: 0.2)) { showPreview.toggle() }
                }
                .buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                Spacer()
                CompactMenu {
                    Text("Shell commands ▾").font(.caption.weight(.medium))
                } items: {
                    ForEach(HostService.CommandStyle.allCases.filter { $0 != .prompt }) { style in
                        Button("Copy for \(style.rawValue)") { host.copy(host.connectCommand(style)) }
                    }
                }
            }

            if showPreview {
                ScrollView {
                    Text(host.agentPrompt.replacingOccurrences(of: host.token, with: "••••••••"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.codeText)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 220)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.codeBackground))
            }
        }
    }
}

private struct AppSection: View {
    @EnvironmentObject private var metro: MetroService
    @EnvironmentObject private var host: HostService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "App under test")

            if let app = shownApp {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.gradient))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                        Text(app.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    changeMenu
                }
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Metro").font(.system(size: 12.5, weight: .medium))
                        Text(metroText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    PillSwitch(isOn: metro.status != .stopped, tint: .orange,
                               busy: metro.status == .starting,
                               disabled: metro.status == .external) {
                        metro.status == .stopped ? metro.start() : metro.stop()
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            } else {
                Text("Pick the Expo / React Native app agents will test. Metro runs here so devices load your latest code.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { metro.chooseFolder() } label: { Label("Choose app folder…", systemImage: "folder") }
                    .controlSize(.large)
            }
        }
    }

    private var shownApp: (name: String, id: String)? {
        if host.demoMode { return ("My Expo App", "com.example.myapp") }
        guard let app = metro.app else { return nil }
        return (app.name, app.bundleIdentifier ?? app.androidPackage ?? app.directory.lastPathComponent)
    }

    private var changeMenu: some View {
        CompactMenu {
            Text("Change ▾").font(.callout.weight(.medium))
        } items: {
            Button("Choose folder…") { metro.chooseFolder() }
            if !metro.recents.isEmpty {
                Divider()
                ForEach(metro.recents, id: \.self) { url in
                    Button(ExpoApp.load(from: url)?.name ?? url.lastPathComponent) { metro.select(url) }
                }
            }
        }
    }

    private var metroText: String {
        switch metro.status {
        case .running: "Serving on :\(metro.port)"
        case .external: "Running outside the app"
        case .starting: "Bundling…"
        case .stopped: "Off"
        }
    }
}

private struct HostSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService
    @State private var reveal = false
    @State private var tokenCopied = false
    @State private var confirmRotate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: "Host")
            InfoRow(label: "URL", value: host.remoteURL, monospaced: true, copyable: true)
            HStack(spacing: 2) {
                InfoRow(label: "Token", value: reveal && !host.demoMode ? host.token : String(repeating: "•", count: 18), monospaced: true)
                IconButton(symbol: reveal ? "eye.slash" : "eye", help: "Show / hide") { if !host.demoMode { reveal.toggle() } }
                IconButton(symbol: tokenCopied ? "checkmark" : "doc.on.doc", help: "Copy token") {
                    guard !host.demoMode else { return }
                    host.copy(host.token)
                    tokenCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { tokenCopied = false }
                }
                IconButton(symbol: "arrow.triangle.2.circlepath", help: "Generate a new token") { confirmRotate = true }
            }
            InfoRow(label: "Engine", value: "agent-device \(host.cliVersion ?? "—")")
            Text("Listens on 127.0.0.1 only. Other machines reach it through your tailnet (HTTPS), never the internet.")
                .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Generate a new token?", isPresented: $confirmRotate) {
            Button("Generate new token", role: .destructive) { model.rotateToken() }
        } message: {
            Text("Remote agents will need the new prompt.")
        }
    }
}

private struct ActivitySection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionLabel(text: "Activity")
                Spacer()
                Button("Open logs") { model.showLogs = true }
                    .buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
            }
            ActivityLines(process: host.process)
        }
    }
}

private struct ActivityLines: View {
    @ObservedObject var process: ManagedProcess

    var body: some View {
        let lines = process.lines.suffix(4)
        VStack(alignment: .leading, spacing: 3) {
            if lines.isEmpty {
                Text("No activity yet.").foregroundStyle(.white.opacity(0.45))
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).lineLimit(1).truncationMode(.tail)
            }
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(Theme.codeText.opacity(0.85))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.codeBackground))
    }
}

private struct CoffeeFooter: View {
    @State private var hovering = false

    var body: some View {
        Button { Links.open(Links.coffee) } label: {
            HStack(spacing: 10) {
                Text("☕").font(.system(size: 20))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Enjoying Remote Emulator?").font(.system(size: 12, weight: .semibold))
                    Text("It's free and open source. Buy me a coffee!").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.coffee.opacity(hovering ? 0.22 : 0.14)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Logs sheet

struct LogsSheet: View {
    enum Source: String, CaseIterable, Identifiable {
        case host = "Host", metro = "Metro"
        var id: String { rawValue }
    }

    @EnvironmentObject private var host: HostService
    @EnvironmentObject private var metro: MetroService
    @Environment(\.dismiss) private var dismiss
    @State private var source: Source = .host

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs").font(.headline)
                Spacer()
                SegmentedControl(options: Source.allCases, selection: $source) { $0.rawValue }
                Button("Clear") { process.clear() }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
            LogText(process: process, externalHint: hint)
        }
        .frame(width: 860, height: 560)
    }

    private var process: ManagedProcess { source == .host ? host.process : metro.process }

    private var hint: String? {
        switch source {
        case .host: if case .external = host.status { return "The host runs outside the app; its output isn't captured here." }
        case .metro: if metro.status == .external { return "Metro runs outside the app; its output isn't captured here." }
        }
        return "Nothing yet."
    }
}
