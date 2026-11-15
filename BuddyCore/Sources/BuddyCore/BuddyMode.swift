/// What a request does with your speech. The mode is sticky: it stays until you change it.
public enum BuddyMode: String, Sendable, CaseIterable {
	/// Ask a question about what's on screen; Buddy answers out loud and may point.
	case ask
	/// Dictate; Buddy cleans the text up and inserts it where your cursor is.
	case draft

	public var toggled: BuddyMode {
		switch self {
		case .ask:
			return .draft
		case .draft:
			return .ask
		}
	}

	public var title: String {
		switch self {
		case .ask:
			return "Ask"
		case .draft:
			return "Draft"
		}
	}
}
