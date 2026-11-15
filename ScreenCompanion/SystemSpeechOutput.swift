import AVFoundation
import BuddyCore

/// Speaks with Apple's built-in voices, one sentence at a time, using the best installed voice for the user's language.
@MainActor
final class SystemSpeechOutput: NSObject, SpeechOutput {
	private let synthesizer = AVSpeechSynthesizer()
	private var waiting: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
	private lazy var voice = Self.bestVoice()

	override init() {
		super.init()
		synthesizer.delegate = self
	}

	func speak(_ text: String) async {
		guard !Task.isCancelled else {
			return
		}
		let utterance = AVSpeechUtterance(string: text)
		utterance.voice = voice
		await withCheckedContinuation { continuation in
			waiting[ObjectIdentifier(utterance)] = continuation
			synthesizer.speak(utterance)
		}
	}

	func stop() async {
		synthesizer.stopSpeaking(at: .immediate)
		let pending = waiting.values
		waiting.removeAll()
		for continuation in pending {
			continuation.resume()
		}
	}

	fileprivate func utteranceEnded(_ id: ObjectIdentifier) {
		waiting.removeValue(forKey: id)?.resume()
	}

	/// Premium and Enhanced voices sound far better than the defaults when the user has downloaded them.
	private static func bestVoice() -> AVSpeechSynthesisVoice? {
		let language = AVSpeechSynthesisVoice.currentLanguageCode()
		let languagePrefix = String(language.prefix(2))
		let voices = AVSpeechSynthesisVoice.speechVoices()
		let exact = voices.filter { $0.language == language }
		let candidates = exact.isEmpty ? voices.filter { $0.language.hasPrefix(languagePrefix) } : exact
		let best = candidates.max { $0.quality.rawValue < $1.quality.rawValue }
		return best ?? AVSpeechSynthesisVoice(language: language)
	}
}

extension SystemSpeechOutput: AVSpeechSynthesizerDelegate {
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
