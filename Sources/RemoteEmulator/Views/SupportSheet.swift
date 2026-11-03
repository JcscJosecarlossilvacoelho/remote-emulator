import SwiftUI

/// Shown rarely (after real use, at most every two weeks) — never blocks anything.
struct SupportSheet: View {
    @EnvironmentObject private var model: AppModel

    private var avatar: NSImage? {
        Bundle.main.url(forResource: "author", withExtension: "jpg").flatMap(NSImage.init(contentsOf:))
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let avatar {
                        Image(nsImage: avatar).resizable().scaledToFill()
                    } else {
                        AppGlyph(size: 84)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 2))
                .shadow(color: Color(red: 0.25, green: 0.75, blue: 0.48).opacity(0.5), radius: 16)
                Text("☕").font(.system(size: 28)).offset(x: 6, y: 4)
            }
            .padding(.top, 6)

            VStack(spacing: 8) {
                Text("Enjoying Remote Emulator?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Hi, I'm José 👋 I build Remote Emulator in my free time and keep it free and open source. If it saves you time, a coffee helps me sign the app, keep improving it and ship more open-source tools.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button {
                    Links.open(Links.coffee)
                    model.closeSupportPrompt(never: false)
                } label: {
                    Text("☕  Buy me a coffee")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.11, green: 0.08, blue: 0))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(red: 1, green: 0.87, blue: 0)))
                }
                .buttonStyle(.plain)

                HStack {
                    Button("I already did 💜") { model.closeSupportPrompt(never: true) }
                    Spacer()
                    Button("Not now") { model.closeSupportPrompt(never: false) }
                        .keyboardShortcut(.cancelAction)
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 400)
    }
}
