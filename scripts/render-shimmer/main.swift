import AppKit
import QuartzCore

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "/tmp/sparekey-shimmer-evidence"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let bounds = NSRect(x: 0, y: 0, width: 1440, height: 900)
_ = NSApplication.shared
let view = CoverArtworkView(frame: bounds)
view.updateMotion(reduceMotion: false)
view.needsLayout = true
view.layoutSubtreeIfNeeded()
view.displayIfNeeded()
let shimmer = view.shimmerLayer
shimmer.setAnimating(true)
guard let animation = shimmer.gradientLayer.animation(forKey: CoverShimmerLayer.animationKey) as? CABasicAnimation,
      let start = animation.fromValue as? NSNumber,
      let end = animation.toValue as? NSNumber else {
    fatalError("Expected the production shimmer position animation")
}
let duration = animation.duration
shimmer.gradientLayer.removeAllAnimations()

func render(_ name: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width),
                                 pixelsHigh: Int(bounds.height), bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    // AppKit's offscreen draw supplies the same artwork; CALayer.render does not sample animations.
    view.draw(bounds)
    context.cgContext.saveGState()
    context.cgContext.translateBy(x: shimmer.frame.minX, y: shimmer.frame.minY)
    shimmer.render(in: context.cgContext)
    context.cgContext.restoreGState()
    let button = CoverLayout.buttonFrame(in: bounds)
    context.cgContext.saveGState()
    context.cgContext.translateBy(x: button.minX, y: button.minY)
    CoverLayout.drawButton(in: NSRect(origin: .zero, size: button.size), highlighted: false)
    context.cgContext.restoreGState()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(
        to: URL(fileURLWithPath: output).appendingPathComponent(name))
}

if CommandLine.arguments.contains("--video") {
    precondition(animation.keyPath == "position.x"
                 && animation.timingFunction == CAMediaTimingFunction(name: .linear)
                 && !animation.autoreverses && animation.speed == 1)
    let fps = 30
    let seconds = 12
    try FileManager.default.createDirectory(atPath: output + "/frames", withIntermediateDirectories: true)
    for frame in 0..<(fps * seconds) {
        try autoreleasepool {
            let time = Double(frame) / Double(fps)
            let phase = time.truncatingRemainder(dividingBy: duration) / duration
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shimmer.gradientLayer.position.x = start.doubleValue + (end.doubleValue - start.doubleValue) * phase
            CATransaction.commit()
            try render(String(format: "frames/frame-%04d.png", frame))
        }
    }
    let note = "Offscreen CoverArtworkView, 360 frames at 30fps, 12 seconds. Production linear position.x endpoints sampled at t modulo \(duration) seconds. Two complete cycles end at 11 seconds. No window, capture, lock/unlock, or helper operations.\n"
    try note.write(toFile: output + "/video-render-notes.txt", atomically: true, encoding: .utf8)
    print(note)
    exit(0)
}

for (index, phase) in [0.3, 0.5, 0.7].enumerated() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shimmer.gradientLayer.position.x = start.doubleValue + (end.doubleValue - start.doubleValue) * phase
    CATransaction.commit()
    try render("shimmer-\(index + 1).png")
}
view.updateMotion(reduceMotion: true)
try render("reduce-motion.png")
try render("reduce-motion-repeat.png")
let note = """
Offscreen samples of CoverArtworkView and its production CoverShimmerLayer.
No window was shown. No screen capture, lock/unlock, or helper operation was performed.
Frames sample the production CABasicAnimation endpoints at 30%, 50%, and 70% of its \(duration)-second cycle.
CALayer.render does not advance animations; only the evidence renderer samples model positions.
Reduce Motion is simulated via the same setAnimating(false) path used by the view.
The repeated static frame allows byte/pixel equality verification.
"""
try note.write(toFile: output + "/render-notes.txt", atomically: true, encoding: .utf8)
print(note)
