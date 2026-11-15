import Foundation
import Testing
@testable import ScreenCompanion

struct VoiceTipTests {
	@Test(arguments: [27, 28])
	func newerMacOSNamesReadAndSpeak(_ major: Int) {
		let text = VoiceTip.instructions(for: OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0))
		#expect(text.contains("Accessibility › Read & Speak)"))
		#expect(!text.contains("Spoken Content"))
	}

	@Test(arguments: [15, 26, 27])
	func everyVersionSuggestsSearchingSettings(_ major: Int) {
		let text = VoiceTip.instructions(for: OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0))
		#expect(text.contains("search for \"System voice\""))
	}

	@Test(arguments: [15, 26])
	func olderMacOSNamesSpokenContent(_ major: Int) {
		let text = VoiceTip.instructions(for: OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0))
		#expect(text.contains("Accessibility › Spoken Content)"))
		#expect(!text.contains("Read & Speak"))
	}
}
