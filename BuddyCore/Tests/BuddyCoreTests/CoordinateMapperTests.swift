import CoreGraphics
import Foundation
import Testing
@testable import BuddyCore

struct CoordinateMapperTests {
	// MARK: - Image pixels to screen points

	@Test
	func retinaLaptopMapsCornersAndCenter() {
		// A 14" MacBook Pro: 1512×982 points at 2×, captured at 1600×1039 pixels.
		let mapper = Self.mapper(image: CGSize(width: 1600, height: 1039), display: CGRect(x: 0, y: 0, width: 1512, height: 982))

		// Image origin is top-left; AppKit's is bottom-left, so the image's top-left is the display's maxY.
		Self.expect(mapper.screenPoint(forImagePoint: CGPoint(x: 0, y: 0)), CGPoint(x: 0, y: 982))
		Self.expect(mapper.screenPoint(forImagePoint: CGPoint(x: 1600, y: 1039)), CGPoint(x: 1512, y: 0))
		Self.expect(mapper.screenPoint(forImagePoint: CGPoint(x: 800, y: 519.5)), CGPoint(x: 756, y: 491))
	}

	@Test
	func nonRetinaMonitorDownscaledImageMapsBackToFullSize() {
		// A 1920×1080 monitor at 1×, captured at 1600×900.
		let mapper = Self.mapper(image: CGSize(width: 1600, height: 900), display: CGRect(x: 0, y: 0, width: 1920, height: 1080))

		Self.expect(mapper.screenPoint(forImagePoint: CGPoint(x: 400, y: 300)), CGPoint(x: 480, y: 720))
	}

	@Test
	func imageNotDownscaledMapsOneToOne() {
		let mapper = Self.mapper(image: CGSize(width: 1280, height: 800), display: CGRect(x: 0, y: 0, width: 1280, height: 800))

		Self.expect(mapper.screenPoint(forImagePoint: CGPoint(x: 100, y: 50)), CGPoint(x: 100, y: 750))
	}

	@Test
	func secondaryDisplayToTheRightIsOffset() {
		// A 2560×1440 monitor to the right of a 1512×982 laptop, top edges aligned.
		let display = CGRect(x: 1512, y: -458, width: 2560, height: 1440)
		let mapper = Self.mapper(image: CGSize(width: 1600, height: 900), display: display)

		Self.expect(mapper.screenPoint(forImagePoint: CGPoint(x: 0, y: 0)), CGPoint(x: 1512, y: 982))
		Self.expect(mapper.screenPoint(forImagePoint: CGPoint(x: 800, y: 450)), CGPoint(x: 1512 + 1280, y: -458 + 720))
	}

	@Test
	func displayWithNegativeOriginToTheLeftAndBelow() {
		let display = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
		let mapper = Self.mapper(image: CGSize(width: 1600, height: 900), display: display)

		Self.expect(mapper.screenPoint(forImagePoint: CGPoint(x: 0, y: 900)), CGPoint(x: -1920, y: -1080))
		Self.expect(mapper.screenPoint(forImagePoint: CGPoint(x: 1600, y: 0)), CGPoint(x: 0, y: 0))
	}

	@Test(arguments: [
		CGPoint(x: -1, y: 10),
		CGPoint(x: 10, y: -1),
		CGPoint(x: 1601, y: 10),
		CGPoint(x: 10, y: 901),
		CGPoint(x: 3200, y: 1800),
	])
	func guessOutsideTheImageGivesNoPoint(_ guess: CGPoint) {
		let mapper = Self.mapper(image: CGSize(width: 1600, height: 900), display: CGRect(x: 0, y: 0, width: 1920, height: 1080))

		#expect(mapper.screenPoint(forImagePoint: guess) == nil)
	}

	@Test
	func emptyImageGivesNoPoint() {
		let mapper = Self.mapper(image: .zero, display: CGRect(x: 0, y: 0, width: 1920, height: 1080))

		#expect(mapper.screenPoint(forImagePoint: .zero) == nil)
	}

	@Test
	func builtFromACapturedScreen() {
		let screen = CapturedScreen(
			imageData: Data(),
			imagePixelSize: CGSize(width: 1600, height: 900),
			displayFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
		)

		Self.expect(CoordinateMapper(screen: screen).screenPoint(forImagePoint: CGPoint(x: 400, y: 300)), CGPoint(x: 480, y: 720))
	}

	// MARK: - AppKit and Accessibility coordinates

	@Test
	func accessibilityPointFlipsAroundThePrimaryDisplay() {
		// Accessibility's origin is the primary display's top-left, with y growing down.
		let point = CoordinateMapper.accessibilityPoint(fromScreenPoint: CGPoint(x: 100, y: 900), primaryDisplayHeight: 982)
		#expect(point == CGPoint(x: 100, y: 82))
	}

	@Test
	func accessibilityPointOnADisplayBelowThePrimaryIsBeyondItsHeight() {
		let point = CoordinateMapper.accessibilityPoint(fromScreenPoint: CGPoint(x: -500, y: -200), primaryDisplayHeight: 982)
		#expect(point == CGPoint(x: -500, y: 1182))
	}

	@Test
	func accessibilityFrameConvertsToAScreenRect() {
		// A 200×40 button whose top-left is 100 points from the top of a 982-point-tall primary display.
		let rect = CoordinateMapper.screenRect(
			fromAccessibilityRect: CGRect(x: 50, y: 100, width: 200, height: 40),
			primaryDisplayHeight: 982
		)
		#expect(rect == CGRect(x: 50, y: 842, width: 200, height: 40))
	}

	@Test
	func screenPointRoundTripsThroughAccessibility() {
		let original = CGPoint(x: 2000, y: -300)
		let accessibility = CoordinateMapper.accessibilityPoint(fromScreenPoint: original, primaryDisplayHeight: 1117)
		let back = CoordinateMapper.accessibilityPoint(fromScreenPoint: accessibility, primaryDisplayHeight: 1117)
		#expect(back == original)
	}

	// MARK: - Helpers

	private static func mapper(image: CGSize, display: CGRect) -> CoordinateMapper {
		CoordinateMapper(imagePixelSize: image, displayFrame: display)
	}

	private static func expect(
		_ actual: CGPoint?,
		_ expected: CGPoint,
		sourceLocation: SourceLocation = #_sourceLocation
	) {
		guard let actual else {
			Issue.record("Expected \(expected), got nil", sourceLocation: sourceLocation)
			return
		}
		#expect(abs(actual.x - expected.x) < 0.01 && abs(actual.y - expected.y) < 0.01, "Expected \(expected), got \(actual)", sourceLocation: sourceLocation)
	}
}
