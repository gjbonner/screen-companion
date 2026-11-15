import CoreGraphics

/// Maps the model's guess from screenshot pixels to where it is on screen.
///
/// Three coordinate spaces are involved:
/// - Image pixels: the screenshot sent to the model, origin top-left, y down. Possibly downscaled (`CaptureSize`).
/// - AppKit global points: where Buddy's overlay windows live. Origin bottom-left of the primary display, y up.
/// - Accessibility (Quartz) global points: what `AXUIElementCopyElementAtPosition` and `kAXPositionAttribute` use.
///   Origin top-left of the primary display, y down.
///
/// Retina scale doesn't enter into it: the display frame is in points and the image size is what was sent,
/// so the mapping is a plain proportion between the two.
public struct CoordinateMapper: Sendable, Equatable {
	public var imagePixelSize: CGSize
	/// The captured display's frame in AppKit global points.
	public var displayFrame: CGRect

	public init(imagePixelSize: CGSize, displayFrame: CGRect) {
		self.imagePixelSize = imagePixelSize
		self.displayFrame = displayFrame
	}

	public init(screen: CapturedScreen) {
		self.init(imagePixelSize: screen.imagePixelSize, displayFrame: screen.displayFrame)
	}

	/// The AppKit global point for a point in the screenshot, or nil if it's outside the image.
	///
	/// A guess outside the image means the model misread its size, so Buddy doesn't point rather than point at an edge.
	public func screenPoint(forImagePoint imagePoint: CGPoint) -> CGPoint? {
		let width = imagePixelSize.width
		let height = imagePixelSize.height
		guard width > 0, height > 0,
			(0...width).contains(imagePoint.x),
			(0...height).contains(imagePoint.y) else {
			return nil
		}
		let x = displayFrame.minX + imagePoint.x * displayFrame.width / width
		let y = displayFrame.maxY - imagePoint.y * displayFrame.height / height
		return CGPoint(x: x, y: y)
	}

	/// Converts between AppKit and Accessibility global points. The flip is its own inverse, so this works both ways.
	/// - Parameter primaryDisplayHeight: the height in points of the display with the menu bar (`NSScreen.screens[0]`).
	public static func accessibilityPoint(fromScreenPoint point: CGPoint, primaryDisplayHeight: CGFloat) -> CGPoint {
		CGPoint(x: point.x, y: primaryDisplayHeight - point.y)
	}

	/// The AppKit global rect for a rect in the screenshot (pixels, origin top-left), such as recognized text.
	public func screenRect(forImageRect rect: CGRect) -> CGRect {
		guard imagePixelSize.width > 0, imagePixelSize.height > 0 else {
			return .zero
		}
		let scaleX = displayFrame.width / imagePixelSize.width
		let scaleY = displayFrame.height / imagePixelSize.height
		return CGRect(
			x: displayFrame.minX + rect.minX * scaleX,
			y: displayFrame.maxY - rect.maxY * scaleY,
			width: rect.width * scaleX,
			height: rect.height * scaleY
		)
	}

	/// Converts an element's Accessibility frame (origin at its top-left) to an AppKit rect (origin at its bottom-left).
	public static func screenRect(fromAccessibilityRect rect: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
		CGRect(x: rect.minX, y: primaryDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
	}
}

/// Where the mark points, located on screen, and the display it's on.
public struct Pointing: Sendable, Equatable {
	public var target: PointTarget
	/// The display the screenshot was taken of, in AppKit global points.
	public var displayFrame: CGRect

	public init(target: PointTarget, displayFrame: CGRect) {
		self.target = target
		self.displayFrame = displayFrame
	}
}
