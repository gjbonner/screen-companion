import Testing
@testable import BuddyCore

struct SetupChecklistTests {
	private static let allGranted = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, PermissionStatus.granted) })

	@Test
	func everythingGrantedWithAKeyIsComplete() {
		let checklist = SetupChecklist(statuses: Self.allGranted, hasAPIKey: true, screenRecordingRequested: false)
		#expect(checklist.isComplete)
		#expect(checklist.remainingCount == 0)
		for permission in Permission.allCases {
			#expect(checklist.action(for: permission) == .done)
		}
		#expect(checklist.apiKeyAction == .done)
	}

	@Test
	func missingKeyAloneLeavesSetupIncomplete() {
		let checklist = SetupChecklist(statuses: Self.allGranted, hasAPIKey: false, screenRecordingRequested: false)
		#expect(!checklist.isComplete)
		#expect(checklist.remainingCount == 1)
		#expect(checklist.apiKeyAction == .enterKey)
	}

	@Test
	func freshMachineNeedsEverything() {
		let checklist = SetupChecklist(statuses: [:], hasAPIKey: false, screenRecordingRequested: false)
		#expect(checklist.remainingCount == 5)
		#expect(checklist.action(for: .microphone) == .allow)
		#expect(checklist.action(for: .speechRecognition) == .allow)
		#expect(checklist.action(for: .accessibility) == .openSettings)
		#expect(checklist.action(for: .screenRecording) == .openSettings)
	}

	@Test(arguments: [Permission.microphone, .speechRecognition, .accessibility])
	func deniedPermissionSendsTheUserToSettings(_ permission: Permission) {
		var statuses = Self.allGranted
		statuses[permission] = .denied
		let checklist = SetupChecklist(statuses: statuses, hasAPIKey: true, screenRecordingRequested: false)
		#expect(checklist.action(for: permission) == .openSettings)
		#expect(!checklist.isComplete)
	}

	@Test
	func screenRecordingOffersARelaunchOnceTheUserWasSentToSettings() {
		var statuses = Self.allGranted
		statuses[.screenRecording] = .notRequested
		let before = SetupChecklist(statuses: statuses, hasAPIKey: true, screenRecordingRequested: false)
		let after = SetupChecklist(statuses: statuses, hasAPIKey: true, screenRecordingRequested: true)
		#expect(before.action(for: .screenRecording) == .openSettings)
		#expect(after.action(for: .screenRecording) == .relaunch)
	}

	@Test
	func deniedScreenRecordingAlsoOffersARelaunchAfterSettings() {
		var statuses = Self.allGranted
		statuses[.screenRecording] = .denied
		let checklist = SetupChecklist(statuses: statuses, hasAPIKey: true, screenRecordingRequested: true)
		#expect(checklist.action(for: .screenRecording) == .relaunch)
	}

	@Test
	func grantedScreenRecordingNeedsNothingEvenIfRequested() {
		let checklist = SetupChecklist(statuses: Self.allGranted, hasAPIKey: true, screenRecordingRequested: true)
		#expect(checklist.action(for: .screenRecording) == .done)
	}
}
