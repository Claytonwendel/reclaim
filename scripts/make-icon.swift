import AppKit

// Reshape a full-bleed square PNG into a proper macOS app-icon tile:
// Apple's Big Sur+ grid = an 824×824 rounded-rectangle body centered on a
// 1024×1024 transparent canvas (100px margin), corner radius 185.4.
// Usage: swift make-icon.swift <source.png> <out-1024.png>

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <src.png> <out.png>\n".utf8))
    exit(1)
}

let canvas = 1024.0
let body = 824.0
let inset = (canvas - body) / 2.0        // 100
let radius = 185.4

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bodyRect = NSRect(x: inset, y: inset, width: body, height: body)
let clip = NSBezierPath(roundedRect: bodyRect, xRadius: radius, yRadius: radius)
clip.addClip()
src.draw(in: bodyRect, from: .zero, operation: .copy, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: args[2]))
FileHandle.standardError.write(Data("wrote \(args[2])\n".utf8))
