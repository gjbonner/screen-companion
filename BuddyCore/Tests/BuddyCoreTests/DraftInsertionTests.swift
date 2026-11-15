import Testing
@testable import BuddyCore

struct DraftInsertionTests {
	@Test
	func textFocusPastes() {
		#expect(Self.delivery(focus: .text) == .paste)
	}

	@Test
	func unclearFocusStillPastes() {
		// Browsers and Electron apps often can't say what's focused. The paste may land or go nowhere;
		// the text is on the clipboard either way.
		#expect(Self.delivery(focus: .unknown) == .paste)
	}

	@Test
	func nonTextFocusCopies() {
		#expect(Self.delivery(focus: .notText) == .copy(reason: DraftInsertion.noTextFieldMessage))
	}

	@Test
	func noTextFieldMessageSaysSo() {
		#expect(DraftInsertion.noTextFieldMessage == "No text field is focused. Copied, paste with ⌘V.")
	}

	@Test(arguments: [FocusedInput.text, .notText, .unknown])
	func secureInputAlwaysCopies(_ focus: FocusedInput) {
		#expect(Self.delivery(focus: focus, secureInputActive: true) == .copy(reason: DraftInsertion.secureInputMessage))
	}

	@Test
	func withoutAccessibilityItCopiesAndSaysWhy() {
		#expect(Self.delivery(focus: .text, canPostKeystrokes: false) == .copy(reason: DraftInsertion.accessibilityMessage))
	}

	@Test
	func modifiersStillHeldCopiesInsteadOfSendingAnotherShortcut() {
		#expect(Self.delivery(focus: .text, modifiersReleased: false) == .copy(reason: DraftInsertion.copiedMessage))
	}

	@Test
	func secureInputWinsOverEverythingElse() {
		let delivery = DraftInsertion.delivery(focus: .notText, secureInputActive: true, canPostKeystrokes: false, modifiersReleased: false)
		#expect(delivery == .copy(reason: DraftInsertion.secureInputMessage))
	}

	@Test(arguments: ["AXTextField", "AXTextArea", "AXComboBox"])
	func textRolesAreText(_ role: String) {
		#expect(DraftInsertion.focusedInput(.element(role: role)) == .text)
	}

	@Test(arguments: ["AXWebArea", "AXGroup", "AXWindow", "AXApplication", "AXUnknown"])
	func webAndContainerRolesAreUnclear(_ role: String) {
		#expect(DraftInsertion.focusedInput(.element(role: role)) == .unknown)
	}

	@Test(arguments: ["AXButton", "AXList", "AXOutline", "AXRow", "AXScrollArea", "AXImage"])
	func otherRolesAreNotText(_ role: String) {
		#expect(DraftInsertion.focusedInput(.element(role: role)) == .notText)
	}

	@Test
	func unreadableRoleIsUnclear() {
		#expect(DraftInsertion.focusedInput(.element(role: nil)) == .unknown)
	}

	@Test
	func accessibilityFailureIsUnclear() {
		#expect(DraftInsertion.focusedInput(.unavailable) == .unknown)
	}

	@Test
	func buddyItselfIsNotText() {
		#expect(DraftInsertion.focusedInput(.buddyItself) == .notText)
	}

	// Chrome reports no focused element (AXError.noValue) whether or not a field is focused. Treating that as
	// "nothing focused" stopped Draft from ever pasting into Chrome.

	@Test
	func nothingFocusedIsUnclearBecauseChromeSaysItWithAFieldFocused() {
		#expect(DraftInsertion.focusedInput(.nothingFocused) == .unknown)
	}

	@Test
	func nothingFocusedStillPastes() {
		// Pastes into a focused Chrome field; if nothing was focused, the user can paste it from the clipboard.
		let delivery = Self.delivery(focus: DraftInsertion.focusedInput(.nothingFocused))
		#expect(delivery == .paste)
	}

	private static func delivery(
		focus: FocusedInput,
		secureInputActive: Bool = false,
		canPostKeystrokes: Bool = true,
		modifiersReleased: Bool = true
	) -> DraftDelivery {
		DraftInsertion.delivery(
			focus: focus,
			secureInputActive: secureInputActive,
			canPostKeystrokes: canPostKeystrokes,
			modifiersReleased: modifiersReleased
		)
	}
}

struct DictationReplyTests {
	@Test
	func plainReplyIsTrimmed() {
		#expect(DictationReply.text(from: "  Hi Greg, the budget is fine.\n") == "Hi Greg, the budget is fine.")
	}

	@Test
	func leadingThinkBlockIsDropped() {
		let reply = "<think>\nThe user corrected Tuesday to Wednesday.\n</think>\n\nSee you Wednesday."
		#expect(DictationReply.text(from: reply) == "See you Wednesday.")
	}

	@Test
	func unfinishedThinkBlockGivesNothing() {
		#expect(DictationReply.text(from: "<think>Still reasoning about") == "")
	}

	@Test
	func echoedDictationTagsAreDropped() {
		#expect(DictationReply.text(from: "<dictation>\nShip it today.\n</dictation>") == "Ship it today.")
	}

	@Test
	func tagsInsideTheTextAreKept() {
		// Only a wrapper around the whole reply is removed.
		let reply = "Use the <dictation> tag."
		#expect(DictationReply.text(from: reply) == reply)
	}

	@Test
	func multipleLinesAreKept() {
		#expect(DictationReply.text(from: "Hi Greg,\n\nThanks for the numbers.") == "Hi Greg,\n\nThanks for the numbers.")
	}
}
