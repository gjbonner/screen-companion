import CoreGraphics
import Foundation

/// An on-screen element found near the model's guess, as Accessibility describes it.
public struct SnapCandidate: Sendable, Equatable {
	/// The element's frame in AppKit global points.
	public var frame: CGRect
	public var role: String?
	/// The element's visible title or description, if it has one.
	public var label: String?

	public init(frame: CGRect, role: String?, label: String?) {
		self.frame = frame
		self.role = role
		self.label = label
	}
}

/// Where the mark points: a real element's exact frame, or the model's raw guess.
public enum PointTarget: Sendable, Equatable {
	/// Highlight this frame (AppKit global points).
	case element(CGRect)
	/// No plausible element was found; draw a ring at this point (AppKit global points).
	case guess(CGPoint)
}

/// Decides whether to replace the model's guess with a real element's frame, and which element (ADR 0004).
///
/// A candidate is plausible when it's a real, reasonably sized element on the captured display, close to the guess,
/// and not a structural container. Among plausible candidates, Buddy prefers, in order: one matching the model's label,
/// the nearest, a control over plain text or images, and the smallest.
public enum SnapGuardrails {
	/// How far from the guess an element may be, in points. The spike's near-miss was about 20 pt.
	public static let maxDistance: CGFloat = 40
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

	public static func target(guess: CGPoint, label: String, candidates: [SnapCandidate], displayFrame: CGRect) -> PointTarget {
		let best = candidates
			.filter { isPlausible($0, guess: guess, displayFrame: displayFrame) }
			.min { isPreferred($0, over: $1, guess: guess, label: label) }
		guard let best else {
			return .guess(guess)
		}
		return .element(best.frame)
	}

	static func isPlausible(_ candidate: SnapCandidate, guess: CGPoint, displayFrame: CGRect) -> Bool {
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
		return distance(from: guess, to: frame) <= maxDistance
	}

	/// Whether `a` should be chosen over `b`.
	private static func isPreferred(_ a: SnapCandidate, over b: SnapCandidate, guess: CGPoint, label: String) -> Bool {
		let aMatches = labelsMatch(label, a.label ?? "")
		let bMatches = labelsMatch(label, b.label ?? "")
		if aMatches != bMatches {
			return aMatches
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

	/// Whether the model's label (e.g. "Run button") refers to an element with this label (e.g. "Run").
	/// At least half the words of the shorter label must appear in the other, ignoring case and kind words.
	static func labelsMatch(_ modelLabel: String, _ elementLabel: String) -> Bool {
		let model = words(in: modelLabel)
		let element = words(in: elementLabel)
		guard !model.isEmpty, !element.isEmpty else {
			return false
		}
		let shared = model.intersection(element).count
		return Double(shared) >= Double(min(model.count, element.count)) / 2
	}

	private static func words(in label: String) -> Set<String> {
		let words = label.lowercased()
			.components(separatedBy: CharacterSet.alphanumerics.inverted)
			.filter { !$0.isEmpty && !ignoredLabelWords.contains($0) }
		return Set(words)
	}
}
