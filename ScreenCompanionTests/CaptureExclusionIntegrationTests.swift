import AppKit
import BuddyCore
import ScreenCaptureKit
import Testing
@testable import ScreenCompanion

/// Opt-in: uses the real screen and takes it over briefly. Needs Screen Recording granted to ScreenCompanion.
///
/// Run with:
/// `TEST_RUNNER_BUDDY_INTEGRATION=1 xcodebuild test -project ScreenCompanion.xcodeproj -scheme ScreenCompanion -destination 'platform=macOS'`
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BUDDY_INTEGRATION"] == "1"))
struct CaptureExclusionIntegrationTests {
	@Test
	func buddysOwnWindowsAreLeftOutOfTheCapture() async throws {
		try #require(CGPreflightScreenCaptureAccess(), "Grant Screen Recording to ScreenCompanion first.")

		// A solid magenta Buddy panel in the middle of the display under the cursor.
		let screen = try #require(NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)
		let size = NSSize(width: 300, height: 200)
		let panel = PillPanel(size: size)
		panel.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
		panel.setFrame(
			NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2, width: size.width, height: size.height),
			display: true
		)
		panel.orderFrontRegardless()
		defer {
			panel.orderOut(nil)
		}
		try await Task.sleep(for: .milliseconds(400))

		// Control: without exclusion, the panel must show up, or the test proves nothing.
		#expect(try await centerIsMagenta(inCaptureOf: screen, excludingBuddy: false), "The test panel wasn't visible on screen.")

		// The real capturer must leave it out.
		let captured = try await ScreenCaptureKitCapturer().captureDisplayUnderCursor()
		let image = try #require(NSBitmapImageRep(data: captured.imageData))
		let center = try #require(image.colorAt(x: image.pixelsWide / 2, y: image.pixelsHigh / 2)?.usingColorSpace(.sRGB))
		#expect(!Self.isMagenta(center), "Buddy's own window appeared in the capture sent to the model.")
	}

	private func centerIsMagenta(inCaptureOf screen: NSScreen, excludingBuddy: Bool) async throws -> Bool {
		let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
		let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
		let display = try #require(content.displays.first { $0.displayID == number.uint32Value })
		let filter = SCContentFilter(display: display, excludingWindows: [])
		let configuration = SCStreamConfiguration()
		configuration.width = Int(screen.frame.width)
		configuration.height = Int(screen.frame.height)
		let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
		let bitmap = NSBitmapImageRep(cgImage: image)
		let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
		return Self.isMagenta(center)
	}

	private static func isMagenta(_ color: NSColor) -> Bool {
		color.redComponent > 0.85 && color.greenComponent < 0.25 && color.blueComponent > 0.85
	}
}
