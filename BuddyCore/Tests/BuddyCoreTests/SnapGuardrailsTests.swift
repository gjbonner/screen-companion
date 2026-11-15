import CoreGraphics
import Testing
@testable import BuddyCore

struct SnapGuardrailsTests {
	/// A 1512×982 laptop display.
	private static let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

	// MARK: - Pointing only at a match

	@Test
	func matchingElementUnderTheGuessIsChosen() {
		let run = Self.button(CGRect(x: 180, y: 930, width: 28, height: 28), label: "Run")
		let target = Self.target(guess: CGPoint(x: 190, y: 940), label: "Run button", candidates: [run])
		#expect(target == PointTarget(frame: run.frame))
	}

	@Test
	func matchFarFromTheGuessIsStillChosen() {
		// Measured in Xcode: guesses for Run landed up to 400 pt away.
		let run = Self.button(CGRect(x: 212, y: 940, width: 31, height: 31), label: "Run")
		let target = Self.target(guess: CGPoint(x: 640, y: 950), label: "Run button", candidates: [run])
		#expect(target == PointTarget(frame: run.frame))
	}

	@Test
	func noCandidatesMeansNoPoint() {
		#expect(Self.target(guess: CGPoint(x: 400, y: 400), label: "Budget", candidates: []) == nil)
	}

	@Test
	func nonMatchingElementUnderTheGuessIsNotChosen() {
		// A false positive is worse than not pointing: the Help menu under a guess for "Run button" stays unhighlighted.
		let help = SnapCandidate(frame: CGRect(x: 600, y: 950, width: 49, height: 30), role: "AXMenuBarItem", label: "Help")
		#expect(Self.target(guess: CGPoint(x: 620, y: 960), label: "Run button", candidates: [help]) == nil)
	}

	@Test
	func unnamedElementUnderTheGuessIsNotChosen() {
		let unnamed = SnapCandidate(frame: CGRect(x: 100, y: 100, width: 30, height: 30), role: "AXButton", label: nil)
		#expect(Self.target(guess: CGPoint(x: 110, y: 110), label: "Settings", candidates: [unnamed]) == nil)
	}

	@Test
	func matchElsewhereWinsOverANonMatchingElementUnderTheGuess() {
		let stop = Self.button(CGRect(x: 100, y: 100, width: 28, height: 28), label: "Stop")
		let run = Self.button(CGRect(x: 600, y: 600, width: 28, height: 28), label: "Run")
		let target = Self.target(guess: CGPoint(x: 110, y: 110), label: "Run button", candidates: [stop, run])
		#expect(target == PointTarget(frame: run.frame))
	}

	// MARK: - Implausible matches

	@Test
	func matchLargerThanAQuarterOfTheDisplayIsIgnored() {
		let panel = SnapCandidate(frame: CGRect(x: 0, y: 0, width: 900, height: 600), role: "AXGroup", label: "Campaigns")
		#expect(Self.target(guess: CGPoint(x: 100, y: 100), label: "Campaigns", candidates: [panel]) == nil)
	}

	@Test
	func tinyMatchIsIgnored() {
		let sliver = SnapCandidate(frame: CGRect(x: 100, y: 100, width: 2, height: 30), role: "AXSplitter", label: "Divider")
		#expect(Self.target(guess: CGPoint(x: 101, y: 110), label: "Divider", candidates: [sliver]) == nil)
	}

	@Test(arguments: ["AXWindow", "AXApplication", "AXWebArea", "AXScrollArea", "AXSplitGroup", "AXToolbar", "AXLayoutArea", "AXUnknown"])
	func structuralContainersAreIgnoredEvenWhenTheirNameMatches(_ role: String) {
		let container = SnapCandidate(frame: CGRect(x: 100, y: 100, width: 300, height: 200), role: role, label: "Inbox")
		#expect(Self.target(guess: CGPoint(x: 150, y: 150), label: "Inbox", candidates: [container]) == nil)
	}

	@Test
	func matchOffTheCapturedDisplayIsIgnored() {
		// The element's center is off the captured display, e.g. a window spilling onto a second monitor.
		let elsewhere = Self.button(CGRect(x: 1500, y: 400, width: 60, height: 20), label: "Next")
		#expect(Self.target(guess: CGPoint(x: 1505, y: 410), label: "Next", candidates: [elsewhere]) == nil)
	}

	// MARK: - Choosing between matches

	@Test
	func nearestOfSeveralMatchesWins() {
		// Measured on GitHub: "README" appears as the file, the README tab and the sidebar link. The guess was
		// about 200 pt above the file, which is still the nearest of the three.
		let file = SnapCandidate(frame: CGRect(x: 387, y: 600, width: 82, height: 17), role: nil, label: "README.md")
		let tab = SnapCandidate(frame: CGRect(x: 385, y: 539, width: 60, height: 17), role: nil, label: "README")
		let sidebar = SnapCandidate(frame: CGRect(x: 1312, y: 925, width: 52, height: 17), role: nil, label: "Readme")
		let target = Self.target(guess: CGPoint(x: 376, y: 810), label: "README", candidates: [sidebar, tab, file])
		#expect(target == PointTarget(frame: file.frame))
	}

