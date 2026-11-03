import SwiftUI

// MARK: - App & Metro

struct AppPage: View {
    @EnvironmentObject private var metro: MetroService
    @EnvironmentObject private var host: HostService

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "App & Metro", subtitle: "The Expo / React Native app your agents test, served from this Mac.") {
                Button { metro.chooseFolder() } label: { Label("Choose app folder…", systemImage: "folder") }
                    .controlSize(.large)
            }

            HStack(alignment: .top, spacing: 16) {
                appCard
                metroCard.frame(width: 300)
            }
            .fixedSize(horizontal: false, vertical: true)

            if !metro.recents.isEmpty && !host.demoMode {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent apps").font(.title3.weight(.bold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                        ForEach(metro.recents, id: \.self) { url in
                            RecentAppTile(url: url, active: url == metro.app?.directory) { metro.select(url) }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Install the app on each device once").font(.title3.weight(.bold))
                Text("Use Expo Go for quick checks, or a development build when the app has native modules (push notifications, custom native code). Builds run from the app folder:")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                CodeBlock(display: """
                cd \(host.demoMode ? "~/code/my-expo-app" : (metro.app?.directory.path ?? "<your-app>"))
                npx expo run:ios        # iOS simulator development build
                npx expo run:android    # Android emulator development build
                """)
            }
        }
    }

    private var appCard: some View {
        Card(title: "Active app", symbol: "app.badge.fill", tint: .orange) {
            if host.demoMode {
                appDetails(name: "My Expo App", ios: "com.example.myapp", android: "com.example.myapp", folder: "~/code/my-expo-app", sdk: "~58.0.0")
            } else if let app = metro.app {
                appDetails(name: app.name, ios: app.bundleIdentifier, android: app.androidPackage, folder: app.directory.path, sdk: app.sdkVersion)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No app selected yet").font(.title3.weight(.semibold))
                    Text("Pick the folder that contains your app's package.json.").foregroundStyle(.secondary)
                    Button { metro.chooseFolder() } label: { Label("Choose app folder…", systemImage: "folder") }
                        .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
                }
            }
        }
    }

    private func appDetails(name: String, ios: String?, android: String?, folder: String, sdk: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name).font(.system(size: 22, weight: .bold, design: .rounded))
            InfoRow(label: "iOS", value: ios ?? "—", monospaced: true, copyable: ios != nil)
            InfoRow(label: "Android", value: android ?? "—", monospaced: true, copyable: android != nil)
            InfoRow(label: "Expo SDK", value: sdk ?? "—", monospaced: true)
            InfoRow(label: "Folder", value: folder, monospaced: true)
        }
    }

    private var metroCard: some View {
        Card(title: "Metro", symbol: "bolt.fill", tint: .yellow) {
            switch metro.status {
            case .running: StatusPill(text: "Serving", color: Theme.ok)
            case .external: StatusPill(text: "External", color: Theme.ok)
            case .starting: StatusPill(text: "Bundling", color: Theme.warn)
            case .stopped: StatusPill(text: "Stopped", color: Theme.off)
            }
        } content: {
            Text("Serves your JavaScript on port \(metro.port). Android emulators get `adb reverse` automatically.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            switch metro.status {
            case .running, .starting:
                PrimaryButton(title: "Stop Metro", symbol: "stop.fill", destructive: true) { metro.stop() }
            case .external:
                PrimaryButton(title: "Running outside the app", symbol: "lock.fill", tint: .gray) {}.disabled(true)
            case .stopped:
                PrimaryButton(title: "Start Metro", symbol: "play.fill", tint: .orange) { metro.start() }
                    .disabled(metro.app == nil)
            }
        }
    }
}

