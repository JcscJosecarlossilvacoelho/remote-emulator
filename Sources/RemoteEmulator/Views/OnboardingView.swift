import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, requirements, host, app, connect

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .requirements: "Check"
            case .host: "Host"
            case .app: "Your app"
            case .connect: "Connect"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService
    @EnvironmentObject private var setup: SetupService
    @State var step: Step = .welcome

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, 22)
                .padding(.horizontal, 32)

            Group {
                switch step {
                case .welcome: WelcomeStep()
                case .requirements: RequirementsStep()
                case .host: HostStep()
                case .app: AppStep()
                case .connect: ConnectStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40)
            .padding(.top, 26)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            Divider()
            footer.padding(.horizontal, 28).padding(.vertical, 16)
        }
        .frame(width: 780, height: 600)
        .background(Theme.canvas)
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.self) { item in
                let done = item.rawValue < step.rawValue
                let current = item == step
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(current || done ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.08)))
                            .frame(width: 22, height: 22)
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        } else {
                            Text("\(item.rawValue + 1)").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(current ? .white : .secondary)
                        }
                    }
                    Text(item.title)
                        .font(.caption.weight(current ? .semibold : .regular))
                        .foregroundStyle(current ? .primary : .secondary)
                }
                if item != Step.allCases.last {
                    Capsule().fill(done ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.1)))
                        .frame(height: 2)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if step == .welcome {
                Button("Skip setup") { finish() }.buttonStyle(.plain).foregroundStyle(.secondary)
            } else {
                Button { go(-1) } label: { Label("Back", systemImage: "chevron.left") }
                    .controlSize(.large)
            }
            Spacer()
            if let hint = blockingHint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                step == .connect ? finish() : go(1)
            } label: {
                Text(primaryTitle).frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.42, green: 0.28, blue: 0.95))
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(blockingHint != nil)
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .app: model.metro.app == nil ? "Skip for now" : "Continue"
        case .connect: "Finish"
        default: "Continue"
        }
    }

    private var blockingHint: String? {
        switch step {
        case .requirements where !setup.canHost: "Install the missing items to continue"
        case .host where !host.status.isUp: "Start the host to continue"
        default: nil
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.spring(duration: 0.35)) { step = next }
    }

    private func finish() {
        model.onboardingCompleted = true
        model.showOnboarding = false
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 22) {
            AppGlyph(size: 92).padding(.top, 8)
            VStack(spacing: 8) {
                Text("Welcome to Remote Emulator")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Turn this Mac into a device host for AI agents. Claude Code, Cursor or any agent on another machine can drive your iOS simulators and Android emulators — privately.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }
            HStack(spacing: 14) {
                feature("iphone.gen3", "Multi-device", "Every simulator & emulator, one place. See which agent uses which.", Theme.ios)
                feature("lock.shield.fill", "Private", "Tailnet-only HTTPS + token. Never on the public internet.", .teal)
                feature("sparkles", "Any agent", "Claude Code, Cursor, MCP or plain CLI — from any OS.", .purple)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(_ symbol: String, _ title: String, _ text: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.gradient))
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StepTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
            Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RequirementsStep: View {
    @EnvironmentObject private var setup: SetupService

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                StepTitle(title: "Let's check this Mac", subtitle: "You need at least one device platform, Node.js and agent-device. Tailscale lets other machines connect.")
                Button { Task { await setup.runChecks() } } label: { Label("Check again", systemImage: "arrow.clockwise") }
            }
            VStack(spacing: 0) {
                row("hammer.fill", "Xcode", "iOS simulators", setup.xcode) {
                    if !setup.xcode.isOK { linkButton("Get Xcode", "macappstore://apps.apple.com/app/id497799835") }
                }
                Divider().padding(.leading, 56)
                row("candybarphone", "Android Studio", "Android emulators (optional)", setup.android) {
                    if !setup.android.isOK { linkButton("Get Android Studio", "https://developer.android.com/studio") }
                }
                Divider().padding(.leading, 56)
                row("chevron.left.forwardslash.chevron.right", "Node.js 22.12+", "Runs agent-device", setup.node) {
                    if !setup.node.isOK { linkButton("Get Node.js", "https://nodejs.org") }
                }
                Divider().padding(.leading, 56)
                row("cpu", "agent-device", "The engine that drives devices", setup.agentDevice) {
                    if !setup.agentDevice.isOK {
                        Button {
                            Task { await setup.installAgentDevice() }
                        } label: {
                            if setup.installing { ProgressView().controlSize(.small) } else { Text("Install") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(setup.installing || setup.node.isBlocking)
                    }
                }
                Divider().padding(.leading, 56)
                row("network", "Tailscale", "Private access from other machines", setup.tailscale) {
                    switch setup.tailscale {
                    case .missing: linkButton("Get Tailscale", "https://tailscale.com/download/mac")
                    case .warning(let text) where text.contains("HTTPS"):
                        linkButton("Open admin console", "https://login.tailscale.com/admin/dns")
                    case .warning: Button("Open Tailscale") { setup.openTailscale() }
                    default: EmptyView()
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))

            if let error = setup.installError {
                Callout(symbol: "exclamationmark.triangle.fill", text: error, tint: .red)
            }
        }
    }

    private func row<Action: View>(_ symbol: String, _ title: String, _ subtitle: String, _ check: SetupService.Check,
                                   @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(check == .checking ? subtitle : check.detail)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            action()
            statusIcon(check)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder private func statusIcon(_ check: SetupService.Check) -> some View {
        switch check {
        case .checking: ProgressView().controlSize(.small).frame(width: 20)
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok).font(.title3)
        case .warning: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.warn).font(.title3)
        case .missing: Image(systemName: "xmark.circle.fill").foregroundStyle(.red.opacity(0.8)).font(.title3)
        }
    }

    private func linkButton(_ title: String, _ url: String) -> some View {
        Button(title) { NSWorkspace.shared.open(URL(string: url)!) }
    }
}

