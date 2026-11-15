import Testing
@testable import BuddyCore

/// Listening started from the menu bar has no key release to end it, so it stops after a stretch without sound.
@MainActor
struct SilenceStopTests {
	private static let timeout: Duration = .milliseconds(150)

	@Test
	func buttonStartStopsByItselfWhenNothingIsSaid() async throws {
		let harness = Harness(finalText: "", silenceTimeout: Self.timeout)
		let buddy = harness.coordinator

		buddy.startListening(stopsOnSilence: true)
		try await waitUntil { buddy.state == .message(BuddyMessage("Didn't hear anything.", kind: .info)) }
	}

	@Test
	func buttonStartStopsAfterSpeechEndsAndAnswers() async throws {
		let harness = Harness(silenceTimeout: Self.timeout)
		let buddy = harness.coordinator

		buddy.startListening(stopsOnSilence: true)
		try await waitUntil { await harness.transcriber.startCount == 1 }
		await harness.transcriber.emit(.level(0.4))
		await harness.transcriber.emit(.partial("where is the budget"))

		try await waitUntil { await harness.speech.spoken == ["Click Edit."] }
	}

	@Test
	func soundKeepsListening() async throws {
		let harness = Harness(silenceTimeout: Self.timeout)
		let buddy = harness.coordinator

		buddy.startListening(stopsOnSilence: true)
		try await waitUntil { await harness.transcriber.startCount == 1 }
		// Keep talking for three times the timeout.
		for _ in 0..<9 {
			await harness.transcriber.emit(.level(0.3))
			try await Task.sleep(for: .milliseconds(50))
		}
		if case .listening = buddy.state {
		} else {
			Issue.record("Stopped while there was still sound: \(buddy.state)")
		}
		buddy.cancel()
	}

	@Test
	func quietBackgroundNoiseDoesNotCountAsSound() async throws {
		let harness = Harness(finalText: "", silenceTimeout: Self.timeout)
		let buddy = harness.coordinator

		buddy.startListening(stopsOnSilence: true)
		try await waitUntil { await harness.transcriber.startCount == 1 }
		for _ in 0..<6 {
			await harness.transcriber.emit(.level(SpeechFilter.silenceThreshold / 2))
			try await Task.sleep(for: .milliseconds(50))
		}
		try await waitUntil { buddy.state == .message(BuddyMessage("Didn't hear anything.", kind: .info)) }
	}

	@Test
	func hotkeyHoldNeverStopsOnSilence() async throws {
		let harness = Harness(silenceTimeout: Self.timeout)
		let buddy = harness.coordinator

		buddy.startListening()
		try await Task.sleep(for: Self.timeout * 4)
		if case .listening = buddy.state {
		} else {
			Issue.record("A hotkey hold stopped by itself: \(buddy.state)")
		}
		buddy.cancel()
	}

	@Test
	func stoppingByHandCancelsTheSilenceTimer() async throws {
		let harness = Harness(silenceTimeout: Self.timeout)
		let buddy = harness.coordinator

		buddy.startListening(stopsOnSilence: true)
		buddy.stopListening()
		try await waitUntil { buddy.state == .idle }
		// A leftover timer would act on the next request.
		buddy.startListening()
		try await Task.sleep(for: Self.timeout * 3)
		if case .listening = buddy.state {
		} else {
			Issue.record("The earlier silence timer ended a later hold: \(buddy.state)")
		}
		buddy.cancel()
	}
}
