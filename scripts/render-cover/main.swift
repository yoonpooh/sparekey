import AppKit

guard CommandLine.arguments.count == 4,
      let width = Int(CommandLine.arguments[1]), let height = Int(CommandLine.arguments[2]),
      width > 0, height > 0 else {
    fputs("Usage: render-cover WIDTH HEIGHT OUTPUT.png\n", stderr)
    exit(2)
}
let output = CommandLine.arguments[3]
_ = NSApplication.shared
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let bounds = NSRect(x: 0, y: 0, width: width, height: height)
CoverLayout.drawArtwork(in: bounds)
let button = CoverLayout.buttonFrame(in: bounds)
context.cgContext.saveGState()
context.cgContext.translateBy(x: button.minX, y: button.minY)
CoverLayout.drawButton(in: NSRect(origin: .zero, size: button.size), highlighted: false)
context.cgContext.restoreGState()
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: output))
print(output)
