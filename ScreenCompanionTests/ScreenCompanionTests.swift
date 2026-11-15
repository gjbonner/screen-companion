import BuddyCore
import Testing
@testable import ScreenCompanion

struct ScreenCompanionTests {
	@Test
	@MainActor
	func menuBarViewBuilds() {
		let coordinator = BuddyCoordinator(services: .placeholders)
		_ = MenuBarView(coordinator: coordinator, setup: SetupMonitor(), openSetup: {}).body
	}
}
