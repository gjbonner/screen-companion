import BuddyCore
import Testing
@testable import ScreenCompanion

/// The menu bar's warning while first-run setup is incomplete.
struct MenuBarSetupTests {
	private static let allGranted = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, PermissionStatus.granted) })

	// MARK: - Icon

	@Test(arguments: BuddyMode.allCases)
	func iconIsAWarningWhileSetupIsIncomplete(_ mode: BuddyMode) {
		#expect(MenuBarIcon.symbolName(mode: mode, setupComplete: false) == "exclamationmark.triangle")
	}

	@Test
	func iconShowsTheModeOnceSetupIsComplete() {
		#expect(MenuBarIcon.symbolName(mode: .ask, setupComplete: true) == "questionmark.bubble")
		#expect(MenuBarIcon.symbolName(mode: .draft, setupComplete: true) == "text.cursor")
	}

	// MARK: - Menu warning

	@Test
	func noWarningOnceSetupIsComplete() {
		let checklist = SetupChecklist(statuses: Self.allGranted, hasAPIKey: true, screenRecordingRequested: false)
		#expect(MenuBarView.setupWarning(for: checklist) == nil)
	}

	@Test
	func missingKeyAloneShowsOneStepLeft() {
		let checklist = SetupChecklist(statuses: Self.allGranted, hasAPIKey: false, screenRecordingRequested: false)
		#expect(MenuBarView.setupWarning(for: checklist) == "Setup: 1 step left")
	}

	@Test
	func severalMissingStepsAreCounted() {
		var statuses = Self.allGranted
		statuses[.accessibility] = .notRequested
		statuses[.screenRecording] = .denied
		let checklist = SetupChecklist(statuses: statuses, hasAPIKey: false, screenRecordingRequested: false)
		#expect(MenuBarView.setupWarning(for: checklist) == "Setup: 3 steps left")
	}

	@Test
	func freshMachineShowsAllFiveSteps() {
		let checklist = SetupChecklist(statuses: [:], hasAPIKey: false, screenRecordingRequested: false)
		#expect(MenuBarView.setupWarning(for: checklist) == "Setup: 5 steps left")
	}
}
