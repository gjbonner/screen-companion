import AppKit
import BuddyCore
import Vision

/// Finds the model's label as text in the screenshot, using on-device text recognition (Vision).
///
/// Works in any app, including browsers and Electron apps that hide their contents from Accessibility.
/// Blocking; call it off the main thread.
enum ScreenTextFinder {
	/// Each piece of recognized text matching `label`, boxed to just the matching words, in AppKit global points.
	static func candidates(matching label: String, in screen: CapturedScreen) -> [SnapCandidate] {
		let request = makeRequest()
		let handler = VNImageRequestHandler(data: screen.imageData, options: [:])
		do {
			try handler.perform([request])
		} catch {
			Log.point.error("Text recognition failed: \(error.localizedDescription, privacy: .public)")
			return []
		}

		let mapper = CoordinateMapper(screen: screen)
		let size = screen.imagePixelSize
		var found: [SnapCandidate] = []
		for observation in request.results ?? [] {
			guard let text = observation.topCandidates(1).first,
				let range = SnapGuardrails.labelRange(of: label, in: text.string),
				let box = (try? text.boundingBox(for: range))?.boundingBox else {
				continue
			}
			// Vision's boxes are normalized, with the origin at the bottom-left.
			let imageRect = CGRect(
				x: box.minX * size.width,
				y: (1 - box.maxY) * size.height,
				width: box.width * size.width,
				height: box.height * size.height
			)
			found.append(SnapCandidate(
				frame: mapper.screenRect(forImageRect: imageRect),
				role: nil,
				label: String(text.string[range])
			))
		}
		return found
	}

	/// Recognizes a small image of text once, so the models are loaded before the first real lookup.
	/// The first recognition in a process took over 20 s in testing; later ones take about 0.1 s.
	static func warmUp() {
		let started = ContinuousClock.now
		let size = CGSize(width: 240, height: 60)
		guard let context = CGContext(
			data: nil,
			width: Int(size.width),
			height: Int(size.height),
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else {
			return
		}
		context.setFillColor(NSColor.white.cgColor)
		context.fill(CGRect(origin: .zero, size: size))
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
		("Buddy" as NSString).draw(at: CGPoint(x: 16, y: 12), withAttributes: [
			.font: NSFont.systemFont(ofSize: 28),
			.foregroundColor: NSColor.black,
		])
		NSGraphicsContext.restoreGraphicsState()
		guard let image = context.makeImage() else {
			return
		}
		try? VNImageRequestHandler(cgImage: image, options: [:]).perform([makeRequest()])
		Log.point.info("Text recognition warmed up in \(ContinuousClock.now - started, privacy: .public)")
	}

	private static func makeRequest() -> VNRecognizeTextRequest {
		let request = VNRecognizeTextRequest()
		request.recognitionLevel = .accurate
		request.usesLanguageCorrection = false
		return request
	}
}
