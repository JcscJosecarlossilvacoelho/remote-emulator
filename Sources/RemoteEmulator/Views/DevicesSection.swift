import SwiftUI

struct DevicesSection: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", ios = "iOS", android = "Android", running = "Running"
        var id: String { rawValue }
    }

    @EnvironmentObject private var devices: DeviceService
    @Environment(\.snapshotMode) private var snapshotMode
    @State private var filter: Filter = .all
    @State private var query = ""

    private var visible: [Device] {
        // Screenshots show only stock device names, never custom (personal) ones.
        let source = snapshotMode
            ? Array(devices.devices.filter { ["iPhone", "iPad", "Pixel"].contains(where: $0.name.hasPrefix) }.prefix(8))
            : devices.devices
        return source.filter { device in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .ios: device.platform == .ios
            case .android: device.platform == .android
            case .running: device.state != .shutdown
            }
            return matchesFilter && (query.isEmpty || device.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Devices").font(.title2.weight(.bold))
                    Text(summary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                SearchField(text: $query, prompt: "Search devices")
                    .frame(width: 190)
                SegmentedControl(options: Filter.allCases, selection: $filter) { $0.rawValue }
                IconButton(symbol: "arrow.clockwise", help: "Refresh") { Task { await devices.refresh() } }
            }

            if let error = devices.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }

            if visible.isEmpty {
                ContentUnavailableView(
                    devices.devices.isEmpty ? "Looking for devices…" : "No devices match",
                    systemImage: "iphone.gen3.slash",
                    description: Text(devices.devices.isEmpty
                                      ? "Install Xcode simulators or Android Studio emulators to get started."
                                      : "Try another filter.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 14)], spacing: 14) {
                    ForEach(visible) { DeviceCard(device: $0) }
                }
            }
        }
    }

    private var summary: String {
        let ios = devices.devices.filter { $0.platform == .ios }.count
        let android = devices.devices.count - ios
        let claimed = devices.devices.filter { $0.claimedBy != nil }.count
        var parts = ["\(devices.runningCount) running", "\(ios) iOS", "\(android) Android"]
        if claimed > 0 { parts.append("\(claimed) in use by agents") }
        return parts.joined(separator: " · ")
    }
}

struct DeviceCard: View {
    let device: Device
    @EnvironmentObject private var devices: DeviceService
    @State private var hovering = false
    @State private var copied = false

    private var tint: Color { Theme.tint(device.platform) }
    private var isOn: Bool { device.state == .booted }
    private var isBusy: Bool { device.state == .booting || device.state == .shuttingDown }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.12)))
                        .frame(width: 52, height: 52)
                    Image(systemName: device.symbol)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isOn ? .white : tint)
                        .symbolEffect(.pulse, isActive: isBusy)
                }
                Spacer()
                PlatformBadge(platform: device.platform)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name).font(.headline).lineLimit(1)
                Text(device.osVersion).font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Circle().fill(stateColor).frame(width: 7, height: 7)
                Text(device.state.label).font(.caption.weight(.medium)).foregroundStyle(stateColor)
                if let owner = device.claimedBy {
                    Text("·").foregroundStyle(.tertiary)
                    Label(owner, systemImage: "sparkles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.purple)
                        .lineLimit(1)
                        .help("In use by agent session \(owner)")
                }
            }

            HStack(spacing: 8) {
                Button {
                    isOn ? devices.shutdown(device) : devices.boot(device)
                } label: {
                    Label(isOn ? "Shut down" : "Boot", systemImage: isOn ? "power" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(isOn ? .red : tint)
                .disabled(isBusy)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(device.agentSelector, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "terminal")
                }
                .buttonStyle(.bordered)
                .help("Copy agent-device selector: \(device.agentSelector)")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: (isOn ? tint : .black).opacity(hovering ? 0.22 : (isOn ? 0.12 : 0.05)), radius: hovering ? 12 : 7, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isOn ? tint.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: isOn ? 1.5 : 1)
        )
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.spring(duration: 0.25), value: hovering)
        .animation(.easeInOut(duration: 0.25), value: device.state)
        .onHover { hovering = $0 }
    }

    private var stateColor: Color {
        switch device.state {
        case .booted: Theme.ok
        case .booting, .shuttingDown: Theme.warn
        case .shutdown: .secondary
        }
    }
}

struct PlatformBadge: View {
    let platform: Platform
    var body: some View {
        HStack(spacing: 4) {
            if platform == .ios { Image(systemName: "apple.logo") }
            Text(platform.label)
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.tint(platform).opacity(0.14)))
        .foregroundStyle(Theme.tint(platform))
    }
}
