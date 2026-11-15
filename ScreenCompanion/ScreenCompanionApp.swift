import ApplicationServices
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
	private static let mutedDefaultsKey = "muteAnswers"

	let coordinator = BuddyCoordinator(
		services: .live,
		isMuted: UserDefaults.standard.bool(forKey: AppDelegate.mutedDefaultsKey)
	)
	private var pill: PillPanelController?
	private var hotkeys: HotkeyMonitor?

	func applicationDidFinishLaunching(_ notification: Notification) {
		pill = PillPanelController(coordinator: coordinator)
		rememberMuteSetting()

		let monitor = HotkeyMonitor(
			onAction: { [weak self] action in
				self?.handle(action)
			},
			isBuddyBusy: { [weak self] in
				self?.coordinator.state.isBusy ?? false
			}
		)
		monitor.start()
		hotkeys = monitor

		// Until onboarding exists, ask macOS to show its Accessibility prompt once at launch.
		if !AXIsProcessTrusted() {
			let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
			_ = AXIsProcessTrustedWithOptions(options)
		}
	}

	/// Saves the mute setting whenever it changes, from the menu or the pill.
	private func rememberMuteSetting() {
		withObservationTracking {
			_ = coordinator.isMuted
		} onChange: { [weak self] in
			DispatchQueue.main.async {
				guard let self else {
					return
				}
				UserDefaults.standard.set(self.coordinator.isMuted, forKey: Self.mutedDefaultsKey)
				self.rememberMuteSetting()
			}
		}
	}

	private func handle(_ action: HotkeyAction) {
		switch action {
		case .press:
			coordinator.startListening()
		case .release:
			coordinator.stopListening()
		case .cancel, .escape:
			coordinator.cancel()
		case .toggleMode:
			coordinator.toggleMode()
		}
	}
}
