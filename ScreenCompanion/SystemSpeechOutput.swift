import AVFoundation
import BuddyCore

/// Speaks with Apple's built-in voices, one sentence at a time, using the best installed voice for the user's language.
@MainActor
final class SystemSpeechOutput: NSObject, SpeechOutput {
	private let synthesizer = AVSpeechSynthesizer()
	private var waiting: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
	#if DEBUG
	/// When each utterance was asked for, to log how long the voice takes to start.
	private var requestedAt: [ObjectIdentifier: ContinuousClock.Instant] = [:]
	#endif

	override init() {
		super.init()
		synthesizer.delegate = self
	}

	func speak(_ text: String) async {
		guard !Task.isCancelled else {
			return
		}
		#if DEBUG
		let requested = ContinuousClock.now
		#endif
		// Chosen each time, so a voice downloaded while Buddy runs is used straight away. Listing voices is quick.
		let utterance = Self.makeUtterance(text, voice: Self.bestVoice())
		#if DEBUG
		requestedAt[ObjectIdentifier(utterance)] = requested
		#endif
		await withCheckedContinuation { continuation in
			waiting[ObjectIdentifier(utterance)] = continuation
			synthesizer.speak(utterance)
		}
	}

	func stop() async {
		synthesizer.stopSpeaking(at: .immediate)
		let pending = waiting.values
		waiting.removeAll()
		#if DEBUG
		requestedAt.removeAll()
		#endif
		for continuation in pending {
			continuation.resume()
		}
	}

	fileprivate func utteranceEnded(_ id: ObjectIdentifier) {
		#if DEBUG
		requestedAt.removeValue(forKey: id)
		#endif
		waiting.removeValue(forKey: id)?.resume()
	}

	#if DEBUG
	fileprivate func utteranceStarted(_ id: ObjectIdentifier, at startedAt: ContinuousClock.Instant) {
		guard let requested = requestedAt.removeValue(forKey: id) else {
			return
		}
		Log.timing.info("Voice started \(Log.milliseconds(startedAt - requested)) ms after a sentence was handed to it")
	}
	#endif

	/// Premium and Enhanced voices sound far better than the defaults when the user has downloaded them.
	private static func bestVoice() -> AVSpeechSynthesisVoice? {
		let language = AVSpeechSynthesisVoice.currentLanguageCode()
		let voices = AVSpeechSynthesisVoice.speechVoices()
		let options = voices.map { VoiceOption(identifier: $0.identifier, language: $0.language, quality: $0.quality.rawValue) }
		return resolve(bestVoice(from: options, language: language), language: language)
	}

	/// The voice for `choice`; if it's missing or can't be loaded, the language's default voice; failing that, nil,
	/// which speaks with the system voice. Never crashes over a missing voice, on any macOS version.
	nonisolated static func resolve(_ choice: VoiceOption?, language: String) -> AVSpeechSynthesisVoice? {
		if let choice, let voice = AVSpeechSynthesisVoice(identifier: choice.identifier) {
			return voice
		}
		return AVSpeechSynthesisVoice(language: language)
	}

	/// The voice (and rate) chosen in System Settings › Accessibility wins. Without one, `voice` is used, and if
	/// that's nil too, the system's default voice: every case speaks, none crashes.
	nonisolated static func makeUtterance(_ text: String, voice: AVSpeechSynthesisVoice?) -> AVSpeechUtterance {
		let utterance = AVSpeechUtterance(string: text)
		utterance.prefersAssistiveTechnologySettings = true
		utterance.voice = voice
		return utterance
	}

	struct VoiceOption: Equatable {
		var identifier: String
		var language: String
		/// `AVSpeechSynthesisVoiceQuality`'s raw value: 1 default, 2 enhanced, 3 premium.
		var quality: Int
	}

	/// Buddy's fallback when no voice is set in System Settings: for the user's language (exactly, else the same
	/// language in another region), the highest quality, then a Premium download over others of the same quality.
	/// The list's order doesn't affect the choice.
	nonisolated static func bestVoice(from voices: [VoiceOption], language: String) -> VoiceOption? {
		let languagePrefix = String(language.prefix(2))
		let exact = voices.filter { $0.language == language }
		let candidates = exact.isEmpty ? voices.filter { $0.language.hasPrefix(languagePrefix) } : exact
		func rank(_ voice: VoiceOption) -> (Int, Int, String) {
			// The identifier only breaks remaining ties, so the result is the same whatever order macOS lists voices in.
			(voice.quality, voice.identifier.lowercased().contains("premium") ? 1 : 0, voice.identifier)
		}
		return candidates.max { rank($0) < rank($1) }
	}
}

extension SystemSpeechOutput: AVSpeechSynthesizerDelegate {
	#if DEBUG
	nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
		let id = ObjectIdentifier(utterance)
		let startedAt = ContinuousClock.now
		Task { @MainActor in
			self.utteranceStarted(id, at: startedAt)
		}
	}
	#endif

	nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
		let id = ObjectIdentifier(utterance)
		Task { @MainActor in
			self.utteranceEnded(id)
		}
	}

	nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
		let id = ObjectIdentifier(utterance)
		Task { @MainActor in
			self.utteranceEnded(id)
		}
	}
}
