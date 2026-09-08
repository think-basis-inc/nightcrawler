import AppKit

// A vector-drawn crescent/radar mark, rasterized at each native macOS size.
// Rebuild with: swift scripts/make-icon.swift && iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
let output = URL(fileURLWithPath: ".build/AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()

    let tile = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 204, yRadius: 204)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(calibratedRed: 0.035, green: 0.08, blue: 0.09, alpha: 1),
                        NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.20, alpha: 1)])!
        .draw(in: tile, angle: 90)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    // The open arc is both a moon and the app's usage ring.
    let moon = NSBezierPath()
    moon.move(to: NSPoint(x: 718, y: 726))
    moon.curve(to: NSPoint(x: 314, y: 706), controlPoint1: NSPoint(x: 580, y: 870), controlPoint2: NSPoint(x: 406, y: 828))
    moon.curve(to: NSPoint(x: 312, y: 330), controlPoint1: NSPoint(x: 200, y: 572), controlPoint2: NSPoint(x: 214, y: 438))
    moon.curve(to: NSPoint(x: 730, y: 342), controlPoint1: NSPoint(x: 432, y: 190), controlPoint2: NSPoint(x: 640, y: 212))
    moon.curve(to: NSPoint(x: 420, y: 396), controlPoint1: NSPoint(x: 592, y: 298), controlPoint2: NSPoint(x: 474, y: 320))
    moon.curve(to: NSPoint(x: 442, y: 676), controlPoint1: NSPoint(x: 346, y: 474), controlPoint2: NSPoint(x: 348, y: 598))
    moon.curve(to: NSPoint(x: 718, y: 726), controlPoint1: NSPoint(x: 506, y: 740), controlPoint2: NSPoint(x: 610, y: 758))
    moon.close()
    NSGradient(colors: [NSColor(calibratedRed: 0.02, green: 0.80, blue: 0.57, alpha: 1),
                        NSColor(calibratedRed: 0.55, green: 1, blue: 0.80, alpha: 1)])!
        .draw(in: moon, angle: 90)

    let signal = NSBezierPath()
    signal.move(to: NSPoint(x: 506, y: 496))
    signal.line(to: NSPoint(x: 595, y: 496))
    signal.line(to: NSPoint(x: 632, y: 567))
    signal.line(to: NSPoint(x: 678, y: 456))
    signal.line(to: NSPoint(x: 712, y: 508))
    signal.line(to: NSPoint(x: 778, y: 508))
    signal.lineWidth = 25
    signal.lineJoinStyle = .round
    signal.lineCapStyle = .round
    NSColor(calibratedRed: 0.84, green: 1, blue: 0.94, alpha: 1).setStroke()
    signal.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try drawIcon(size * scale).write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
