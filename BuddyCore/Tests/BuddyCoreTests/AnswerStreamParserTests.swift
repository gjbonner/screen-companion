import CoreGraphics
import Testing
@testable import BuddyCore

struct AnswerStreamParserTests {
	private func run(_ chunks: [String]) -> (text: String, point: PointGuess?) {
		var parser = AnswerStreamParser()
		var events: [AnswerEvent] = []
		for chunk in chunks {
			events += parser.add(chunk)
		}
		events += parser.finish()
		var text = ""
		var point: PointGuess?
		for event in events {
			switch event {
			case .text(let chunk):
				text += chunk
			case .point(let guess):
				point = guess
			}
		}
		return (text, point)
	}

	@Test
	func plainAnswerPassesThrough() {
		let result = run(["Click ", "Edit next to the ad set."])
		#expect(result.text == "Click Edit next to the ad set.")
		#expect(result.point == nil)
	}

	@Test
	func pointLineIsParsedAndNeverShownAsText() {
		let result = run(["The Run button is top left.\n", "POINT: 172,44 | Run button"])
		#expect(result.text == "The Run button is top left.\n")
		#expect(result.point == PointGuess(imagePoint: CGPoint(x: 172, y: 44), label: "Run button"))
	}

	@Test
	func pointLineSplitAcrossChunksIsStillHidden() {
		let result = run(["It's the Edit button.\nPO", "IN", "T: 8", "12, 344 | E", "dit"])
		#expect(result.text == "It's the Edit button.\n")
		#expect(result.point == PointGuess(imagePoint: CGPoint(x: 812, y: 344), label: "Edit"))
	}

	@Test
	func textStartingLikePointButNotAPointLineIsEmitted() {
		let result = run(["Po", "licies are under Settings."])
		#expect(result.text == "Policies are under Settings.")
		#expect(result.point == nil)
	}

	@Test
	func malformedPointLineIsDroppedWithoutAPoint() {
		let result = run(["Look at the chart.\nPOINT: somewhere | chart"])
		#expect(result.text == "Look at the chart.\n")
		#expect(result.point == nil)
	}

	@Test
	func pointWithoutLabelStillParses() {
		let result = run(["Here.\nPOINT: 10.5, 20"])
		#expect(result.point == PointGuess(imagePoint: CGPoint(x: 10.5, y: 20), label: ""))
	}

	@Test
	func leadingThinkBlockIsDropped() {
		let result = run(["<thi", "nk>The user wants the budget.</th", "ink>\nIt's under Budget & Schedule."])
		#expect(result.text == "It's under Budget & Schedule.")
	}

	@Test
	func textIsEmittedBeforeTheStreamEnds() {
		var parser = AnswerStreamParser()
		let events = parser.add("Click Edit")
		#expect(events == [.text("Click Edit")])
	}
}
