import Testing
@testable import BuddyCore

struct TranscriptAccumulatorTests {
	@Test
	func partialResultsReplaceTheSegmentInsteadOfRepeating() {
		var transcript = TranscriptAccumulator()

		_ = transcript.receive(text: "Let's", segmentClosed: false, isFinal: false)
		_ = transcript.receive(text: "Let's check", segmentClosed: false, isFinal: false)
		let next = transcript.receive(text: "Let's check the budget", segmentClosed: false, isFinal: false)

		#expect(next == .keepListening)
		#expect(transcript.heard == "Let's check the budget")
	}

	@Test
	func textBeforeAPauseIsKeptWhenTheNextSegmentStarts() {
		var transcript = TranscriptAccumulator()

		_ = transcript.receive(text: "Yeah, that's better now", segmentClosed: true, isFinal: false)
		_ = transcript.receive(text: "much", segmentClosed: false, isFinal: false)
		_ = transcript.receive(text: "much better", segmentClosed: false, isFinal: false)

		#expect(transcript.heard == "Yeah, that's better now much better")
	}

	@Test
	func severalPausesAccumulateEverySegment() {
		var transcript = TranscriptAccumulator()

		_ = transcript.receive(text: "Let's check the budget", segmentClosed: true, isFinal: false)
		_ = transcript.receive(text: "for the Coca-Cola", segmentClosed: true, isFinal: false)
		_ = transcript.receive(text: "ad campaign", segmentClosed: false, isFinal: false)

		#expect(transcript.heard == "Let's check the budget for the Coca-Cola ad campaign")
	}

	@Test
	func recognizerStoppingWhileHeldRestartsAndKeepsTheText() {
		var transcript = TranscriptAccumulator()

		let next = transcript.receive(text: "Where is the budget", segmentClosed: false, isFinal: true)
		#expect(next == .restartRecognition)

		_ = transcript.receive(text: "setting", segmentClosed: false, isFinal: false)
		#expect(transcript.heard == "Where is the budget setting")
	}

	@Test
	func silenceWhileHeldRestartsAndKeepsTheText() {
		var transcript = TranscriptAccumulator()

		_ = transcript.receive(text: "Let's check the budget", segmentClosed: false, isFinal: false)
		#expect(transcript.recognizerStoppedWithoutSpeech() == .restartRecognition)

		_ = transcript.receive(text: "for the campaign", segmentClosed: false, isFinal: false)
		#expect(transcript.heard == "Let's check the budget for the campaign")
	}

	@Test
	func silenceBeforeAnySpeechRestartsWithNothingHeard() {
		var transcript = TranscriptAccumulator()

		#expect(transcript.recognizerStoppedWithoutSpeech() == .restartRecognition)
		#expect(transcript.heard == "")

		_ = transcript.receive(text: "Hello", segmentClosed: false, isFinal: false)
		#expect(transcript.heard == "Hello")
	}

	@Test
	func listeningNeverFinishesWhileTheKeyIsHeld() {
		var transcript = TranscriptAccumulator()

		#expect(transcript.receive(text: "one", segmentClosed: true, isFinal: false) != .finish)
		#expect(transcript.receive(text: "two", segmentClosed: false, isFinal: true) != .finish)
		#expect(transcript.recognizerStoppedWithoutSpeech() != .finish)
		#expect(transcript.receive(text: "three", segmentClosed: false, isFinal: true) != .finish)
	}

	@Test
	func afterReleaseTheFinalResultFinishesWithEverything() {
		var transcript = TranscriptAccumulator()

		_ = transcript.receive(text: "Let's check the budget", segmentClosed: true, isFinal: false)
		_ = transcript.receive(text: "for the campaign", segmentClosed: false, isFinal: false)
		transcript.endAudio()

		let next = transcript.receive(text: "for the campaign now", segmentClosed: false, isFinal: true)
		#expect(next == .finish)
		#expect(transcript.heard == "Let's check the budget for the campaign now")
	}

	@Test
	func afterReleaseSilenceFinishesWithWhatWasHeard() {
		var transcript = TranscriptAccumulator()

		_ = transcript.receive(text: "Where is the budget", segmentClosed: false, isFinal: false)
		transcript.endAudio()

		#expect(transcript.recognizerStoppedWithoutSpeech() == .finish)
		#expect(transcript.heard == "Where is the budget")
	}
}
