#if DEBUG
import AppKit
import BuddyCore
import ImageIO
import UniformTypeIdentifiers

/// Debug builds only: saves each pointing attempt as the screenshot the model saw, with the model's guess (red)
/// and the snapped element (green) drawn on it. For the pointing accuracy check.
///
/// Files go to `~/Library/Caches/<bundle id>/PointDebug/`. They show whatever was on screen; delete the folder afterwards.
enum PointDebug {
	static func record(_ guess: PointGuess, screen: CapturedScreen, target: PointTarget?) {
		Task.detached(priority: .utility) {
			do {
				let url = try write(guess: guess, screen: screen, target: target)
				Log.point.info("Saved point debug image to \(url.path, privacy: .public)")
			} catch {
				Log.point.error("Couldn't save point debug image: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	static var folder: URL {
		let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
		return caches
			.appendingPathComponent(Bundle.main.bundleIdentifier ?? "ScreenCompanion", isDirectory: true)
			.appendingPathComponent("PointDebug", isDirectory: true)
	}

	private static func write(guess pointGuess: PointGuess, screen: CapturedScreen, target: PointTarget?) throws -> URL {
		let mapper = CoordinateMapper(screen: screen)
		guard let source = CGImageSourceCreateWithData(screen.imageData as CFData, nil),
			let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
			let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
			let context = CGContext(
				data: nil,
				width: image.width,
				height: image.height,
				bitsPerComponent: 8,
				bytesPerRow: 0,
				space: colorSpace,
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			) else {
			throw CocoaError(.fileReadCorruptFile)
		}
		let width = CGFloat(image.width)
		let height = CGFloat(image.height)
		context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
		// Draw with the image's top-left origin, the same coordinates the model answers in.
		context.translateBy(x: 0, y: height)
		context.scaleBy(x: 1, y: -1)

		var snapped = "no match, not pointing"
		if let target {
			let rect = imageRect(for: target.frame, mapper: mapper)
			context.setStrokeColor(NSColor.systemGreen.cgColor)
			context.setLineWidth(3)
			context.stroke(rect)
			snapped = "pointing at (\(Int(rect.minX)), \(Int(rect.minY)), \(Int(rect.width))×\(Int(rect.height)))"
		}

		let guess = pointGuess.imagePoint
		context.setStrokeColor(NSColor.systemRed.cgColor)
		context.setLineWidth(1)
		context.strokeLineSegments(between: [
			CGPoint(x: guess.x - 20, y: guess.y), CGPoint(x: guess.x + 20, y: guess.y),
			CGPoint(x: guess.x, y: guess.y - 20), CGPoint(x: guess.x, y: guess.y + 20),
		])
		context.setFillColor(NSColor.systemRed.cgColor)
		context.fillEllipse(in: CGRect(x: guess.x - 5, y: guess.y - 5, width: 10, height: 10))

		let caption = "\"\(pointGuess.label)\"  guess (\(Int(guess.x)), \(Int(guess.y))) in \(Int(width))×\(Int(height))  \(snapped)"
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
		(caption as NSString).draw(at: CGPoint(x: 12, y: height - 32), withAttributes: [
			.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
			.foregroundColor: NSColor.white,
			.backgroundColor: NSColor.black.withAlphaComponent(0.75),
		])
		NSGraphicsContext.restoreGraphicsState()

		guard let annotated = context.makeImage() else {
			throw CocoaError(.fileWriteUnknown)
		}
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let url = folder.appendingPathComponent("\(timestamp())-\(slug(pointGuess.label)).png")
		guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
			throw CocoaError(.fileWriteUnknown)
		}
		CGImageDestinationAddImage(destination, annotated, nil)
		guard CGImageDestinationFinalize(destination) else {
			throw CocoaError(.fileWriteUnknown)
		}
		return url
	}

	/// An AppKit global rect in the screenshot's pixels (top-left origin).
	private static func imageRect(for frame: CGRect, mapper: CoordinateMapper) -> CGRect {
		let display = mapper.displayFrame
		let scaleX = mapper.imagePixelSize.width / display.width
		let scaleY = mapper.imagePixelSize.height / display.height
		return CGRect(
			x: (frame.minX - display.minX) * scaleX,
			y: (display.maxY - frame.maxY) * scaleY,
			width: frame.width * scaleX,
			height: frame.height * scaleY
		)
	}

	private static func timestamp() -> String {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyyMMdd-HHmmss"
		return formatter.string(from: Date())
	}

	private static func slug(_ label: String) -> String {
		let words = label.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
		return words.prefix(6).joined(separator: "-")
	}
}
#endif
