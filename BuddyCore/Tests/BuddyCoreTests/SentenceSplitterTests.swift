import Testing
@testable import BuddyCore

struct SentenceSplitterTests {
	private func split(_ chunks: [String]) -> [String] {
		var splitter = SentenceSplitter()
		var sentences: [String] = []
		for chunk in chunks {
			sentences += splitter.add(chunk)
		}
		return sentences + splitter.finish()
	}

	@Test
	func splitsOnSentenceEndings() {
		#expect(split(["Click Edit. Then open Budget! Done?"]) == ["Click Edit.", "Then open Budget!", "Done?"])
	}

	@Test
	func sentenceIsReadyAsSoonAsTheNextCharacterArrives() {
		var splitter = SentenceSplitter()
		#expect(splitter.add("Click Edit.") == [])
		#expect(splitter.add(" Then") == ["Click Edit."])
	}

	@Test
	func decimalsAndPricesDoNotSplit() {
		#expect(split(["Your ROAS is 3.5 and CPC is $1.20 today. Nice."]) == ["Your ROAS is 3.5 and CPC is $1.20 today.", "Nice."])
	}

	@Test
	func abbreviationsDoNotSplit() {
		#expect(split(["Use a filter, e.g. date range. Then save."]) == ["Use a filter, e.g. date range.", "Then save."])
	}

	@Test
	func lineBreaksEndSentences() {
		#expect(split(["First line\nSecond line"]) == ["First line", "Second line"])
	}

	@Test
	func sentenceSplitAcrossChunksIsJoined() {
		#expect(split(["Cli", "ck E", "dit.", " Th", "en save."]) == ["Click Edit.", "Then save."])
	}

	@Test
	func unfinishedSentenceIsReturnedAtTheEnd() {
		#expect(split(["It's under Settings"]) == ["It's under Settings"])
	}
}
