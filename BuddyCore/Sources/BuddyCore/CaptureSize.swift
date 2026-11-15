import CoreGraphics

/// How large the screenshot sent to the model is.
///
/// The image keeps the display's shape, so on-screen proportions (and the model's pointing) aren't distorted,
/// and its longest side is at most `maxLongEdge` pixels, to keep uploads small and the first word fast.
/// It never exceeds the display's real pixel count.
public enum CaptureSize {
	public static let maxLongEdge: CGFloat = 1600

	/// - Parameters:
	///   - displaySize: the display's size in points.
	///   - backingScale: pixels per point (2 on Retina displays, 1 on most external monitors).
	public static func pixelSize(displaySize: CGSize, backingScale: CGFloat, maxLongEdge: CGFloat = maxLongEdge) -> CGSize {
		let longEdgePoints = max(displaySize.width, displaySize.height)
		guard longEdgePoints > 0, backingScale > 0 else {
			return .zero
		}
		let longEdgePixels = min(maxLongEdge, longEdgePoints * backingScale)
		let factor = longEdgePixels / longEdgePoints
		return CGSize(width: (displaySize.width * factor).rounded(), height: (displaySize.height * factor).rounded())
	}
}
