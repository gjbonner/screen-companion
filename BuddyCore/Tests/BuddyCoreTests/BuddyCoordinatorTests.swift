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
	func askSpeaksEachSentenceAsItCompletes() async throws {
		let harness = Harness(answers: FakeAnswerProvider(events: [
			.text("Click Edit next to the ad set."),
			.text(" Budget is under "),
			.text("Budget & Schedule."),
		]))
		let buddy = harness.coordinator

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .idle }

		#expect(await harness.speech.spoken == ["Click Edit next to the ad set.", "Budget is under Budget & Schedule."])
	}

	@Test
	func answerCardTracksHowMuchHasBeenSpoken() async throws {
		let harness = Harness(
			answers: FakeAnswerProvider(events: [.text("First part. Second part.")]),
			speech: FakeSpeech(holdsUntilStopped: true)
		)
		let buddy = harness.coordinator

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { await harness.speech.spoken.count == 1 }

		#expect(buddy.state == .answering(text: "First part. Second part.", point: nil, spokenLength: "First part.".count))
		buddy.cancel()
	}

	@Test
	func toggleMutedFlipsTheSetting() {
		let buddy = Harness().coordinator

		#expect(!buddy.isMuted)
		buddy.toggleMuted()
		#expect(buddy.isMuted)
		buddy.toggleMuted()
		#expect(!buddy.isMuted)
	}

	@Test
	func mutedAnswerIsShownButNotSpoken() async throws {
		let harness = Harness(answers: FakeAnswerProvider(events: [.text("Click Edit. Then save.")]))
		let buddy = harness.coordinator
		buddy.setMuted(true)

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil {
			if case .answering(let text, _, _) = buddy.state {
				return text == "Click Edit. Then save."
			}
			return buddy.state == .idle
		}
		try await waitUntil { buddy.state == .idle }

		#expect(await harness.speech.spoken.isEmpty)
	}

	@Test
	func mutingMidAnswerStopsSpeechAndSkipsTheRest() async throws {
		let answers = ControlledAnswerProvider()
		let harness = Harness(answers: FakeAnswerProvider(), speech: FakeSpeech(holdsUntilStopped: true))
		let buddy = BuddyCoordinatorTests.coordinator(harness: harness, answers: answers)

		buddy.startListening()
		buddy.stopListening()
		answers.continuation.yield(.text("First sentence. "))
		try await waitUntil { await harness.speech.spoken == ["First sentence."] }

		buddy.setMuted(true)
		try await waitUntil { await harness.speech.stopCount == 1 }

		answers.continuation.yield(.text("Second sentence. Third sentence."))
		answers.continuation.finish()
		try await waitUntil { buddy.state == .idle }

		#expect(await harness.speech.spoken == ["First sentence."])
	}

	@Test
	func unmutingMidAnswerSpeaksTheSentencesThatFollow() async throws {
		let answers = ControlledAnswerProvider()
		let harness = Harness()
		let buddy = BuddyCoordinatorTests.coordinator(harness: harness, answers: answers)
		buddy.setMuted(true)

		buddy.startListening()
		buddy.stopListening()
		answers.continuation.yield(.text("First sentence. "))
		try await waitUntil {
			if case .answering = buddy.state {
				return true
			}
			return false
		}

		buddy.setMuted(false)
		answers.continuation.yield(.text("Second sentence."))
		answers.continuation.finish()
		try await waitUntil { buddy.state == .idle }

		#expect(await harness.speech.spoken == ["Second sentence."])
	}

	@Test
	func mutedAnswerStaysUpLongEnoughToRead() async throws {
		let harness = Harness(answers: FakeAnswerProvider(events: [.text("One two three four five six.")]))
		let buddy = BuddyCoordinator(
			services: BuddyCoordinatorTests.services(harness: harness, answers: FakeAnswerProvider(events: [.text("One two three four five six.")])),
			isMuted: true,
			answerLinger: .zero,
			readingTimePerWord: .seconds(10)
		)

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil {
			if case .answering = buddy.state {
				return true
			}
			return false
		}
		try await Task.sleep(for: .milliseconds(200))

		guard case .answering = buddy.state else {
			Issue.record("A muted answer disappeared before it could be read: \(buddy.state)")
			return
		}
		buddy.cancel()
	}

	private static func services(harness: Harness, answers: any AnswerProvider) -> BuddyServices {
		BuddyServices(
			permissions: FakePermissions(),
			transcriber: harness.transcriber,
			screen: harness.screen,
			secureInput: harness.secureInput,
			answers: answers,
			cleaner: FakeCleaner(),
			speech: harness.speech,
			inserter: harness.inserter,
			apiKeys: FakeAPIKeys()
		)
	}

	private static func coordinator(harness: Harness, answers: any AnswerProvider) -> BuddyCoordinator {
		BuddyCoordinator(
			services: services(harness: harness, answers: answers),
			messageDuration: .seconds(60),
			answerLinger: .zero,
			readingTimePerWord: .zero
		)
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
	func silentHoldShowsDidNotHearAnything() async throws {
		let harness = Harness(finalText: "")
		let buddy = harness.coordinator

		buddy.startListening()
		try await waitUntil { await harness.transcriber.startCount == 1 }
		await harness.transcriber.emit(.level(0.01))
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(BuddyMessage("Didn't hear anything.", kind: .info)) }
		#expect(await harness.speech.spoken.isEmpty)
	}

	@Test
	func fillerOnlyHoldShowsDidNotCatchThatWithoutCallingTheModel() async throws {
		let harness = Harness(finalText: "um, uh")
		let buddy = harness.coordinator

		buddy.startListening()
		try await waitUntil { await harness.transcriber.startCount == 1 }
		await harness.transcriber.emit(.level(0.4))
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(BuddyMessage("Didn't catch that. Try again.", kind: .info)) }
		#expect(await harness.speech.spoken.isEmpty)
		#expect(await harness.screen.captureCount == 1)
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
	func tabToDraftDuringAskHoldInsertsAndNeverSendsTheScreenshot() async throws {
		let harness = Harness(finalText: "see you wednesday")
		let buddy = harness.coordinator

		buddy.startListening()
		try await waitUntil { await harness.screen.captureCount == 1 }
		buddy.toggleMode()
		#expect(buddy.mode == .draft)
		buddy.stopListening()
		try await waitUntil { buddy.state == .idle }

		#expect(await harness.inserter.inserted == ["see you wednesday"])
		#expect(harness.answers.requestCount == 0)
		#expect(await harness.speech.spoken.isEmpty)
	}

	@Test
	func modeSwitchedWithTabStaysForTheNextRequest() async throws {
		let harness = Harness(finalText: "see you wednesday")
		let buddy = harness.coordinator

		buddy.startListening()
		buddy.toggleMode()
		buddy.stopListening()
		try await waitUntil { buddy.state == .idle }

		// The next hold, with no Tab, is still Draft.
		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { await harness.inserter.inserted.count == 2 }

		#expect(buddy.mode == .draft)
		#expect(harness.answers.requestCount == 0)
	}

	@Test
	func twoTabsInOneHoldEndInTheStartingMode() async throws {
		let harness = Harness()
		let buddy = harness.coordinator

		buddy.startListening()
		buddy.toggleMode()
		buddy.toggleMode()
		#expect(buddy.mode == .ask)
		buddy.stopListening()
		try await waitUntil { buddy.state == .idle }

		#expect(await harness.speech.spoken == ["Click Edit."])
		#expect(harness.answers.requestCount == 1)
		#expect(await harness.screen.captureCount == 1)
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
	func draftWithNoFocusedFieldTellsTheUserInThePill() async throws {
		let harness = Harness(inserter: FakeInserter(result: .copiedToClipboard(reason: DraftInsertion.noTextFieldMessage)))
		let buddy = harness.coordinator
		buddy.setMode(.draft)

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(BuddyMessage("No text field is focused. Copied, paste with ⌘V.", kind: .info)) }
	}

	@Test
	func draftPasteTellsTheUserItIsOnTheClipboard() async throws {
		let harness = Harness(inserter: FakeInserter(result: .insertedAndCopied(note: DraftInsertion.copiedToClipboardMessage)))
		let buddy = harness.coordinator
		buddy.setMode(.draft)

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(BuddyMessage("Copied to clipboard", kind: .info)) }
	}

	@Test
	func draftCleanupErrorShowsItsMessageAndInsertsNothing() async throws {
		let harness = Harness(cleaner: FakeCleaner(error: BuddyError("No internet connection.")))
		let buddy = harness.coordinator
		buddy.setMode(.draft)

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { buddy.state == .message(BuddyMessage("No internet connection.", kind: .problem)) }
		#expect(await harness.inserter.inserted.isEmpty)
	}

	@Test
	func escapeWhileDraftIsCleaningUpInsertsNothing() async throws {
		let cleaner = FakeCleaner(delay: .seconds(10))
		let harness = Harness(cleaner: cleaner)
		let buddy = harness.coordinator
		buddy.setMode(.draft)

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil { cleaner.callCount == 1 }
		buddy.cancel()

		#expect(buddy.state == .idle)
		// Give a cancelled-but-still-running request time to insert, if it wrongly would.
		try await Task.sleep(for: .milliseconds(100))
		#expect(buddy.state == .idle)
		#expect(await harness.inserter.inserted.isEmpty)
	}

	@Test
	func draftWithoutAnAPIKeyShowsProblemAndNeverCleans() async throws {
		let cleaner = FakeCleaner()
		let harness = Harness(cleaner: cleaner, apiKeys: FakeAPIKeys(key: nil))
		let buddy = harness.coordinator
		buddy.setMode(.draft)

		buddy.startListening()
		buddy.stopListening()
		try await waitUntil {
			if case .message(let message) = buddy.state {
				return message.kind == .problem && message.text.contains("API key")
			}
			return false
		}
		#expect(cleaner.callCount == 0)
		#expect(await harness.inserter.inserted.isEmpty)
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
				secureInput: FakeSecureInput(),
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
