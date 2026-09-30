import AppKit

// Draw the icon at full resolution, then supply every macOS iconset size.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let tile = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920),
    xRadius: 206, yRadius: 206)
NSColor(calibratedWhite: 0.035, alpha: 1).setFill()
tile.fill()
tile.addClip()
let gradient = NSGradient(starting: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.20, alpha: 1),
    ending: NSColor(calibratedWhite: 0.008, alpha: 1))!
gradient.draw(in: tile, angle: -90)

for index in 0..<22 {
    let phase = CGFloat(index) / 21
    let side = 600 * pow(0.925, CGFloat(index))
    let angle = CGFloat(index) * 0.115 - 0.47
    let center = NSPoint(x: 512 + 44 * sin(CGFloat(index) * 0.16),
                         y: 512 + 32 * cos(CGFloat(index) * 0.19))
    let square = NSBezierPath()
    for corner in 0..<4 {
        let x: CGFloat = (corner == 0 || corner == 3) ? -side / 2 : side / 2
        let y: CGFloat = corner < 2 ? -side / 2 : side / 2
        let point = NSPoint(x: center.x + x * cos(angle) - y * sin(angle),
                            y: center.y + x * sin(angle) + y * cos(angle))
        if corner == 0 { square.move(to: point) } else { square.line(to: point) }
    }
    square.close()
    let color = NSColor(calibratedHue: (0.53 + phase * 0.86).truncatingRemainder(dividingBy: 1),
        saturation: 0.86, brightness: 1, alpha: 1)
    NSColor(calibratedWhite: 0.015, alpha: 0.72).setFill()
    square.fill()
    square.lineJoinStyle = .round
    for spread in stride(from: 4, through: 1, by: -1) {
        color.withAlphaComponent(0.025).setStroke()
        square.lineWidth = CGFloat(spread) * 12 + 7
        square.stroke()
    }
    color.setStroke()
    square.lineWidth = 9 - phase * 3
    square.stroke()
    color.blended(withFraction: 0.35, of: .white)!.withAlphaComponent(0.65).setStroke()
    square.lineWidth = 2
    square.stroke()
}
NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: output.appendingPathComponent("icon_512x512@2x.png"))

// AppKit redraws the master into smaller bitmap representations without tools
// or dependencies beyond the macOS SDK.
let master = NSImage(size: NSSize(width: 1024, height: 1024))
master.addRepresentation(bitmap)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        if pixels == 1024 { continue }
        let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        NSGraphicsContext.current?.imageInterpolation = .high
        master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
            from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try small.representation(using: .png, properties: [:])!.write(
            to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
