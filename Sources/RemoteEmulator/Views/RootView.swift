import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService
    @EnvironmentObject private var metro: MetroService
    @EnvironmentObject private var devices: DeviceService

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Divider().ignoresSafeArea()
            ScrollView {
                PageContent(page: model.page)
                    .padding(.horizontal, 32)
                    .padding(.top, 40)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 1200, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.canvas.ignoresSafeArea())
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView()
                .environmentObject(model)
                .environmentObject(host)
                .environmentObject(metro)
                .environmentObject(devices)
                .environmentObject(model.setup)
        }
    }
}

struct PageContent: View {
    let page: Page

    var body: some View {
        switch page {
        case .overview: OverviewPage()
        case .devices: DevicesSection()
        case .app: AppPage()
        case .connect: ConnectPage()
        case .logs: LogsPage()
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var host: HostService
    @EnvironmentObject private var devices: DeviceService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                AppGlyph(size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Remote").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Emulator").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 44)
            .padding(.bottom, 22)

            ForEach(Page.allCases) { page in
                SidebarItem(page: page, badge: badge(for: page), selected: model.page == page) {
                    withAnimation(.easeInOut(duration: 0.18)) { model.page = page }
                }
            }

            Spacer()

            HostStatusBadge()

            Button {
                model.showOnboarding = true
            } label: {
                Label("Setup guide", systemImage: "wand.and.stars")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 12)
        .frame(width: 228)
        .background(Theme.sidebar.ignoresSafeArea())
    }

    private func badge(for page: Page) -> String? {
        switch page {
        case .devices: devices.runningCount > 0 ? "\(devices.runningCount)" : nil
        default: nil
        }
    }
}

private struct SidebarItem: View {
    let page: Page
    let badge: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                Text(page.title).font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.25) : Theme.ok.opacity(0.18)))
                        .foregroundStyle(selected ? .white : Theme.ok)
                }
            }
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.brand)
                        .shadow(color: Color.purple.opacity(0.3), radius: 6, y: 2)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct HostStatusBadge: View {
    @EnvironmentObject private var host: HostService

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 26, height: 26)
                Circle().fill(color).frame(width: 9, height: 9)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .padding(.bottom, 4)
    }

    private var color: Color {
        if host.status.isUp && host.daemonHealthy { return host.isPrivatelyShared ? Theme.ok : Theme.warn }
        if case .failed = host.status { return .red }
        return host.status.isUp ? Theme.warn : .secondary
    }

    private var title: String {
        switch host.status {
        case .running, .external: host.isPrivatelyShared ? "Ready for agents" : "Local only"
        case .starting: "Starting host…"
        case .stopped: "Host offline"
        case .failed: "Host error"
        }
    }

    private var detail: String {
        switch host.status {
        case .running(let v): "agent-device v\(v)"
        case .external: "Running outside the app"
        case .starting: "One moment"
        case .stopped: "Start it from Overview"
        case .failed: "See Logs"
        }
    }
}
