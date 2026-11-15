import Foundation

/// Decides, before any model call, whether a hold contained anything worth sending.
public enum SpeechFilter {
	public enum Verdict: Sendable, Equatable {
		/// Usable speech, trimmed.
		case speech(String)
		/// The microphone never picked up more than background noise.
		case silence
		/// There was sound, but no words beyond filler like "um".
		case nothingUsable
	}

	/// Mic level (0 to 1) below which a hold counts as silent.
	public static let silenceThreshold: Float = 0.05

	/// Sounds that are never words. Ambiguous fillers like "like" and "so" are left to the model.
	static let fillers: Set<String> = ["um", "umm", "uhm", "uh", "uhh", "erm", "er", "hmm", "hm", "mm", "mmm", "ah", "eh"]

	public static func classify(transcript: String, peakLevel: Float) -> Verdict {
		let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
		if hasRealWords(trimmed) {
			return .speech(trimmed)
		}
		if peakLevel < silenceThreshold {
			return .silence
		}
		return .nothingUsable
	}

	static func hasRealWords(_ text: String) -> Bool {
		let words = text
			.lowercased()
			.components(separatedBy: CharacterSet.letters.inverted)
			.filter { !$0.isEmpty }
		return words.contains { !fillers.contains($0) }
	}
}
