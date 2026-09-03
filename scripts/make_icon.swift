import AppKit

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Paxo/Assets.xcassets/AppIcon.appiconset"

let sizes: [(name: String, px: Int)] = [
    ("icon_16", 16), ("icon_16@2x", 32),
    ("icon_32", 32), ("icon_32@2x", 64),
    ("icon_128", 128), ("icon_128@2x", 256),
    ("icon_256", 256), ("icon_256@2x", 512),
    ("icon_512", 512), ("icon_512@2x", 1024),
]

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let s = CGFloat(px) / 1024.0

    // 배경 스쿼클 (macOS 아이콘 그리드: 1024 캔버스에 824 사각형, 반경 185)
    let bgRect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 185 * s, yRadius: 185 * s)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.36, green: 0.53, blue: 0.98, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.13, green: 0.22, blue: 0.75, alpha: 1.0)
    )!
    gradient.draw(in: bgPath, angle: 270)

    NSColor.white.setStroke()
    let bracket = NSBezierPath()
    bracket.lineWidth = 58 * s
    bracket.lineCapStyle = .round
    bracket.lineJoinStyle = .round

    let left: CGFloat = 270 * s
    let right: CGFloat = 754 * s
    let bottom: CGFloat = 270 * s
    let top: CGFloat = 754 * s
    let arm: CGFloat = 130 * s

    bracket.move(to: NSPoint(x: left, y: top - arm))
    bracket.line(to: NSPoint(x: left, y: top))
    bracket.line(to: NSPoint(x: left + arm, y: top))
    bracket.move(to: NSPoint(x: right - arm, y: top))
    bracket.line(to: NSPoint(x: right, y: top))
    bracket.line(to: NSPoint(x: right, y: top - arm))
    bracket.move(to: NSPoint(x: left, y: bottom + arm))
    bracket.line(to: NSPoint(x: left, y: bottom))
    bracket.line(to: NSPoint(x: left + arm, y: bottom))
    bracket.move(to: NSPoint(x: right - arm, y: bottom))
    bracket.line(to: NSPoint(x: right, y: bottom))
    bracket.line(to: NSPoint(x: right, y: bottom + arm))
    bracket.stroke()

    let lines = NSBezierPath()
    lines.lineWidth = 58 * s
    lines.lineCapStyle = .round
    lines.move(to: NSPoint(x: 380 * s, y: 582 * s))
    lines.line(to: NSPoint(x: 644 * s, y: 582 * s))
    lines.move(to: NSPoint(x: 380 * s, y: 512 * s))
    lines.line(to: NSPoint(x: 560 * s, y: 512 * s))
    lines.move(to: NSPoint(x: 380 * s, y: 442 * s))
    lines.line(to: NSPoint(x: 610 * s, y: 442 * s))
    lines.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(
    atPath: outputDir, withIntermediateDirectories: true
)
for (name, px) in sizes {
    let data = render(px: px)
    let path = "\(outputDir)/\(name).png"
    try data.write(to: URL(fileURLWithPath: path))
    print("✓ \(name).png (\(px)px)")
}
print("done")
