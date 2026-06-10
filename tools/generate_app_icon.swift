import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift generate_app_icon.swift <output-path>\n", stderr)
    exit(EXIT_FAILURE)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("failed to create image context\n", stderr)
    exit(EXIT_FAILURE)
}

bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let canvas = NSRect(origin: .zero, size: size)
let backgroundRect = canvas.insetBy(dx: 72, dy: 72)
let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 220, yRadius: 220)

context.cgContext.saveGState()
context.cgContext.setShadow(
    offset: CGSize(width: 0, height: -24),
    blur: 48,
    color: NSColor.black.withAlphaComponent(0.28).cgColor
)
NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.58, alpha: 1).setFill()
backgroundPath.fill()
context.cgContext.restoreGState()

context.cgContext.saveGState()
backgroundPath.addClip()
let gradient = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 0.19, green: 0.38, blue: 0.96, alpha: 1), 0),
    (NSColor(calibratedRed: 0.38, green: 0.23, blue: 0.86, alpha: 1), 0.52),
    (NSColor(calibratedRed: 0.11, green: 0.70, blue: 0.73, alpha: 1), 1)
)!
gradient.draw(in: backgroundPath, angle: 305)
context.cgContext.restoreGState()

let glowPath = NSBezierPath(ovalIn: NSRect(x: 130, y: 510, width: 720, height: 390))
NSColor.white.withAlphaComponent(0.10).setFill()
glowPath.fill()

guard let symbol = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil) else {
    fputs("speaker.wave.2.fill symbol is unavailable\n", stderr)
    exit(EXIT_FAILURE)
}
let configuredSymbol = symbol.withSymbolConfiguration(
    NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
) ?? symbol
configuredSymbol.draw(
    in: NSRect(x: 224, y: 255, width: 576, height: 576),
    from: .zero,
    operation: .sourceOver,
    fraction: 0.96,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)

let badgeRect = NSRect(x: 650, y: 165, width: 220, height: 220)
let badgePath = NSBezierPath(ovalIn: badgeRect)
context.cgContext.saveGState()
context.cgContext.setShadow(
    offset: CGSize(width: 0, height: -10),
    blur: 22,
    color: NSColor.black.withAlphaComponent(0.24).cgColor
)
NSColor(calibratedRed: 0.08, green: 0.76, blue: 0.60, alpha: 1).setFill()
badgePath.fill()
context.cgContext.restoreGState()

if let arrows = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil) {
    let configuredArrows = arrows.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 112, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    ) ?? arrows
    configuredArrows.draw(
        in: badgeRect.insetBy(dx: 46, dy: 46),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to encode app icon\n", stderr)
    exit(EXIT_FAILURE)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL)
