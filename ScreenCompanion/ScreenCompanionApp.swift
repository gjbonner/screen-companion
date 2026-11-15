import ApplicationServices
import BuddyCore
import SwiftUI

@main
struct ScreenCompanionApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

	var body: some Scene {
		MenuBarExtra {
			MenuBarView(coordinator: appDelegate.coordinator, setup: appDelegate.setup, hotkey: appDelegate.hotkey) {
				appDelegate.showSetup()
			}
		} label: {
			MenuBarIcon(coordinator: appDelegate.coordinator, setup: appDelegate.setup)
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
	let setup = SetupMonitor()
	let hotkey = HotkeySetting()
	private lazy var onboarding = OnboardingWindowController(setup: setup, hotkey: hotkey)
	private var pill: PillPanelController?
	private var overlay: PointOverlayController?
	private var hotkeys: HotkeyMonitor?

	func applicationDidFinishLaunching(_ notification: Notification) {
		pill = PillPanelController(coordinator: coordinator)
		overlay = PointOverlayController(coordinator: coordinator)
		Task.detached(priority: .utility) {
			ScreenTextFinder.warmUp()
		}
		rememberMuteSetting()
		#if DEBUG
		coordinator.onAskTiming = { timing in
			Log.timing.info("""
				Ask after release: transcript \(Log.milliseconds(timing.transcript)) ms, \
				screen \(Log.milliseconds(timing.screen)) ms, \
				first token \(Log.milliseconds(timing.firstToken)) ms, \
				first sentence to voice \(Log.milliseconds(timing.firstSentence)) ms
				""")
		}
		#endif

		let monitor = HotkeyMonitor(
			hotkey: hotkey.choice,
			onAction: { [weak self] action in
				self?.handle(action)
			},
			isBuddyBusy: { [weak self] in
				self?.coordinator.state.isBusy ?? false
			}
		)
		monitor.start()
		hotkeys = monitor
		followHotkeySetting()

		if !setup.checklist.isComplete {
			showSetup()
		}
	}

	func showSetup() {
		onboarding.show()
	}

	/// Passes a new hotkey choice, from the menu bar or the setup window, to the monitor.
	private func followHotkeySetting() {
		withObservationTracking {
			_ = hotkey.choice
		} onChange: { [weak self] in
			DispatchQueue.main.async {
				guard let self else {
					return
				}
				self.hotkeys?.setHotkey(self.hotkey.choice)
				self.followHotkeySetting()
			}
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