private struct RecentAppTile: View {
    let url: URL
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(active ? .white : .orange)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(active ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color.orange.opacity(0.12))))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ExpoApp.load(from: url)?.name ?? url.lastPathComponent).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(active ? Color.orange.opacity(0.5) : Color.primary.opacity(hovering ? 0.15 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Connect agents

struct ConnectPage: View {
    @EnvironmentObject private var host: HostService
    @State private var style: HostService.CommandStyle = .prompt
    @State private var revealToken = false
    @State private var confirmRotate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Connect agents", subtitle: "Run these on the machine where Claude Code, Cursor or your agent lives.")

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 18) {
                    step(1, "Join the same tailnet", "Install Tailscale on the agent machine and sign in with the same account. Nothing is exposed to the internet.")
                    step(2, "Install & connect", "Same agent-device version as this Mac. The command includes your token — send it through a secure channel.")
                    SegmentedControl(options: HostService.CommandStyle.allCases, selection: $style) { $0.rawValue }
                    CodeBlock(display: masked(host.connectCommand(style)), copyText: host.connectCommand(style))
                    step(3, "Drive the devices", "Each agent uses its own session; agent-device leases a separate device to each one.")
                    CodeBlock(display: """
                    agent-device open com.example.app --platform ios
                    agent-device snapshot -i              # UI tree with refs (@e1…)
                    agent-device press @e3 --settle       # tap
                    agent-device screenshot ./screen.png  # saved on the agent machine
                    agent-device close
                    """)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                accessCard.frame(width: 320)
            }
        }
        .confirmationDialog("Generate a new token?", isPresented: $confirmRotate) {
            Button("Generate new token", role: .destructive) { host.rotateToken() }
        } message: {
            Text("Connected agents will need the new connect command.")
        }
    }

    private func masked(_ command: String) -> String {
        command.replacingOccurrences(of: host.token, with: String(repeating: "•", count: 16))
    }

    private func step(_ number: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.brand))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessCard: some View {
        Card(title: "Remote access", symbol: "lock.shield.fill", tint: .teal) {
            VStack(alignment: .leading, spacing: 10) {
                InfoRow(label: "URL", value: host.remoteURL, monospaced: true, copyable: true)
                HStack(spacing: 4) {
                    InfoRow(label: "Token",
                            value: revealToken && !host.demoMode ? host.token : String(repeating: "•", count: 20),
                            monospaced: true)
                    IconButton(symbol: revealToken ? "eye.slash" : "eye", help: "Show / hide") {
                        if !host.demoMode { revealToken.toggle() }
                    }
                    IconButton(symbol: "arrow.triangle.2.circlepath", help: "Generate a new token") { confirmRotate = true }
                }
                InfoRow(label: "Session", value: host.sessionName, monospaced: true)
            }
            Callout(symbol: host.isPrivatelyShared ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                    text: host.isPrivatelyShared
                        ? "Private to your tailnet over HTTPS. The proxy itself only listens on 127.0.0.1."
                        : "Not shared yet — start Tailscale on this Mac.",
                    tint: host.isPrivatelyShared ? .teal : .orange)
            Text("Anyone with the token can control your simulators. Rotate it if it leaks.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Logs

struct LogsPage: View {
    enum Source: String, CaseIterable, Identifiable {
        case host = "Host", metro = "Metro"
        var id: String { rawValue }
    }

    @EnvironmentObject private var host: HostService
    @EnvironmentObject private var metro: MetroService
    @State private var source: Source = .host

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Logs", subtitle: "Live output from processes this app runs. Tokens are redacted.") {
                HStack(spacing: 10) {
                    SegmentedControl(options: Source.allCases, selection: $source) { $0.rawValue }
                    Button("Clear") { process.clear() }.controlSize(.large)
                }
            }
            LogText(process: process, externalHint: externalHint)
                .frame(height: 560)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var process: ManagedProcess { source == .host ? host.process : metro.process }

    private var externalHint: String? {
        switch source {
        case .host:
            if case .external = host.status { return "The host is running outside the app, so its output isn't captured here." }
        case .metro:
            if metro.status == .external { return "Metro is running outside the app, so its output isn't captured here." }
        }
        return process.lines.isEmpty ? "Nothing yet." : nil
    }
}
