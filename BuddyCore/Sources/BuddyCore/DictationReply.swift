import Foundation

/// Turns the cleanup model's reply into the text Draft inserts.
public enum DictationReply {
	private static let thinkOpen = "<think>"
	private static let thinkClose = "</think>"
	private static let dictationOpen = "<dictation>"
	private static let dictationClose = "</dictation>"

	/// Drops a leading `<think>…</think>` block, the `<dictation>` tags the dictation was sent in if the model
	/// echoed them, and surrounding whitespace. An unfinished think block means there's no text yet, so it gives "".
	public static func text(from reply: String) -> String {
		var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
		if text.hasPrefix(thinkOpen) {
			guard let end = text.range(of: thinkClose) else {
				return ""
			}
			text = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
		}
		if text.hasPrefix(dictationOpen), text.hasSuffix(dictationClose) {
			text = String(text.dropFirst(dictationOpen.count).dropLast(dictationClose.count))
				.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		return text
	}
}
