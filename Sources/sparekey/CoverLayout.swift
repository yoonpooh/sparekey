import AppKit

enum CoverLayout {
    static let buttonSize = NSSize(width: 154, height: 44)
    static let logoSize = NSSize(width: 144, height: 73)

    static func buttonFrame(in frame: NSRect) -> NSRect {
        let groupHeight: CGFloat = logoSize.height + 32 + 32 + 10 + 20 + 40 + buttonSize.height
        let bottom = frame.midY - groupHeight / 2 + 30
        return NSRect(x: frame.midX - buttonSize.width / 2, y: bottom,
                      width: buttonSize.width, height: buttonSize.height)
    }

    static func drawArtwork(in bounds: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        let button = buttonFrame(in: bounds)
        let subtitleY = button.maxY + 40
        let titleY = subtitleY + 20 + 10
        let logo = NSRect(x: bounds.midX - logoSize.width / 2, y: titleY + 32 + 32, width: logoSize.width, height: logoSize.height)
        EmbeddedLogo.image.draw(in: logo, from: .zero, operation: .sourceOver, fraction: 1)
        drawText("Your agent is using this Mac", in: NSRect(x: 20, y: titleY, width: bounds.width - 40, height: 32),
                 font: .systemFont(ofSize: 26, weight: .semibold), color: .white)
        drawText("The screen is hidden while it works.", in: NSRect(x: 20, y: subtitleY, width: bounds.width - 40, height: 20),
                 font: .systemFont(ofSize: 15), color: NSColor.white.withAlphaComponent(0.55))
    }

    private static func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    static func drawButton(in bounds: NSRect, highlighted: Bool) {
        NSColor.white.withAlphaComponent(highlighted ? 0.22 : 0.14).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        let text = "Lock Mac" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attributes)
        let symbolSize: CGFloat = 17
        let gap: CGFloat = 9
        let x = (bounds.width - symbolSize - gap - textSize.width) / 2
        let symbol = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Lock")?
            .withSymbolConfiguration(.init(pointSize: symbolSize, weight: .medium))?
            .withSymbolConfiguration(.init(paletteColors: [.white]))
        symbol?.draw(in: NSRect(x: x, y: (bounds.height - symbolSize) / 2, width: symbolSize, height: symbolSize),
                     from: .zero, operation: .sourceOver, fraction: 1)
        text.draw(at: NSPoint(x: x + symbolSize + gap, y: (bounds.height - textSize.height) / 2), withAttributes: attributes)
    }
}

final class CoverArtworkView: NSView {
    override func draw(_ dirtyRect: NSRect) { CoverLayout.drawArtwork(in: bounds) }
}

final class CoverLockButtonView: NSView {
    var action: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) { CoverLayout.drawButton(in: bounds, highlighted: hovering || pressing) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false; pressing = false }
    override func mouseDown(with event: NSEvent) { pressing = true; action?() }
    override func mouseUp(with event: NSEvent) { pressing = false }
}
