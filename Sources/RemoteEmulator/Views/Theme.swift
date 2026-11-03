import SwiftUI

enum Theme {
    static let ios = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let android = Color(red: 0.20, green: 0.80, blue: 0.47)
    static let brand = LinearGradient(
        colors: [Color(red: 0.38, green: 0.30, blue: 0.98), Color(red: 0.75, green: 0.32, blue: 0.95)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let ok = Color.green
    static let warn = Color.orange
    static let off = Color.secondary

    static func tint(_ platform: Platform) -> Color { platform == .ios ? ios : android }

    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color.primary.opacity(0.035)

    static let heroReady = LinearGradient(
        colors: [Color(red: 0.30, green: 0.22, blue: 0.92), Color(red: 0.62, green: 0.25, blue: 0.93), Color(red: 0.93, green: 0.36, blue: 0.70)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let heroWarn = LinearGradient(
        colors: [Color(red: 0.96, green: 0.55, blue: 0.16), Color(red: 0.93, green: 0.33, blue: 0.33)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let heroOff = LinearGradient(
        colors: [Color(red: 0.20, green: 0.22, blue: 0.30), Color(red: 0.33, green: 0.35, blue: 0.46)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// Rounded panel used for every section of the dashboard.
struct Card<Content: View, Accessory: View>: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
                Text(title).font(.headline)
                Spacer(minLength: 0)
                accessory
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}

extension Card where Accessory == EmptyView {
    init(title: String, symbol: String, tint: Color = .accentColor, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, tint: tint, accessory: { EmptyView() }, content: content)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(color.opacity(0.35), lineWidth: pulsing ? 4 : 0))
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
        .foregroundStyle(color == .secondary ? Color.secondary : color)
    }
}

/// Label/value row with an optional copy button.
struct InfoRow: View {
    let label: String
    let value: String
    var monospaced = false
    var copyable = false

    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if copyable {
                IconButton(symbol: copied ? "checkmark" : "doc.on.doc", help: "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
            }
        }
    }
}

struct PrimaryButton: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(destructive ? .red : tint)
        .controlSize(.large)
    }
}

// MARK: - Pure SwiftUI controls
// These avoid AppKit-backed controls so the dashboard also renders offscreen
// (README screenshots) and looks the same everywhere.

private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True while rendering the dashboard offscreen for screenshots.
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

struct IconButton: View {
    let symbol: String
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

struct SegmentedControl<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    withAnimation(.spring(duration: 0.25)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            if snapshotMode {
                Text(prompt).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            } else {
                TextField(prompt, text: $text).textFieldStyle(.plain)
                if !text.isEmpty {
                    IconButton(symbol: "xmark.circle.fill", help: "Clear") { text = "" }
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}

/// A prominent button that opens a menu (falls back to a plain look offscreen).
struct MenuButton<Items: View>: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    var prominent = true
    @ViewBuilder var items: Items
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let label = Label(title, systemImage: symbol).frame(maxWidth: prominent ? .infinity : nil)
        if snapshotMode {
            if prominent {
                Button {} label: { label }.buttonStyle(.borderedProminent).tint(tint).controlSize(.large)
            } else {
                Button {} label: { label }.buttonStyle(.bordered).controlSize(.large)
            }
        } else {
            Menu { items } label: { label }
                .menuStyle(.button)
                .buttonStyle(prominent ? AnyPrimitiveButtonStyle(.borderedProminent) : AnyPrimitiveButtonStyle(.bordered))
                .tint(prominent ? tint : nil)
                .controlSize(.large)
        }
    }
}

struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

// MARK: - Brand & page building blocks

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

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(tint.opacity(0.14)))
                Spacer()
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

/// Monospaced command block with a copy button. `display` can mask secrets
/// while `copyText` holds the real value.
struct CodeBlock: View {
    let display: String
    var copyText: String?
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(display)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(red: 0.86, green: 0.88, blue: 0.95))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .padding(.trailing, 70)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyText ?? display, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(copied ? 0.25 : 0.12)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.16))
        )
    }
}

/// Soft callout box (info / warning).
struct Callout: View {
    let symbol: String
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 14, weight: .semibold))
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.10)))
    }
}
