import CoreGraphics
import Foundation

/// Turns the model's streamed text into answer text and an optional point guess.
///
/// The model writes its spoken answer, then optionally a final line `POINT: x,y | label`.
/// Text that might be the start of that line is held back until it's clear, so a `POINT` line
/// is never shown or spoken, even when it arrives split across chunks.
/// A leading `<think>…</think>` block, which some models emit, is dropped.
public struct AnswerStreamParser: Sendable {
	private static let pointPrefix = "POINT:"
	private static let thinkOpen = "<think>"
	private static let thinkClose = "</think>"

	/// Text received but not yet emitted.
	private var pending = ""
	private var insideThinkBlock = false
	private var sawAnyText = false
	private var point: PointGuess?

	public init() {}

	/// Feeds a chunk; returns events that are now certain.
	public mutating func add(_ chunk: String) -> [AnswerEvent] {
		pending += chunk
		return drain(final: false)
	}

	/// Call once the stream ends; returns whatever was held back.
	public mutating func finish() -> [AnswerEvent] {
		drain(final: true)
	}

	private mutating func drain(final: Bool) -> [AnswerEvent] {
		var events: [AnswerEvent] = []

		if stripThinkBlock(final: final) == false {
			return events
		}

		while let newline = pending.firstIndex(of: "\n") {
			let line = String(pending[..<newline])
			pending = String(pending[pending.index(after: newline)...])
			events += handleCompleteLine(line, followedByNewline: true)
		}

		if final {
			events += handleCompleteLine(pending, followedByNewline: false)
			pending = ""
			if let point {
				events.append(.point(point))
				self.point = nil
			}
			return events
		}

		// An incomplete last line: emit it unless it could still turn into a POINT line.
		if !Self.couldBePointLine(pending) {
			if !pending.isEmpty {
				events.append(.text(pending))
				sawAnyText = true
			}
			pending = ""
		}
		return events
	}

	/// Returns false while still waiting to see whether a think block ends.
	private mutating func stripThinkBlock(final: Bool) -> Bool {
		if !sawAnyText, !insideThinkBlock {
			let trimmed = pending.drop(while: \.isWhitespace)
			if trimmed.hasPrefix(Self.thinkOpen) {
				insideThinkBlock = true
			} else if !final, Self.thinkOpen.hasPrefix(String(trimmed)), !trimmed.isEmpty {
				return false
			}
		}
		if insideThinkBlock {
			guard let close = pending.range(of: Self.thinkClose) else {
				if final {
					pending = ""
				}
				return final
			}
			pending = String(pending[close.upperBound...].drop(while: \.isWhitespace))
			insideThinkBlock = false
		}
		return true
	}

	private mutating func handleCompleteLine(_ line: String, followedByNewline: Bool) -> [AnswerEvent] {
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		if trimmed.uppercased().hasPrefix(Self.pointPrefix) {
			point = Self.parsePoint(trimmed) ?? point
			return []
		}
		let text = followedByNewline ? line + "\n" : line
		guard !text.isEmpty else {
			return []
		}
		sawAnyText = true
		return [.text(text)]
	}

	static func couldBePointLine(_ partial: String) -> Bool {
		let trimmed = partial.drop(while: { $0 == " " || $0 == "\t" }).uppercased()
		if trimmed.isEmpty {
			return !partial.isEmpty
		}
		if trimmed.count <= pointPrefix.count {
			return pointPrefix.hasPrefix(trimmed)
		}
		return trimmed.hasPrefix(pointPrefix)
	}

	/// Parses `POINT: 812, 344 | Edit button`.
	static func parsePoint(_ line: String) -> PointGuess? {
		let body = line.dropFirst(pointPrefix.count)
		let parts = body.split(separator: "|", maxSplits: 1)
		guard let coordinates = parts.first else {
			return nil
		}
		let numbers = coordinates
			.split(separator: ",")
			.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
		guard numbers.count == 2, numbers.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
			return nil
		}
		let label = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
		return PointGuess(imagePoint: CGPoint(x: numbers[0], y: numbers[1]), label: label)
	}
}
