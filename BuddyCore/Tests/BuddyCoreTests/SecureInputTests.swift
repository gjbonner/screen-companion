import Testing
@testable import BuddyCore

/// Screenshots go to a cloud model, so nothing may be captured or sent while a password field is active.
@MainActor
struct SecureInputTests {
	private static let secureMessage = BuddyMessage(BuddyCoordinator.secureInputMessage, kind: .problem)

	@Test
	func passwordFieldActiveAtKeyDownNeverCapturesOrSends() async throws {
		let harness = Harness(secureInput: FakeSecureInput(active: true))
		let buddy = harness.coordinator

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(Self.secureMessage) }

		#expect(await harness.screen.captureCount == 0)
		#expect(harness.answers.requestCount == 0)
		#expect(await harness.speech.spoken.isEmpty)
	}

	@Test
	func passwordFieldActiveAtReleaseDiscardsTheScreenshotUnsent() async throws {
		let harness = Harness()
		let buddy = harness.coordinator

		buddy.startListening()
		try await waitUntil { await harness.screen.captureCount == 1 }
		harness.secureInput.set(true)
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(Self.secureMessage) }

		#expect(harness.answers.requestCount == 0)
		#expect(await harness.speech.spoken.isEmpty)
	}

	@Test
	func askWorksAgainOnceThePasswordFieldIsGone() async throws {
		let harness = Harness(secureInput: FakeSecureInput(active: true))
		let buddy = harness.coordinator

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(Self.secureMessage) }

		harness.secureInput.set(false)
		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .idle }

		#expect(await harness.screen.captureCount == 1)
		#expect(harness.answers.requestCount == 1)
		#expect(await harness.speech.spoken == ["Click Edit."])
	}

	@Test
	func tabToAskWhileAPasswordFieldIsActiveStillNeverCaptures() async throws {
		let harness = Harness(secureInput: FakeSecureInput(active: true))
		let buddy = harness.coordinator
		buddy.setMode(.draft)

		buddy.startListening()
		buddy.toggleMode()
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(Self.secureMessage) }

		#expect(await harness.screen.captureCount == 0)
		#expect(harness.answers.requestCount == 0)
	}

	@Test
	func draftIsNotBlockedBecauseItNeverLooksAtTheScreen() async throws {
		let harness = Harness(secureInput: FakeSecureInput(active: true), cleaner: FakeCleaner(transform: { _ in "Hello." }))
		let buddy = harness.coordinator
		buddy.setMode(.draft)

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .idle }

		#expect(await harness.inserter.inserted == ["Hello."])
		#expect(await harness.screen.captureCount == 0)
	}
}
