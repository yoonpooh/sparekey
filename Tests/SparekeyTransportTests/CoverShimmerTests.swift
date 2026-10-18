import AppKit
import QuartzCore
import XCTest
@testable import sparekey

final class CoverShimmerTests: XCTestCase {
    @MainActor
    func testSweepRemainsSizedToTextOnWideDisplays() async {
        let small = CoverLayout.titleFrame(in: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let wide = CoverLayout.titleFrame(in: CGRect(x: 0, y: 0, width: 3840, height: 2160))
        XCTAssertEqual(small.width, wide.width)
        XCTAssertEqual(small.midX, 720)
        XCTAssertEqual(wide.midX, 1920)
    }

    @MainActor
    func testHighlightTravelsAcrossEntireTitleAndStopsWithoutResidualHighlight() async throws {
        let shimmer = CoverShimmerLayer()
        shimmer.updateGeometry(titleRect: CGRect(x: 20, y: 50, width: 600, height: 32), scale: 2)
        shimmer.setAnimating(true)
        let animation = try XCTUnwrap(shimmer.gradientLayer.animation(forKey: CoverShimmerLayer.animationKey) as? CABasicAnimation)
        let start = try XCTUnwrap(animation.fromValue as? NSNumber).doubleValue
        let end = try XCTUnwrap(animation.toValue as? NSNumber).doubleValue
        XCTAssertLessThan(start, 0)
        XCTAssertGreaterThan(end, 600)
        XCTAssertGreaterThanOrEqual(animation.duration, 4)
        XCTAssertEqual(animation.repeatCount, .infinity)
        XCTAssertFalse(shimmer.isHidden)
        shimmer.setAnimating(false)
        XCTAssertNil(shimmer.gradientLayer.animationKeys())
        XCTAssertTrue(shimmer.isHidden)
    }

    @MainActor
    func testReduceMotionImmediatelyRemovesRunningAnimationAndStaysStaticAfterLayout() async {
        let view = CoverArtworkView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.layout()
        view.shimmerLayer.setAnimating(true)
        XCTAssertNotNil(view.shimmerLayer.gradientLayer.animationKeys())
        view.updateMotion(reduceMotion: true)
        XCTAssertTrue(view.reduceMotion)
        XCTAssertNil(view.shimmerLayer.gradientLayer.animationKeys())
        XCTAssertTrue(view.shimmerLayer.isHidden)
        view.frame.size = CGSize(width: 1200, height: 800)
        view.layout()
        XCTAssertEqual(view.shimmerLayer.frame, CoverLayout.titleFrame(in: view.bounds))
        XCTAssertNil(view.shimmerLayer.gradientLayer.animationKeys())
        XCTAssertTrue(view.shimmerLayer.isHidden)
    }

    @MainActor
    func testDetachedViewDoesNotStartAnimationWhenMotionIsEnabled() async {
        let view = CoverArtworkView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.updateMotion(reduceMotion: false)
        view.layout()
        XCTAssertNil(view.shimmerLayer.gradientLayer.animationKeys())
        XCTAssertTrue(view.shimmerLayer.isHidden)
    }

    @MainActor
    func testAccessibilityNotificationRefreshesCurrentPreference() async {
        let view = CoverArtworkView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let currentPreference = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        view.updateMotion(reduceMotion: !currentPreference)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        XCTAssertEqual(view.reduceMotion, currentPreference)
    }

    @MainActor
    func testHiddenViewRemovesRunningAnimation() async {
        let view = CoverArtworkView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.layout()
        view.shimmerLayer.setAnimating(true)
        view.isHidden = true
        XCTAssertNil(view.shimmerLayer.gradientLayer.animationKeys())
        XCTAssertTrue(view.shimmerLayer.isHidden)
    }

    @MainActor
    func testResizeUpdatesMaskAndSweepWithoutAccumulatingAnimations() async throws {
        let shimmer = CoverShimmerLayer()
        shimmer.updateGeometry(titleRect: CGRect(x: 20, y: 50, width: 600, height: 32), scale: 2)
        shimmer.setAnimating(true)
        shimmer.setAnimating(true)
        shimmer.updateGeometry(titleRect: CGRect(x: 20, y: 80, width: 1000, height: 32), scale: 2)
        XCTAssertEqual(shimmer.mask?.frame, shimmer.bounds)
        XCTAssertNotNil(shimmer.mask?.contents)
        XCTAssertEqual(shimmer.gradientLayer.animationKeys()?.count, 1)
        let animation = try XCTUnwrap(shimmer.gradientLayer.animation(forKey: CoverShimmerLayer.animationKey) as? CABasicAnimation)
        XCTAssertGreaterThan(try XCTUnwrap(animation.toValue as? NSNumber).doubleValue, 1000)
    }
}
