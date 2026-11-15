import CoreGraphics
import Foundation

/// An on-screen element or piece of text found for the model's label.
public struct SnapCandidate: Sendable, Equatable {
	/// The element's frame in AppKit global points.
	public var frame: CGRect
	/// The Accessibility role, or nil for text found in the screenshot.
	public var role: String?
	/// The element's name or text, if it has one.
	public var label: String?

	public init(frame: CGRect, role: String?, label: String?) {
		self.frame = frame
		self.role = role
		self.label = label
	}
}

/// Where the mark points: a real element's exact frame, in AppKit global points.
public struct PointTarget: Sendable, Equatable {
	public var frame: CGRect

	public init(frame: CGRect) {
		self.frame = frame
	}
}

/// Decides where to point, or not to point at all (ADR 0004).
///
/// The model reliably names the right element but places it badly: 60–400 pt off in testing. So only an element
/// whose label matches the model's counts, anywhere on the display; the guess just breaks ties between matches.
/// If nothing matches, Buddy doesn't point: a confident highlight on the wrong element is worse than none.
public enum SnapGuardrails {
	/// Elements thinner than this are dividers or decoration, not things to point at.
	public static let minSide: CGFloat = 4
	/// Elements covering more than this share of the display are panels or content areas, not targets.
	public static let maxDisplayFraction: CGFloat = 0.25

	/// Roles that hold other elements rather than being something to point at.
	static let structuralRoles: Set<String> = [
		"AXWindow", "AXApplication", "AXWebArea", "AXScrollArea", "AXSplitGroup",
		"AXToolbar", "AXLayoutArea", "AXUnknown", "AXSheet", "AXDrawer", "AXMenuBar",
	]
	/// Roles of things the user acts on, preferred over the text or image inside them.
	static let controlRoles: Set<String> = [
		"AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXLink",
		"AXTextField", "AXTextArea", "AXComboBox", "AXSlider", "AXIncrementor", "AXDisclosureTriangle",
		"AXMenuItem", "AXMenuBarItem", "AXRow", "AXCell", "AXColorWell", "AXSegmentedControl", "AXTab",
	]
	/// Words the model adds to describe an element's kind, which the element's own label won't contain.
	static let ignoredLabelWords: Set<String> = [
		"button", "icon", "field", "box", "menu", "tab", "link", "toggle", "checkbox", "dropdown", "bar", "item",
		"the", "a", "an", "or", "of", "to", "in", "on", "for", "and",
	]
	/// Words for the same icon: what it looks like, and what apps name it. The first word of each group stands for all.
	static let synonymGroups: [[String]] = [
		["play", "run", "start"],
		["settings", "preferences", "gear", "cog", "options"],
		["delete", "trash", "remove", "bin"],
		["add", "plus", "new", "create"],
		["search", "find", "magnifier", "magnifying"],
		["edit", "pencil"],
		["refresh", "reload"],
		["back", "previous"],
		["forward", "next"],
		["more", "ellipsis", "overflow"],
		["close", "dismiss"],
	]
	private static let canonicalWord: [String: String] = {
		var map: [String: String] = [:]
		for group in synonymGroups {
			for word in group {
				map[word] = group[0]
			}
		}
		return map
	}()

	/// The matching element to point at, or nil if none of the candidates matches the model's label.
	/// Among matches: the one covering most of the label's words, then the nearest to the guess,
	/// then a control over the text inside it, then the smallest.
	public static func target(guess: CGPoint, label: String, candidates: [SnapCandidate], displayFrame: CGRect) -> PointTarget? {
		let best = candidates
			.filter { isPlausible($0, label: label, displayFrame: displayFrame) }
			.min { isPreferred($0, over: $1, guess: guess, label: label) }
		return best.map { PointTarget(frame: $0.frame) }
	}

