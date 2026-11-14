import AppKit
import Foundation

// Native, reproducible raster exports of the vector shelf mark. No network or packages.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let destination = root.appendingPathComponent("Resources/IconPreviews")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for mode in ["dark", "light", "clear-dark", "clear-light"] {
    let light = mode.hasSuffix("light")
    let bg = light ? NSColor.white : NSColor(srgbRed: 24/255, green: 24/255, blue: 24/255, alpha: 1)
    let fg = light ? NSColor.black : NSColor.white
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    bg.withAlphaComponent(mode.hasPrefix("clear") ? 0.72 : 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 192, yRadius: 192).fill()
    let transform = NSAffineTransform(); transform.translateX(by: 128, yBy: 128); transform.scale(by: 12); transform.concat()
    fg.setFill()
    for x in [10, 26, 42] {
        NSBezierPath(roundedRect: NSRect(x: x, y: 20, width: 12, height: 32), xRadius: 4, yRadius: 4).fill()
    }
    NSBezierPath(roundedRect: NSRect(x: 6, y: 10, width: 52, height: 4), xRadius: 2, yRadius: 2).fill()
    bg.setFill()
    for x in [10, 26, 42] {
        NSBezierPath(ovalIn: NSRect(x: x+3, y: 38, width: 6, height: 6)).fill()
        NSBezierPath(roundedRect: NSRect(x: x+3, y: 31, width: 6, height: 2), xRadius: 1, yRadius: 1).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(mode + ".png"))
}
print("Rendered four Profile Shelf icon appearances.")
