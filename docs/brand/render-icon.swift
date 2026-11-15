import AppKit
import CoreGraphics

// Renders the Buddy app icon: a near-black tile with the purple mark landing at the end of its flight arc.
// Usage: swift docs/brand/render-icon.swift ScreenCompanion/Assets.xcassets/AppIcon.appiconset

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
	CGColor(
		red: CGFloat((hex >> 16) & 0xFF) / 255,
		green: CGFloat((hex >> 8) & 0xFF) / 255,
		blue: CGFloat(hex & 0xFF) / 255,
		alpha: alpha
	)
}

let purple = rgb(0x9A3CFF)
let offWhite = rgb(0xF5F4F0)

func render(pixels: Int) -> CGImage {
	let size = CGFloat(pixels)
	let space = CGColorSpace(name: CGColorSpace.sRGB)!
	let ctx = CGContext(
		data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
		space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
	)!
	// Work on Apple's 1024 grid, flipped so y runs downward.
	ctx.scaleBy(x: size / 1024, y: size / 1024)
	ctx.translateBy(x: 0, y: 1024)
	ctx.scaleBy(x: 1, y: -1)

	// Tile: 824 pt body centered on the canvas, with the standard soft drop shadow.
	let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
	let tile = CGPath(roundedRect: tileRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
	ctx.saveGState()
	ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: rgb(0x000000, 0.35))
	ctx.addPath(tile)
	ctx.setFillColor(rgb(0x171717))
	ctx.fillPath()
	ctx.restoreGState()

	// Subtle top-down sheen so the tile isn't flat black.
	ctx.saveGState()
	ctx.addPath(tile)
	ctx.clip()
	let sheen = CGGradient(
		colorsSpace: space,
		colors: [rgb(0x2F2F2F), rgb(0x0D0D0D)] as CFArray,
		locations: [0, 1]
	)!
	ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

	// Flight arc: from the top-left, curving down to where the mark lands.
	let start = CGPoint(x: 230, y: 380)
	let control = CGPoint(x: 520, y: 170)
	let end = CGPoint(x: 610, y: 610)
	let steps = 11
	for i in 0..<steps {
		let t = CGFloat(i) / CGFloat(steps)
		let u = 1 - t
		let p = CGPoint(
			x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
			y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
		)
		if hypot(p.x - end.x, p.y - end.y) < 185 {
			continue
		}
		let radius = 9 + 9 * t
		ctx.setFillColor(rgb(0xF5F4F0, 0.18 + 0.5 * t))
		ctx.fillEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
	}

	// Landing ring: the highlight Buddy draws around what it points at.
	let ring = CGRect(x: end.x - 150, y: end.y - 150, width: 300, height: 300)
	ctx.setStrokeColor(rgb(0x9A3CFF, 0.45))
	ctx.setLineWidth(14)
	ctx.strokeEllipse(in: ring.insetBy(dx: 7, dy: 7))

	// The mark: purple with a white ring and a soft purple glow.
	let markRadius: CGFloat = 92
	let mark = CGRect(x: end.x - markRadius, y: end.y - markRadius, width: markRadius * 2, height: markRadius * 2)
	ctx.saveGState()
	ctx.setShadow(offset: .zero, blur: 60, color: rgb(0x9A3CFF, 0.8))
	ctx.setFillColor(purple)
	ctx.fillEllipse(in: mark)
	ctx.restoreGState()
	ctx.setStrokeColor(offWhite)
	ctx.setLineWidth(20)
	ctx.strokeEllipse(in: mark.insetBy(dx: 10, dy: 10))
	ctx.restoreGState()

	return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
	let rep = NSBitmapImageRep(cgImage: image)
	let data = rep.representation(using: .png, properties: [:])!
	try! data.write(to: URL(fileURLWithPath: path))
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
	let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
	write(render(pixels: points * scale), to: "\(outDir)/\(name)")
}
print("wrote icons to \(outDir)")
