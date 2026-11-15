import CoreGraphics
import Testing
@testable import BuddyCore

struct CaptureSizeTests {
	@Test
	func fourKDisplayIsCappedAtTheMaximumKeepingItsShape() {
		// A 3840×2160 display at 1× (as on this Mac's external monitor).
		let size = CaptureSize.pixelSize(displaySize: CGSize(width: 3840, height: 2160), backingScale: 1)
		#expect(size == CGSize(width: 1600, height: 900))
	}

	@Test
	func retinaLaptopIsCappedAtTheMaximum() {
		// A 14" MacBook Pro: 1512×982 points at 2× is 3024×1964 pixels.
		let size = CaptureSize.pixelSize(displaySize: CGSize(width: 1512, height: 982), backingScale: 2)
		#expect(size.width == 1600)
		#expect(size.height == (982.0 * 1600 / 1512).rounded())
	}

	@Test
	func fullHDMonitorIsCappedAtTheMaximum() {
		let size = CaptureSize.pixelSize(displaySize: CGSize(width: 1920, height: 1080), backingScale: 1)
		#expect(size == CGSize(width: 1600, height: 900))
	}

	@Test
	func portraitMonitorCapsTheHeight() {
		let size = CaptureSize.pixelSize(displaySize: CGSize(width: 1080, height: 1920), backingScale: 1)
		#expect(size == CGSize(width: 900, height: 1600))
	}

	@Test
	func smallDisplayIsNeverEnlarged() {
		let size = CaptureSize.pixelSize(displaySize: CGSize(width: 1280, height: 800), backingScale: 1)
		#expect(size == CGSize(width: 1280, height: 800))
	}

	@Test(arguments: [
		CGSize(width: 3840, height: 2160),
		CGSize(width: 1512, height: 982),
		CGSize(width: 2560, height: 1080),
		CGSize(width: 1080, height: 1920),
	])
	func shapeIsAlwaysPreserved(_ display: CGSize) {
		let size = CaptureSize.pixelSize(displaySize: display, backingScale: 2)
		let displayRatio = display.width / display.height
		let imageRatio = size.width / size.height
		#expect(abs(displayRatio - imageRatio) < 0.01)
		#expect(max(size.width, size.height) <= CaptureSize.maxLongEdge)
	}

	@Test
	func emptyDisplayGivesZero() {
		#expect(CaptureSize.pixelSize(displaySize: .zero, backingScale: 2) == .zero)
	}
}
