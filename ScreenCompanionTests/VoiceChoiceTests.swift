import AVFoundation
import Synchronization
import Testing
@testable import ScreenCompanion

struct VoiceChoiceTests {
	private typealias Option = SystemSpeechOutput.VoiceOption

	private static let siriNora = Option(identifier: "com.apple.siri.natural.Nora", language: "en-US", quality: 2)
	private static let simonePremium = Option(identifier: "com.apple.ttsbundle.gryphon-neural_Simone_en-US_premium", language: "en-US", quality: 2)
	private static let samantha = Option(identifier: "com.apple.voice.compact.en-US.Samantha", language: "en-US", quality: 1)
	private static let amanIndia = Option(identifier: "com.apple.voice.Aman.premium", language: "en-IN", quality: 2)

	// The voice chosen in System Settings is used ahead of these (prefersAssistiveTechnologySettings);
	// this ranking is only Buddy's fallback.

	@Test
	func premiumVoiceWinsAtTheSameQuality() {
		// Measured on macOS 27.2: Siri's Nora and the Premium Simone download both report quality 2.
		let voices = [Self.siriNora, Self.samantha, Self.simonePremium, Self.amanIndia]
		#expect(SystemSpeechOutput.bestVoice(from: voices, language: "en-US") == Self.simonePremium)
	}

	@Test
	func orderInTheListDoesNotMatter() {
		let voices = [Self.simonePremium, Self.siriNora, Self.samantha]
		#expect(SystemSpeechOutput.bestVoice(from: voices, language: "en-US") == SystemSpeechOutput.bestVoice(from: voices.reversed(), language: "en-US"))
	}

	@Test
	func higherQualityStillWins() {
		let enhanced = Option(identifier: "com.apple.voice.enhanced.en-US.Ava", language: "en-US", quality: 2)
		#expect(SystemSpeechOutput.bestVoice(from: [Self.samantha, enhanced], language: "en-US") == enhanced)
	}

	@Test
	func siriVoiceIsChosenWhenItIsTheBest() {
		#expect(SystemSpeechOutput.bestVoice(from: [Self.samantha, Self.siriNora], language: "en-US") == Self.siriNora)
	}

	@Test
	func exactRegionIsPreferredOverABetterVoiceInAnotherRegion() {
		#expect(SystemSpeechOutput.bestVoice(from: [Self.amanIndia, Self.samantha], language: "en-US") == Self.samantha)
	}

	@Test
	func anotherRegionIsUsedWhenTheExactOneHasNoVoices() {
		#expect(SystemSpeechOutput.bestVoice(from: [Self.amanIndia], language: "en-GB") == Self.amanIndia)
	}

	@Test
	func noVoiceForTheLanguageGivesNil() {
		#expect(SystemSpeechOutput.bestVoice(from: [Self.samantha], language: "fr-FR") == nil)
	}

	@Test
	func noVoicesAtAllGivesNil() {
		#expect(SystemSpeechOutput.bestVoice(from: [], language: "en-US") == nil)
	}

	// MARK: - Loading the voice (real speech APIs)

	@Test
	func voiceThatIsNotInstalledFallsBackToTheLanguageDefault() {
		// For example a Premium voice deleted while Buddy runs, or one an older macOS doesn't have.
		let missing = Option(identifier: "com.apple.voice.premium.en-US.DoesNotExist", language: "en-US", quality: 3)
		let voice = SystemSpeechOutput.resolve(missing, language: "en-US")
		#expect(voice?.identifier != missing.identifier)
		#expect(voice?.language.hasPrefix("en") ?? true)
	}

	@Test
	func noChoiceFallsBackToTheLanguageDefault() {
		#expect(SystemSpeechOutput.resolve(nil, language: "en-US") != nil)
	}

	@Test
	func unknownLanguageGivesNilSoTheSystemVoiceIsUsed() {
		#expect(SystemSpeechOutput.resolve(nil, language: "zz-ZZ") == nil)
	}

	// MARK: - Speaking (synthesized silently into a buffer)

	@Test
	func speaksWithNoVoiceChosen() async {
		let utterance = SystemSpeechOutput.makeUtterance("Testing.", voice: nil)
		#expect(utterance.prefersAssistiveTechnologySettings)
		#expect(await Self.producesAudio(utterance))
	}

	@Test
	func speaksWithTheFallbackVoice() async {
		let voice = SystemSpeechOutput.resolve(nil, language: "en-US")
		#expect(await Self.producesAudio(SystemSpeechOutput.makeUtterance("Testing.", voice: voice)))
	}

	/// Synthesizes the utterance without playing it, and reports whether any audio came out.
	private static func producesAudio(_ utterance: AVSpeechUtterance) async -> Bool {
		let synthesizer = AVSpeechSynthesizer()
		let frames = Mutex(0)
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			let finished = Mutex(false)
			synthesizer.write(utterance) { buffer in
				guard let pcm = buffer as? AVAudioPCMBuffer else {
					return
				}
				frames.withLock { $0 += Int(pcm.frameLength) }
				// The last buffer is empty.
				if pcm.frameLength == 0, finished.withLock({ done in
					defer { done = true }
					return !done
				}) {
					continuation.resume()
				}
			}
		}
		return frames.withLock { $0 } > 0
	}
}