	@Test
	func readmeIsNotConfusedWithLicenseByTheSharedExtension() {
		// Measured on GitHub: the guess was nearer LICENSE.md, and "md" alone made it match "README.md".
		let license = SnapCandidate(frame: CGRect(x: 383, y: 440, width: 88, height: 17), role: nil, label: "LICENSE.md")
		let readme = SnapCandidate(frame: CGRect(x: 387, y: 399, width: 82, height: 17), role: nil, label: "README.md")
		let guess = CGPoint(x: 473, y: 836)
		#expect(Self.target(guess: guess, label: "README.md", candidates: [license, readme]) == PointTarget(frame: readme.frame))
		#expect(Self.target(guess: guess, label: "README.md", candidates: [license]) == nil)
	}

	@Test
	func fullerMatchWinsOverANearerPartialOne() {
		let partial = Self.button(CGRect(x: 100, y: 100, width: 60, height: 20), label: "Budget")
		let full = Self.button(CGRect(x: 800, y: 600, width: 100, height: 20), label: "Daily budget")
		let target = Self.target(guess: CGPoint(x: 110, y: 110), label: "Daily budget", candidates: [partial, full])
		#expect(target == PointTarget(frame: full.frame))
	}

	@Test
	func controlWinsOverTheTextInsideIt() {
		let text = SnapCandidate(frame: CGRect(x: 210, y: 405, width: 30, height: 12), role: "AXStaticText", label: "Save")
		let button = Self.button(CGRect(x: 200, y: 400, width: 60, height: 22), label: "Save")
		let target = Self.target(guess: CGPoint(x: 220, y: 410), label: "Save button", candidates: [text, button])
		#expect(target == PointTarget(frame: button.frame))
	}

	@Test
	func amongEqualMatchesTheSmallestWins() {
		let row = SnapCandidate(frame: CGRect(x: 0, y: 300, width: 300, height: 24), role: "AXRow", label: "Archive")
		let checkbox = SnapCandidate(frame: CGRect(x: 10, y: 304, width: 16, height: 16), role: "AXCheckBox", label: "Archive")
		let target = Self.target(guess: CGPoint(x: 15, y: 310), label: "Archive", candidates: [row, checkbox])
		#expect(target == PointTarget(frame: checkbox.frame))
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
		("README.md", "LICENSE.md"),
		("Package.swift", "Main.swift"),
		("Add to cart", "Add"),
	])
	func labelsThatDoNotMatch(_ modelLabel: String, _ elementLabel: String) {
		#expect(!SnapGuardrails.labelsMatch(modelLabel, elementLabel))
	}

	@Test(arguments: [
		("play button", "Run"),
		("Play", "Start"),
		("gear icon", "Settings"),
		("cog", "Preferences"),
		("trash icon", "Delete"),
		("plus button", "Add"),
		("magnifying glass", "Search"),
		("pencil icon", "Edit"),
	])
	func iconDescriptionsMatchTheNamesAppsUse(_ modelLabel: String, _ elementLabel: String) {
		#expect(SnapGuardrails.labelsMatch(modelLabel, elementLabel))
	}

	@Test
	func synonymsDoNotCrossGroups() {
		#expect(!SnapGuardrails.labelsMatch("play button", "Delete"))
		#expect(!SnapGuardrails.labelsMatch("gear icon", "Add"))
	}

	@Test
	func playButtonFindsXcodesRunButton() {
		let run = Self.button(CGRect(x: 212, y: 940, width: 31, height: 31), label: "Run")
		let target = Self.target(guess: CGPoint(x: 640, y: 950), label: "play button", candidates: [run])
		#expect(target == PointTarget(frame: run.frame))
	}

	// MARK: - Label range in recognized text

	@Test(arguments: [
		("README", "README.md", "README.md"),
		("README", "README.md Initial commit", "README.md"),
		("Run button", "Run", "Run"),
		("Sign up button", "Sign up", "Sign up"),
		("Budget", "Daily budget $50.00", "budget"),
		("the Publish button", "Save draft  Publish", "Publish"),
		("gear icon", "Settings", "Settings"),
	])
	func labelRangeCoversTheMatchingWords(_ label: String, _ text: String, _ expected: String) throws {
		let range = try #require(SnapGuardrails.labelRange(of: label, in: text))
		#expect(String(text[range]) == expected)
	}

	@Test
	func labelRangeIsNilWhenTheLabelsDoNotMatch() {
		#expect(SnapGuardrails.labelRange(of: "Run button", in: "Stop") == nil)
	}

	// MARK: - Helpers

	private static func button(_ frame: CGRect, label: String) -> SnapCandidate {
		SnapCandidate(frame: frame, role: "AXButton", label: label)
	}

	private static func target(guess: CGPoint, label: String, candidates: [SnapCandidate]) -> PointTarget? {
		SnapGuardrails.target(guess: guess, label: label, candidates: candidates, displayFrame: display)
	}
}
