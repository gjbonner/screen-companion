import CoreGraphics
import Testing
@testable import BuddyCore

@MainActor
struct BuddyCoordinatorTests {
	@Test
	func askHappyPathListensAnswersSpeaksAndReturnsToIdle() async throws {
		let guess = PointGuess(imagePoint: CGPoint(x: 189, y: 47), label: "Edit")
		let harness = Harness(answers: FakeAnswerProvider(events: [.text("Click "), .text("Edit."), .point(guess)]))
		let buddy = harness.coordinator

		buddy.startListening()
		#expect(buddy.state == .listening(transcript: "", level: 0))

		try await waitUntil { await harness.transcriber.startCount == 1 }
		await harness.transcriber.emit(.partial("where is"))
		try await waitUntil { buddy.state == .listening(transcript: "where is", level: 0) }

		buddy.stopListening()
		try await waitUntil { buddy.state == .idle }

		#expect(await harness.speech.spoken == ["Click Edit."])
		#expect(await harness.screen.captureCount == 1)
	}

	@Test
	func draftHappyPathInsertsCleanedTextWithoutCapturing() async throws {
		let harness = Harness(
			finalText: "um hello greg",
			cleaner: FakeCleaner(transform: { _ in "Hello Greg." })
		)
		let buddy = harness.coordinator
		buddy.setMode(.draft)

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .idle }

		#expect(await harness.inserter.inserted == ["Hello Greg."])
		#expect(await harness.screen.captureCount == 0)
	}

	@Test
	func missingMicrophoneShowsProblemAndDoesNotListen() async throws {
		let harness = Harness(permissions: FakePermissions(granted: [.speechRecognition, .screenRecording, .accessibility]))
		let buddy = harness.coordinator

		buddy.startListening()

		guard case .message(let message) = buddy.state else {
			Issue.record("Expected a message, got \(buddy.state)")
			return
		}
		#expect(message.kind == .problem)
		#expect(await harness.transcriber.startCount == 0)
	}

	@Test
	func missingScreenRecordingStopsAskWithProblem() async throws {
		let harness = Harness(permissions: FakePermissions(granted: [.microphone, .speechRecognition]))
		let buddy = harness.coordinator

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil {
			if case .message(let message) = buddy.state {
				return message.kind == .problem
			}
			return false
		}
		#expect(await harness.speech.spoken.isEmpty)
	}

	@Test
	func missingAPIKeyShowsProblem() async throws {
		let harness = Harness(apiKeys: FakeAPIKeys(key: nil))
		let buddy = harness.coordinator

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil {
			if case .message(let message) = buddy.state {
				return message.text.contains("API key")
			}
			return false
		}
	}

	@Test
	func emptyTranscriptShowsDidNotCatchThat() async throws {
		let harness = Harness(finalText: "   ")
		let buddy = harness.coordinator

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(BuddyMessage("Didn't catch that. Try again.", kind: .info)) }
		#expect(await harness.speech.spoken.isEmpty)
	}

	@Test
	func escapeWhileListeningCancelsAndReturnsToIdle() async throws {
		let harness = Harness()
		let buddy = harness.coordinator

		buddy.startListening()
		try await waitUntil { await harness.transcriber.startCount == 1 }
		buddy.cancel()

		#expect(buddy.state == .idle)
		try await waitUntil { await harness.transcriber.cancelCount == 1 }
	}

	@Test
	func escapeWhileAnsweringStopsSpeech() async throws {
		let harness = Harness(speech: FakeSpeech(holdsUntilStopped: true))
		let buddy = harness.coordinator

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { await harness.speech.spoken.count == 1 }
		buddy.cancel()

		#expect(buddy.state == .idle)
		try await waitUntil { await harness.speech.stopCount == 1 }
	}

	@Test
	func newHoldWhileAnsweringInterruptsAndListensAgain() async throws {
		let harness = Harness(speech: FakeSpeech(holdsUntilStopped: true))
		let buddy = harness.coordinator

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { await harness.speech.spoken.count == 1 }

		buddy.startListening()
		#expect(buddy.state == .listening(transcript: "", level: 0))
		try await waitUntil { await harness.speech.stopCount == 1 }
		try await waitUntil { await harness.transcriber.startCount == 2 }
	}

	@Test
	func tabToAskDuringDraftHoldCapturesAndAnswers() async throws {
		let harness = Harness()
		let buddy = harness.coordinator
		buddy.setMode(.draft)

		buddy.startListening()
		#expect(await harness.screen.captureCount == 0)
		buddy.toggleMode()
		#expect(buddy.mode == .ask)
		buddy.stopListening()
		try await waitUntil { buddy.state == .idle }

		#expect(await harness.screen.captureCount == 1)
		#expect(await harness.speech.spoken == ["Click Edit."])
		#expect(await harness.inserter.inserted.isEmpty)
	}

	@Test
	func answerErrorShowsItsMessage() async throws {
		let harness = Harness(answers: FakeAnswerProvider(events: [], error: BuddyError("Groq rate limit. Try again in 12s.")))
		let buddy = harness.coordinator

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(BuddyMessage("Groq rate limit. Try again in 12s.", kind: .problem)) }
	}

	@Test
	func draftClipboardFallbackShowsReason() async throws {
		let harness = Harness(inserter: FakeInserter(result: .copiedToClipboard(reason: "Copied. Paste with ⌘V.")))
		let buddy = harness.coordinator
		buddy.setMode(.draft)

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(BuddyMessage("Copied. Paste with ⌘V.", kind: .info)) }
	}

	@Test
	func draftInsertsNothingWhenCleanerReturnsEmpty() async throws {
		let harness = Harness(finalText: "anything", cleaner: FakeCleaner(transform: { _ in "" }))
		let buddy = harness.coordinator
		buddy.setMode(.draft)

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(BuddyMessage("Nothing to insert.", kind: .info)) }
		#expect(await harness.inserter.inserted.isEmpty)
	}

	@Test
	func messageReturnsToIdleAfterItsDuration() async throws {
		let transcriber = FakeTranscriber(finalText: "")
		let buddy = BuddyCoordinator(
			services: BuddyServices(
				permissions: FakePermissions(),
				transcriber: transcriber,
				screen: FakeScreenCapturer(),
				answers: FakeAnswerProvider(),
				cleaner: FakeCleaner(),
				speech: FakeSpeech(),
				inserter: FakeInserter(),
				apiKeys: FakeAPIKeys()
			),
			messageDuration: .milliseconds(20)
		)

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil {
			if case .message = buddy.state {
				return true
			}
			return false
		}
		try await waitUntil { buddy.state == .idle }
	}
}