	static func isPlausible(_ candidate: SnapCandidate, label: String, displayFrame: CGRect) -> Bool {
		let frame = candidate.frame
		if let role = candidate.role, structuralRoles.contains(role) {
			return false
		}
		guard frame.width >= minSide, frame.height >= minSide else {
			return false
		}
		guard frame.width * frame.height <= displayFrame.width * displayFrame.height * maxDisplayFraction else {
			return false
		}
		guard displayFrame.contains(CGPoint(x: frame.midX, y: frame.midY)) else {
			return false
		}
		return labelsMatch(label, candidate.label ?? "")
	}

	/// Whether `a` should be chosen over `b`.
	private static func isPreferred(_ a: SnapCandidate, over b: SnapCandidate, guess: CGPoint, label: String) -> Bool {
		let aScore = matchScore(label, a.label ?? "") ?? 0
		let bScore = matchScore(label, b.label ?? "") ?? 0
		if aScore != bScore {
			return aScore > bScore
		}
		let aDistance = distance(from: guess, to: a.frame)
		let bDistance = distance(from: guess, to: b.frame)
		if aDistance != bDistance {
			return aDistance < bDistance
		}
		let aIsControl = a.role.map(controlRoles.contains) ?? false
		let bIsControl = b.role.map(controlRoles.contains) ?? false
		if aIsControl != bIsControl {
			return aIsControl
		}
		return a.frame.width * a.frame.height < b.frame.width * b.frame.height
	}

	/// Distance from a point to the nearest edge of a rect, or 0 if the point is inside it.
	static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
		let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
		let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
		return (dx * dx + dy * dy).squareRoot()
	}

	/// Whether the model's label (e.g. "Run button", "play icon") refers to an element with this label (e.g. "Run").
	///
	/// Ignoring case, kind words and synonyms: at least half the words of the shorter label must appear in the other,
	/// and they must include the model label's longest word, so "README.md" doesn't match "LICENSE.md" on "md" alone.
	public static func labelsMatch(_ modelLabel: String, _ elementLabel: String) -> Bool {
		matchScore(modelLabel, elementLabel) != nil
	}

	/// The share of the model label's words found in the element's label, or nil if it isn't a match.
	static func matchScore(_ modelLabel: String, _ elementLabel: String) -> Double? {
		let model = Set(words(in: modelLabel).map(canonical))
		let element = Set(words(in: elementLabel).map(canonical))
		guard !model.isEmpty, !element.isEmpty else {
			return nil
		}
		let shared = model.intersection(element)
		guard Double(shared.count) >= Double(min(model.count, element.count)) / 2 else {
			return nil
		}
		let longest = model.map(\.count).max() ?? 0
		guard shared.contains(where: { $0.count == longest }) else {
			return nil
		}
		return Double(shared.count) / Double(model.count)
	}

	/// The part of `text` the model's label refers to, widened to whole words, so recognized text can be boxed
	/// precisely: "README" in "README.md Initial commit" gives "README.md". Nil if the labels don't match.
	public static func labelRange(of modelLabel: String, in text: String) -> Range<String.Index>? {
		guard labelsMatch(modelLabel, text) else {
			return nil
		}
		var start: String.Index?
		var end: String.Index?
		for word in words(in: modelLabel) {
			for variant in variants(of: word) {
				guard let found = text.range(of: variant, options: .caseInsensitive) else {
					continue
				}
				start = min(start ?? found.lowerBound, found.lowerBound)
				end = max(end ?? found.upperBound, found.upperBound)
			}
		}
		guard var start, var end else {
			return nil
		}
		while start > text.startIndex, !text[text.index(before: start)].isWhitespace {
			start = text.index(before: start)
		}
		while end < text.endIndex, !text[end].isWhitespace {
			end = text.index(after: end)
		}
		return start..<end
	}

	private static func words(in label: String) -> [String] {
		label.lowercased()
			.components(separatedBy: CharacterSet.alphanumerics.inverted)
			.filter { !$0.isEmpty && !ignoredLabelWords.contains($0) }
	}

	private static func canonical(_ word: String) -> String {
		canonicalWord[word] ?? word
	}

	/// The word and its synonyms.
	private static func variants(of word: String) -> [String] {
		synonymGroups.first { $0.contains(word) } ?? [word]
	}
}
