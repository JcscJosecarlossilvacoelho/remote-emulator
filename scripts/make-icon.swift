// Renders the app icon (1024×1024 PNG): a phone with signal waves on the brand gradient.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "icon.png"
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS icon grid: 824pt rounded square centered on a 1024 canvas.
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// josecoelho.dev palette: forest green with a soft leaf glow.
NSGradient(colors: [
    NSColor(red: 0.12, green: 0.35, blue: 0.23, alpha: 1),
    NSColor(red: 0.055, green: 0.17, blue: 0.11, alpha: 1),
])!.draw(in: shape, angle: -60)
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor(red: 0.25, green: 0.75, blue: 0.48, alpha: 0.55), NSColor(red: 0.25, green: 0.75, blue: 0.48, alpha: 0)])!
    .draw(fromCenter: NSPoint(x: size / 2, y: size * 0.55), radius: 0, toCenter: NSPoint(x: size / 2, y: size * 0.55), radius: 380, options: [])
NSGraphicsContext.restoreGraphicsState()

// Soft highlight on the top half.
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.08), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()

let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
    .applying(.init(paletteColors: [NSColor(red: 0.94, green: 0.91, blue: 0.87, alpha: 1)]))
if let symbol = NSImage(systemSymbolName: "iphone.radiowaves.left.and.right", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("icon → \(output)")
