import SwiftUI

enum Theme {
    // Palette shared with josecoelho.dev: paper, ink, forest, leaf, peach, beard.
    static let paper = Color(hex: 0xEFE9DF)
    static let forest = Color(hex: 0x17432C)
    static let forestDeep = Color(hex: 0x0E2C1D)
    static let leaf = Color(hex: 0x3FBF7A)
    static let peach = Color(hex: 0xF2A983)
    static let beard = Color(hex: 0x5A3726)
    static let coffee = Color(hex: 0xFFDD00)

    /// Main accent: forest on paper, leaf on dark.
    static let accent = Color(light: 0x17432C, dark: 0x3FBF7A)
    static let ios = Color(light: 0xC8693F, dark: 0xF2A983)
    static let android = Color(light: 0x23965A, dark: 0x3FBF7A)
    static let agent = Color(light: 0x8A4F33, dark: 0xF2A983)
    static let brand = LinearGradient(colors: [Color(hex: 0x1F5A3A), forest], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ok = Color(light: 0x23965A, dark: 0x3FBF7A)
    static let warn = Color(light: 0xD0663A, dark: 0xF2A983)
    static let off = Color.secondary

    static func tint(_ platform: Platform) -> Color { platform == .ios ? ios : android }

    static let canvas = Color(light: 0xEFE9DF, dark: 0x0F1813)
    static let surface = Color(light: 0xF8F4EC, dark: 0x16231B)
    static let sidebar = Color(light: 0xE6DFD2, dark: 0x0B130F)
    static let codeBackground = Color(hex: 0x0E2C1D)
    static let codeText = Color(hex: 0xEFE9DF)

    static let heroReady = brand
    static let heroWarn = LinearGradient(colors: [Color(hex: 0xF2A983), Color(hex: 0xD0663A)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let heroOff = LinearGradient(colors: [Color(hex: 0x2A3A31), Color(hex: 0x121512)], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Display type: heavy and tight, like the site's headlines.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy) }
    /// Italic serif accent (New York), like the site's *open-source*.
    static func serif(_ size: CGFloat) -> Font { .system(size: size, design: .serif).italic() }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Adapts to light/dark appearance.
    init(light: UInt32, dark: UInt32) {
        func ns(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light)
        })
    }
}

/// Rounded panel used for every section of the dashboard.
struct Card<Content: View, Accessory: View>: View {
    let title: String
    let symbol: String
    var tint: Color = Theme.accent
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.paper)
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
                .fill(Theme.surface)
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
    var tint: Color = Theme.accent
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
                                    .fill(Theme.surface)
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
    var tint: Color = Theme.accent
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
                    .foregroundStyle(Theme.paper)
            )
            .shadow(color: Theme.forest.opacity(0.35), radius: size * 0.15, y: size * 0.06)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.display(30)).tracking(-0.8)
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
                .font(Theme.display(24)).tracking(-0.5)
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
                .fill(Theme.surface)
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
                .foregroundStyle(Theme.codeText)
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
                .fill(Theme.codeBackground)
        )
    }
}

/// Soft callout box (info / warning).
struct Callout: View {
    let symbol: String
    let text: String
    var tint: Color = Theme.accent

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

// MARK: - Compact controls

/// iOS-style switch drawn in SwiftUI (renders offscreen, unlike Toggle).
struct PillSwitch: View {
    let isOn: Bool
    var tint: Color = Theme.ok
    var busy = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.14)))
                    .frame(width: 36, height: 21)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .frame(width: 17, height: 17)
                    .padding(2)
                    .overlay {
                        if busy { ProgressView().controlSize(.mini).scaleEffect(0.6) }
                    }
            }
            .animation(.spring(duration: 0.22), value: isOn)
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled || busy)
    }
}

/// Small uppercase section title used in the inspector.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.0)
            .foregroundStyle(.secondary)
    }
}

/// A ScrollView that becomes a plain stack offscreen (ImageRenderer can't draw scroll views).
struct AdaptiveScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        if snapshotMode {
            content.frame(maxHeight: .infinity, alignment: .top).clipped()
        } else {
            ScrollView { content }
        }
    }
}

/// Full-width gradient call-to-action.
struct BrandButton: View {
    let title: String
    let symbol: String
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(disabled ? AnyShapeStyle(Color.gray.opacity(0.5)) : AnyShapeStyle(Theme.brand))
                        .shadow(color: Theme.forest.opacity(disabled ? 0 : (hovering ? 0.45 : 0.28)), radius: hovering ? 10 : 6, y: 3)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Borderless text/icon menu that draws as a plain label offscreen.
struct CompactMenu<Label: View, Items: View>: View {
    @ViewBuilder var label: Label
    @ViewBuilder var items: Items
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        if snapshotMode {
            label.foregroundStyle(Theme.accent)
        } else {
            Menu { items } label: { label }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
        }
    }
}
