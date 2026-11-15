import CoreGraphics
import Testing
@testable import BuddyCore

struct SnapGuardrailsTests {
	/// A 1512×982 laptop display.
	private static let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

	// MARK: - Snapping or not

	@Test
	func guessInsideAButtonSnapsToIt() {
		let run = Self.button(CGRect(x: 180, y: 930, width: 28, height: 28), label: "Run")
		let target = Self.target(guess: CGPoint(x: 190, y: 940), label: "Run button", candidates: [run])
		#expect(target == .element(run.frame))
	}

	@Test
	func noCandidatesPointsAtTheGuess() {
		let guess = CGPoint(x: 400, y: 400)
		#expect(Self.target(guess: guess, label: "Budget", candidates: []) == .guess(guess))
	}

	@Test
	func elementFartherThanTheLimitIsIgnored() {
		let far = Self.button(CGRect(x: 500, y: 400, width: 40, height: 20), label: "Save")
		let guess = CGPoint(x: 500 - SnapGuardrails.maxDistance - 1, y: 410)
		#expect(Self.target(guess: guess, label: "Save", candidates: [far]) == .guess(guess))
	}

	@Test
	func elementJustWithinTheLimitSnaps() {
		let near = Self.button(CGRect(x: 500, y: 400, width: 40, height: 20), label: "Save")
		let guess = CGPoint(x: 500 - SnapGuardrails.maxDistance + 1, y: 410)
		#expect(Self.target(guess: guess, label: "Save", candidates: [near]) == .element(near.frame))
	}

	@Test
	func elementLargerThanAQuarterOfTheDisplayIsIgnored() {
		let panel = SnapCandidate(frame: CGRect(x: 0, y: 0, width: 900, height: 600), role: "AXButton", label: nil)
		let guess = CGPoint(x: 100, y: 100)
		#expect(Self.target(guess: guess, label: "Panel", candidates: [panel]) == .guess(guess))
	}

	@Test
	func tinyElementIsIgnored() {
		let sliver = SnapCandidate(frame: CGRect(x: 100, y: 100, width: 2, height: 30), role: "AXSplitter", label: nil)
		let guess = CGPoint(x: 101, y: 110)
		#expect(Self.target(guess: guess, label: "Divider", candidates: [sliver]) == .guess(guess))
	}

	@Test(arguments: ["AXWindow", "AXApplication", "AXWebArea", "AXScrollArea", "AXSplitGroup", "AXToolbar", "AXLayoutArea", "AXUnknown"])
	func structuralContainersAreIgnored(_ role: String) {
		let container = SnapCandidate(frame: CGRect(x: 100, y: 100, width: 300, height: 200), role: role, label: nil)
		let guess = CGPoint(x: 150, y: 150)
		#expect(Self.target(guess: guess, label: "Something", candidates: [container]) == .guess(guess))
	}

	@Test
	func elementOnAnotherDisplayIsIgnored() {
		// The element's center is off the captured display, e.g. a window spilling onto a second monitor.
		let offDisplay = Self.button(CGRect(x: 1500, y: 400, width: 60, height: 20), label: "Next")
		let guess = CGPoint(x: 1505, y: 410)
		#expect(Self.target(guess: guess, label: "Next", candidates: [offDisplay]) == .guess(guess))
	}

	// MARK: - Choosing between elements

	@Test
	func nearMissPrefersTheElementMatchingTheLabel() {
		// The spike's case: the guess landed between the sidebar toggle and the Run button.
		let sidebar = Self.button(CGRect(x: 150, y: 930, width: 28, height: 28), label: "Hide Navigator")
		let run = Self.button(CGRect(x: 185, y: 930, width: 28, height: 28), label: "Run")
		let target = Self.target(guess: CGPoint(x: 172, y: 940), label: "Run button", candidates: [sidebar, run])
		#expect(target == .element(run.frame))
	}

	@Test
	func withoutALabelMatchTheNearestWins() {
		let left = Self.button(CGRect(x: 100, y: 100, width: 30, height: 30), label: "Back")
		let right = Self.button(CGRect(x: 160, y: 100, width: 30, height: 30), label: "Forward")
		let target = Self.target(guess: CGPoint(x: 140, y: 115), label: "Toolbar arrow", candidates: [left, right])
		#expect(target == .element(left.frame))
	}

	@Test
	func controlWinsOverTheTextInsideIt() {
		let text = SnapCandidate(frame: CGRect(x: 210, y: 405, width: 30, height: 12), role: "AXStaticText", label: "Save")
		let button = Self.button(CGRect(x: 200, y: 400, width: 60, height: 22), label: "Save")
		let target = Self.target(guess: CGPoint(x: 220, y: 410), label: "Save button", candidates: [text, button])
		#expect(target == .element(button.frame))
	}

	@Test
	func amongEqualControlsTheSmallestWins() {
		let row = SnapCandidate(frame: CGRect(x: 0, y: 300, width: 300, height: 24), role: "AXRow", label: nil)
		let checkbox = SnapCandidate(frame: CGRect(x: 10, y: 304, width: 16, height: 16), role: "AXCheckBox", label: nil)
		let target = Self.target(guess: CGPoint(x: 15, y: 310), label: "Checkbox", candidates: [row, checkbox])
		#expect(target == .element(checkbox.frame))
	}

	@Test
	func implausibleLabelMatchLosesToAPlausibleElement() {
		// The matching element is too far away, so the nearby one is used.
		let farRun = Self.button(CGRect(x: 600, y: 600, width: 28, height: 28), label: "Run")
		let near = Self.button(CGRect(x: 100, y: 100, width: 28, height: 28), label: "Stop")
		let target = Self.target(guess: CGPoint(x: 110, y: 110), label: "Run button", candidates: [farRun, near])
		#expect(target == .element(near.frame))
	}

	// MARK: - Label matching

	@Test(arguments: [
		("Run button", "Run"),
		("Save", "Save As…"),
		("Ask Google search bar", "Search Google or type a URL"),
		("the Budget field", "Budget"),
		("DAILY BUDGET", "Daily budget"),
	])
	func labelsThatMatch(_ modelLabel: String, _ elementLabel: String) {
		#expect(SnapGuardrails.labelsMatch(modelLabel, elementLabel))
	}

	@Test(arguments: [
		("Run button", "Stop"),
		("Budget", ""),
		("button", "OK"),
		("Campaign name", "Ad set budget"),
	])
	func labelsThatDoNotMatch(_ modelLabel: String, _ elementLabel: String) {
		#expect(!SnapGuardrails.labelsMatch(modelLabel, elementLabel))
	}

	// MARK: - Helpers

	private static func button(_ frame: CGRect, label: String) -> SnapCandidate {
		SnapCandidate(frame: frame, role: "AXButton", label: label)
	}

	private static func target(guess: CGPoint, label: String, candidates: [SnapCandidate]) -> PointTarget {
		SnapGuardrails.target(guess: guess, label: label, candidates: candidates, displayFrame: display)
	}
}
