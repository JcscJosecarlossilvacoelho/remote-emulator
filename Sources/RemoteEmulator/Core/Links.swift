import AppKit

enum Links {
    static let coffee = URL(string: "https://buymeacoffee.com/JcscJosecarlossilvacoelho")!
    static let repository = URL(string: "https://github.com/JcscJosecarlossilvacoelho/remote-emulator")!
    static let issues = URL(string: "https://github.com/JcscJosecarlossilvacoelho/remote-emulator/issues")!

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}
