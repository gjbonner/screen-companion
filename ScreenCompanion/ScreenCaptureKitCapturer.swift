import AppKit
import BuddyCore
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Takes one screenshot of the display under the mouse cursor, leaving out every Buddy window (ADR 0003).
/// The window server re-composites the screen without Buddy, so whatever is underneath is fully visible.
/// The image size comes from `CaptureSize` (in BuddyCore, unit-tested).
struct ScreenCaptureKitCapturer: ScreenCapturer {
	static let jpegQuality: CGFloat = 0.8

	func captureDisplayUnderCursor() async throws -> CapturedScreen {
		guard CGPreflightScreenCaptureAccess() else {
			// Shows macOS's prompt the first time; the grant only takes effect after Buddy relaunches.
			CGRequestScreenCaptureAccess()
			throw BuddyError(BuddyCoordinator.screenRecordingMessage)
		}

		let target = await MainActor.run {
			Self.displayUnderCursor()
		}
		guard let target else {
			throw BuddyError("Couldn't find a display to capture.")
		}

		do {
			let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
			guard let display = content.displays.first(where: { $0.displayID == target.displayID }) else {
				throw BuddyError("Couldn't find a display to capture.")
			}
			let processID = ProcessInfo.processInfo.processIdentifier
			let buddy = content.applications.filter { $0.processID == processID }
			let filter = SCContentFilter(display: display, excludingApplications: buddy, exceptingWindows: [])

			let pixelSize = CaptureSize.pixelSize(displaySize: target.frame.size, backingScale: target.backingScale)
			let configuration = SCStreamConfiguration()
			configuration.width = Int(pixelSize.width)
			configuration.height = Int(pixelSize.height)
			configuration.showsCursor = false

			let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
			let data = try Self.jpeg(from: image)
			Log.capture.info("Captured \(image.width, privacy: .public)×\(image.height, privacy: .public) (\(data.count, privacy: .public) bytes)")
			return CapturedScreen(
				imageData: data,
				imagePixelSize: CGSize(width: image.width, height: image.height),
				displayFrame: target.frame
			)
		} catch let error as BuddyError {
			throw error
		} catch is CancellationError {
			throw CancellationError()
		} catch {
			Log.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
			throw BuddyError("Couldn't capture the screen. Try again.")
		}
	}

	private struct Target: Sendable {
		var displayID: CGDirectDisplayID
		/// The display's frame in AppKit global coordinates (points, origin bottom-left of the main display).
		var frame: CGRect
		var backingScale: CGFloat
	}

	@MainActor
	private static func displayUnderCursor() -> Target? {
		let mouse = NSEvent.mouseLocation
		guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main,
			let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
			return nil
		}
		return Target(displayID: number.uint32Value, frame: screen.frame, backingScale: screen.backingScaleFactor)
	}

	private static func jpeg(from image: CGImage) throws -> Data {
		let data = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
			throw BuddyError("Couldn't capture the screen. Try again.")
		}
		let options = [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
		CGImageDestinationAddImage(destination, image, options)
		guard CGImageDestinationFinalize(destination) else {
			throw BuddyError("Couldn't capture the screen. Try again.")
		}
		return data as Data
	}
}
