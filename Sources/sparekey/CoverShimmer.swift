import AppKit
import QuartzCore

final class CoverShimmerLayer: CALayer {
    static let animationKey = "coverTitleShimmer"
    let gradientLayer = CAGradientLayer()

    override init() {
        super.init()
        name = "coverTitleShimmer"
        gradientLayer.colors = [NSColor.clear.cgColor,
                                NSColor.white.withAlphaComponent(0.65).cgColor,
                                NSColor.clear.cgColor]
        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        addSublayer(gradientLayer)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateGeometry(titleRect: CGRect, scale: CGFloat) {
        let wasAnimating = gradientLayer.animation(forKey: Self.animationKey) != nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = titleRect
        let textMask = CALayer()
        textMask.frame = bounds
        textMask.contentsScale = scale
        let image = NSImage(size: titleRect.size, flipped: false) { rect in
            CoverLayout.drawTitle(in: rect, color: .white)
            return true
        }
        var imageRect = CGRect(origin: .zero, size: titleRect.size)
        textMask.contents = image.cgImage(forProposedRect: &imageRect, context: nil,
                                         hints: [.ctm: AffineTransform(scale: scale)])
        mask = textMask
        gradientLayer.bounds = CGRect(x: 0, y: 0, width: titleRect.width * 0.45, height: titleRect.height)
        gradientLayer.position = CGPoint(x: -gradientLayer.bounds.width / 2, y: bounds.midY)
        CATransaction.commit()
        if wasAnimating {
            setAnimating(false)
            setAnimating(true)
        }
    }

    func setAnimating(_ animate: Bool) {
        guard animate, bounds.width > 0 else {
            gradientLayer.removeAnimation(forKey: Self.animationKey)
            isHidden = true
            return
        }
        isHidden = false
        guard gradientLayer.animation(forKey: Self.animationKey) == nil else { return }
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = -gradientLayer.bounds.width / 2
        animation.toValue = bounds.width + gradientLayer.bounds.width / 2
        animation.duration = 5.5
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        gradientLayer.add(animation, forKey: Self.animationKey)
    }
}

final class CoverArtworkView: NSView {
    let shimmerLayer = CoverShimmerLayer()
    private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(shimmerLayer)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    override func draw(_ dirtyRect: NSRect) {
        CoverLayout.drawArtwork(in: bounds, titleColor: .white.withAlphaComponent(reduceMotion ? 1 : 0.78))
    }

    override func layout() {
        super.layout()
        shimmerLayer.updateGeometry(titleRect: CoverLayout.titleFrame(in: bounds),
                                    scale: window?.backingScaleFactor ?? 2)
        updateAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
        updateAnimation()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateAnimation()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateAnimation()
    }

    func updateMotion(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        needsDisplay = true
        updateAnimation()
    }

    @objc private func accessibilityOptionsChanged() {
        updateMotion(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func updateAnimation() {
        shimmerLayer.setAnimating(!reduceMotion && window != nil && !isHiddenOrHasHiddenAncestor)
    }
}
