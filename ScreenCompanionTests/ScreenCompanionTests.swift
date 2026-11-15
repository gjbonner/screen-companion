import Testing
@testable import ScreenCompanion

struct ScreenCompanionTests {
	@Test
	@MainActor
	func contentViewBuilds() {
		_ = ContentView().body
	}
}
