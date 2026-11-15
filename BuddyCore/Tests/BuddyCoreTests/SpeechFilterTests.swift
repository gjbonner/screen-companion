import Testing
@testable import BuddyCore

struct SpeechFilterTests {
	@Test
	func realWordsAreSpeech() {
		#expect(SpeechFilter.classify(transcript: "  where is the budget? ", peakLevel: 0.4) == .speech("where is the budget?"))
	}

	@Test
	func wordsCountEvenWithFillerAround() {
		#expect(SpeechFilter.classify(transcript: "um, budget", peakLevel: 0.4) == .speech("um, budget"))
	}

	@Test
	func quietHoldWithNoWordsIsSilence() {
		#expect(SpeechFilter.classify(transcript: "", peakLevel: 0.01) == .silence)
	}

	@Test
	func soundWithNoWordsIsNothingUsable() {
		#expect(SpeechFilter.classify(transcript: "", peakLevel: 0.3) == .nothingUsable)
	}

	@Test(arguments: ["um", "Uh.", "um, uh", "Hmm... erm", "mm-hmm"])
	func fillerOnlyIsNothingUsable(_ transcript: String) {
		#expect(SpeechFilter.classify(transcript: transcript, peakLevel: 0.3) == .nothingUsable)
	}

	@Test
	func ambiguousFillersAreLeftAsSpeech() {
		#expect(SpeechFilter.classify(transcript: "like", peakLevel: 0.3) == .speech("like"))
	}
}
