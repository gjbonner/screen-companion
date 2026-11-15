/// The phase of the current request. Every piece of Buddy's UI reads this; only the coordinator changes it.
public enum BuddyState: Sendable, Equatable {
	/// Nothing happening. Buddy rests in the menu bar.
	case idle
	/// The hotkey is held (or listening was started from the menu); shows the live transcript and mic level.
	case listening(transcript: String, level: Float)
	/// Speech has ended; Buddy is working on the answer or the cleaned-up text.
	case thinking
	/// An Ask answer is arriving and being spoken. `spokenLength` is how many characters of `text`
	/// have been spoken or are being spoken now, for highlighting in the answer card.
	case answering(text: String, point: PointGuess?, spokenLength: Int)
	/// A short notice in the pill, such as a missing permission or "Copied".
	case message(BuddyMessage)

	/// True while a request is in progress (anything other than idle or a notice).
	public var isBusy: Bool {
		switch self {
		case .listening, .thinking, .answering:
			return true
		case .idle, .message:
			return false
		}
	}
}

/// A short notice shown in the pill.
public struct BuddyMessage: Sendable, Equatable {
	public enum Kind: Sendable, Equatable {
		/// Something worth knowing, like "Copied — paste with ⌘V".
		case info
		/// Something stopped the request, like a missing permission.
		case problem
	}

	public var text: String
	public var kind: Kind

	public init(_ text: String, kind: Kind) {
		self.text = text
		self.kind = kind
	}
}

/// An error that carries the sentence to show the user.
public struct BuddyError: Error, Sendable, Equatable {
	public var userMessage: String

	public init(_ userMessage: String) {
		self.userMessage = userMessage
	}
}
