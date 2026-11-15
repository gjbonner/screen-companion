import SwiftUI

/// The brand layer. Every color and the mark artwork come from here, so the look can be swapped in one place.
/// Colors follow shadow.co: monochrome near-black surfaces with their CTA purple as the single accent.
enum Theme {
	/// Shadow CTA purple, #9A3CFF.
	static let accent = Color(red: 0x9A / 255, green: 0x3C / 255, blue: 0xFF / 255)
	/// Shadow near-black, #171717.
	static let pillBackground = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255)
	static let highlight = accent
}
