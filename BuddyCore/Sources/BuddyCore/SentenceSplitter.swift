import Foundation

/// Cuts streamed text into complete sentences, so speech can start before the whole answer has arrived.
///
/// A sentence ends at `.`, `!` or `?` followed by whitespace, or at a line break.
/// Decimals ("$3.50") never split, because no whitespace follows the period, and common abbreviations
/// ("e.g.", "Mr.") don't either.
public struct SentenceSplitter: Sendable {
	private static let abbreviations: Set<String> = ["e.g.", "i.e.", "etc.", "vs.", "mr.", "mrs.", "ms.", "dr.", "st.", "approx."]

	private var buffer = ""

	public init() {}

	/// Feeds text; returns the sentences that are now complete.
	public mutating func add(_ text: String) -> [String] {
		buffer += text
		var sentences: [String] = []
		var searchStart = buffer.startIndex

		while let end = nextBoundary(from: searchStart) {
			let sentence = buffer[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
			buffer = String(buffer[end...])
			searchStart = buffer.startIndex
			if !sentence.isEmpty {
				sentences.append(sentence)
			}
		}
		return sentences
	}

	/// Returns whatever is left once the stream ends.
	public mutating func finish() -> [String] {
		let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
		buffer = ""
		return rest.isEmpty ? [] : [rest]
	}

	/// The index just after a sentence boundary, if one is certain yet.
	private func nextBoundary(from start: String.Index) -> String.Index? {
		var index = start
		while index < buffer.endIndex {
			let character = buffer[index]
			let next = buffer.index(after: index)
			if character == "\n" {
				return next
			}
			if ".!?".contains(character) {
				// Need to see the next character before deciding.
				guard next < buffer.endIndex else {
					return nil
				}
				let following = buffer[next]
				if following.isWhitespace, !(character == "." && endsWithAbbreviation(upTo: next)) {
					return next
				}
			}
			index = next
		}
		return nil
	}

	private func endsWithAbbreviation(upTo end: String.Index) -> Bool {
		let prefix = buffer[..<end]
		let lastWord = prefix.split(whereSeparator: \.isWhitespace).last.map { $0.lowercased() } ?? ""
		return Self.abbreviations.contains(lastWord)
	}
}
