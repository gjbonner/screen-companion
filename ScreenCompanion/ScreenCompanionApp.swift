import BuddyCore
import SwiftUI

@main
struct ScreenCompanionApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

	var body: some Scene {
		MenuBarExtra {
			MenuBarView(coordinator: appDelegate.coordinator)
		} label: {
			MenuBarIcon(coordinator: appDelegate.coordinator)
		}
		.menuBarExtraStyle(.window)
	}
}

/// Owns the long-lived objects. Created once at launch; everything else receives what it needs from here.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	let coordinator = BuddyCoordinator(services: .placeholders)
}