private struct HostStep: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService
    @EnvironmentObject private var setup: SetupService

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(title: "Start your host", subtitle: "Remote Emulator runs agent-device on 127.0.0.1 and shares it only with your tailnet over HTTPS.")

            if !setup.externalAgents.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(.blue).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Found an existing host setup").font(.headline)
                        Text("\(setup.externalAgents.count) LaunchAgent\(setup.externalAgents.count == 1 ? "" : "s") already run agent-device or Metro. Let the app take over — they're archived in ~/.agent-device-host, not deleted.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.takeOver() }
                    } label: {
                        if model.takingOver { ProgressView().controlSize(.small) } else { Text("Take over") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.takingOver)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.blue.opacity(0.08)))
            }

            HStack(spacing: 18) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.15)).frame(width: 76, height: 76)
                    Image(systemName: statusSymbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .symbolEffect(.pulse, isActive: host.status == .starting)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle).font(.title2.weight(.bold))
                    Text(host.remoteURL).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                switch host.status {
                case .stopped, .failed:
                    Button { host.start() } label: { Label("Start host", systemImage: "play.fill").frame(minWidth: 110) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                case .starting:
                    ProgressView()
                default:
                    EmptyView()
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))

            if case .failed(let message) = host.status {
                Callout(symbol: "exclamationmark.triangle.fill", text: message, tint: .red)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Start the host automatically when Remote Emulator opens", isOn: $model.startHostOnLaunch)
                Toggle("Open Remote Emulator at login (keeps devices available after a reboot)", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }
                ))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private var statusColor: Color {
        switch host.status {
        case .running, .external: host.isPrivatelyShared ? Theme.ok : Theme.warn
        case .starting: .purple
        case .failed: .red
        case .stopped: .secondary
        }
    }

    private var statusSymbol: String {
        switch host.status {
        case .running, .external: host.isPrivatelyShared ? "checkmark.shield.fill" : "wifi.exclamationmark"
        case .starting: "antenna.radiowaves.left.and.right"
        case .failed: "exclamationmark.triangle.fill"
        case .stopped: "power"
        }
    }

    private var statusTitle: String {
        switch host.status {
        case .running, .external: host.isPrivatelyShared ? "Host is live on your tailnet" : "Host running — connect Tailscale to share"
        case .starting: "Starting…"
        case .failed: "Couldn't start the host"
        case .stopped: "Host is off"
        }
    }
}

private struct AppStep: View {
    @EnvironmentObject private var metro: MetroService

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(title: "Which app will agents test?", subtitle: "Pick your Expo / React Native project. Remote Emulator runs Metro for it so devices load your latest JavaScript. You can change it anytime.")

            Button { metro.chooseFolder() } label: {
                HStack(spacing: 16) {
                    Image(systemName: metro.app == nil ? "folder.badge.plus" : "shippingbox.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.gradient))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metro.app?.name ?? "Choose app folder…").font(.title3.weight(.bold))
                        Text(metro.app.map { $0.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
                             ?? "The folder with your app's package.json")
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        if let app = metro.app {
                            Text([app.bundleIdentifier, app.androidPackage].compactMap { $0 }.uniqued().joined(separator: " · "))
                                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(metro.app == nil ? "Browse" : "Change").font(.callout.weight(.semibold)).foregroundStyle(.orange)
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.orange.opacity(metro.app == nil ? 0.15 : 0.45), style: StrokeStyle(lineWidth: 1.5, dash: metro.app == nil ? [6, 5] : [])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if metro.app != nil {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Metro").font(.headline)
                        Text(metroText).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    switch metro.status {
                    case .stopped:
                        Button { metro.start() } label: { Label("Start Metro", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent).tint(.orange)
                    case .starting: ProgressView().controlSize(.small)
                    default: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok).font(.title2)
                    }
                }
                Callout(symbol: "lightbulb.fill",
                        text: "Install the app once on each device: Expo Go, or a development build with `npx expo run:ios` / `npx expo run:android` when you use native modules.",
                        tint: .yellow)
            }
        }
    }

    private var metroText: String {
        switch metro.status {
        case .running: "Serving on port \(metro.port)"
        case .external: "Already running on port \(metro.port)"
        case .starting: "Bundling…"
        case .stopped: "Not running"
        }
    }
}

private struct ConnectStep: View {
    @EnvironmentObject private var host: HostService
    @State private var style: HostService.CommandStyle = .prompt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(title: "Connect your agent 🎉", subtitle: "On the other machine: install Tailscale (same account) and Node.js, then run this. It contains your token — share it through a secure channel.")
            SegmentedControl(options: HostService.CommandStyle.allCases, selection: $style) { $0.rawValue }
            CodeBlock(display: host.connectCommand(style).replacingOccurrences(of: host.token, with: String(repeating: "•", count: 16)),
                      copyText: host.connectCommand(style))
            Callout(symbol: "sparkles",
                    text: "Running several agents? Give each its own AGENT_DEVICE_SESSION — each gets its own device, and you'll see who's using what in Devices.",
                    tint: .purple)
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
