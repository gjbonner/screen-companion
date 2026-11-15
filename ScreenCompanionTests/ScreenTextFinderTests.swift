import AppKit
import BuddyCore
import Testing
@testable import ScreenCompanion

/// Runs real on-device text recognition on a drawn screenshot.
struct ScreenTextFinderTests {
	/// Like GitHub's file list: LICENSE.md directly above README.md.
	private static let screen = makeScreen(lines: [
		(text: "LICENSE.md", top: 500),
		(text: "README.md", top: 560),
	])

	@Test
	func readmeIsFoundButLicenseIsNot() {
		let found = ScreenTextFinder.candidates(matching: "README.md", in: Self.screen)
		#expect(found.map(\.label) == ["README.md"])
	}

	@Test
	func readmeIsChosenEvenWhenTheGuessIsNearerLicense() throws {
		let found = ScreenTextFinder.candidates(matching: "README.md", in: Self.screen)
		let readme = try #require(found.first)
		// A guess right on LICENSE.md, as the model made on GitHub.
		let guess = try #require(CoordinateMapper(screen: Self.screen).screenPoint(forImagePoint: CGPoint(x: 160, y: 510)))
		let target = SnapGuardrails.target(guess: guess, label: "README.md", candidates: found, displayFrame: Self.screen.displayFrame)
		#expect(target == PointTarget(frame: readme.frame))
	}

	@Test
	func licenseAloneIsNotTakenForReadme() {
		let screen = Self.makeScreen(lines: [(text: "LICENSE.md", top: 500)])
		#expect(ScreenTextFinder.candidates(matching: "README.md", in: screen).isEmpty)
	}

	@Test
	func matchIsBoxedWhereTheTextIs() throws {
		let readme = try #require(ScreenTextFinder.candidates(matching: "README.md", in: Self.screen).first)
		// Drawn at image y 560–590 on a 1600×900 capture of a 1920×1080 display: screen y 372–408.
		#expect(readme.frame.minY > 360 && readme.frame.maxY < 420)
		#expect(readme.frame.minX > 100 && readme.frame.minX < 140)
	}

	/// A white 1600×900 JPEG with each line of text drawn at x = 100, `top` pixels from the top, captured from a 1920×1080 display.
	private static func makeScreen(lines: [(text: String, top: CGFloat)]) -> CapturedScreen {
		let size = CGSize(width: 1600, height: 900)
		let image = NSImage(size: size, flipped: true) { rect in
			NSColor.white.setFill()
			rect.fill()
			for line in lines {
				(line.text as NSString).draw(at: CGPoint(x: 100, y: line.top), withAttributes: [
					.font: NSFont.systemFont(ofSize: 24),
					.foregroundColor: NSColor.black,
				])
			}
			return true
		}
		let bitmap = NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int(size.width),
			pixelsHigh: Int(size.height),
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		)!
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
		image.draw(in: CGRect(origin: .zero, size: size))
		NSGraphicsContext.restoreGraphicsState()
		let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
		return CapturedScreen(imageData: jpeg, imagePixelSize: size, displayFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
	}
}
