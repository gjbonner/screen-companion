import Testing
@testable import BuddyCore

struct HotkeyInterpreterTests {
	private let hotkey = ModifierKeys(control: true, option: true)
	private let none = ModifierKeys()

	@Test
	func holdingControlAndOptionPressesAndReleasingAfterMinimumReleases() {
		var interpreter = HotkeyInterpreter()

		#expect(interpreter.modifiersChanged(to: hotkey, at: 10.0).action == .press)
		#expect(interpreter.isHolding)
		#expect(interpreter.modifiersChanged(to: none, at: 11.0).action == .release)
		#expect(!interpreter.isHolding)
	}

	@Test
	func pressingTheKeysOneAtATimeStillPresses() {
		var interpreter = HotkeyInterpreter()

		#expect(interpreter.modifiersChanged(to: ModifierKeys(control: true), at: 0).action == nil)
		#expect(interpreter.modifiersChanged(to: hotkey, at: 0.1).action == .press)
	}

	@Test
	func releasingOneKeyFirstReleasesThenWaitsForTheOther() {
		var interpreter = HotkeyInterpreter()

		_ = interpreter.modifiersChanged(to: hotkey, at: 0)
		#expect(interpreter.modifiersChanged(to: ModifierKeys(option: true), at: 1).action == .release)
		// Pressing Control again while Option is still held must not start a new request.
		#expect(interpreter.modifiersChanged(to: hotkey, at: 1.1).action == nil)
		#expect(interpreter.modifiersChanged(to: none, at: 1.2).action == nil)
		#expect(interpreter.modifiersChanged(to: hotkey, at: 2).action == .press)
	}

	@Test
	func quickTapIsCancelledNotSent() {
		var interpreter = HotkeyInterpreter()

		_ = interpreter.modifiersChanged(to: hotkey, at: 5.0)
		#expect(interpreter.modifiersChanged(to: none, at: 5.1).action == .cancel)
	}

	@Test
	func anotherKeyDuringHoldCancelsAndPassesThrough() {
		var interpreter = HotkeyInterpreter()

		_ = interpreter.modifiersChanged(to: hotkey, at: 0)
		let decision = interpreter.keyDown(.other, isRepeat: false, buddyIsBusy: true, at: 1)

		#expect(decision == HotkeyDecision(action: .cancel, swallow: false))
		#expect(interpreter.modifiersChanged(to: none, at: 2).action == nil)
	}

	@Test
	func addingCommandOrShiftCancels() {
		var interpreter = HotkeyInterpreter()

		_ = interpreter.modifiersChanged(to: hotkey, at: 0)
		let withCommand = ModifierKeys(control: true, option: true, command: true)
		#expect(interpreter.modifiersChanged(to: withCommand, at: 1).action == .cancel)
		#expect(interpreter.modifiersChanged(to: hotkey, at: 1.5).action == nil)
	}

	@Test
	func hotkeyWithShiftAlreadyHeldDoesNotPress() {
		var interpreter = HotkeyInterpreter()

		let withShift = ModifierKeys(control: true, option: true, shift: true)
		#expect(interpreter.modifiersChanged(to: withShift, at: 0).action == nil)
	}

	@Test
	func tabDuringHoldTogglesModeAndIsSwallowed() {
		var interpreter = HotkeyInterpreter()

		_ = interpreter.modifiersChanged(to: hotkey, at: 0)

		#expect(interpreter.keyDown(.tab, isRepeat: false, buddyIsBusy: true, at: 1) == HotkeyDecision(action: .toggleMode, swallow: true))
		#expect(interpreter.keyDown(.tab, isRepeat: true, buddyIsBusy: true, at: 1.1) == HotkeyDecision(action: nil, swallow: true))
		#expect(interpreter.isHolding)
	}

	@Test
	func escapeDuringHoldCancelsAndIsSwallowed() {
		var interpreter = HotkeyInterpreter()

		_ = interpreter.modifiersChanged(to: hotkey, at: 0)

		#expect(interpreter.keyDown(.escape, isRepeat: false, buddyIsBusy: true, at: 1) == HotkeyDecision(action: .cancel, swallow: true))
		#expect(interpreter.modifiersChanged(to: none, at: 2).action == nil)
	}

	@Test
	func escapeWhileBuddyIsBusyEscapesAndIsSwallowed() {
		var interpreter = HotkeyInterpreter()

		#expect(interpreter.keyDown(.escape, isRepeat: false, buddyIsBusy: true, at: 0) == HotkeyDecision(action: .escape, swallow: true))
	}

	@Test
	func escapeAndTabWhenBuddyIsIdlePassThrough() {
		var interpreter = HotkeyInterpreter()

		#expect(interpreter.keyDown(.escape, isRepeat: false, buddyIsBusy: false, at: 0) == .passThrough)
		#expect(interpreter.keyDown(.tab, isRepeat: false, buddyIsBusy: true, at: 0) == .passThrough)
	}

	// MARK: - Shortcuts that use Tab or Esc

	@Test
	func quickControlShiftTabReachesTheBrowser() {
		// ⌃⇧Tab is "previous tab" in browsers: the Tab arrives right after the modifiers.
		var interpreter = HotkeyInterpreter(hotkey: .controlShift)

		#expect(interpreter.modifiersChanged(to: ModifierKeys(control: true, shift: true), at: 0).action == .press)
		#expect(interpreter.keyDown(.tab, isRepeat: false, buddyIsBusy: true, at: 0.1) == HotkeyDecision(action: .cancel, swallow: false))
		#expect(!interpreter.isHolding)
	}

	@Test
	func quickOptionCommandEscapeReachesForceQuit() {
		var interpreter = HotkeyInterpreter(hotkey: .optionCommand)

		#expect(interpreter.modifiersChanged(to: ModifierKeys(option: true, command: true), at: 0).action == .press)
		#expect(interpreter.keyDown(.escape, isRepeat: false, buddyIsBusy: true, at: 0.1) == HotkeyDecision(action: .cancel, swallow: false))
	}

	@Test
	func tabAfterADeliberateHoldStillSwitchesMode() {
		var interpreter = HotkeyInterpreter(hotkey: .controlShift)

		_ = interpreter.modifiersChanged(to: ModifierKeys(control: true, shift: true), at: 0)
		#expect(interpreter.keyDown(.tab, isRepeat: false, buddyIsBusy: true, at: 0.25) == HotkeyDecision(action: .toggleMode, swallow: true))
	}

	// MARK: - Each choice

	@Test(arguments: [
		(HotkeyChoice.controlOption, ModifierKeys(control: true, option: true, leftOption: true)),
		(.optionCommand, ModifierKeys(option: true, command: true, leftOption: true)),
		(.controlShift, ModifierKeys(control: true, shift: true)),
		(.rightOption, ModifierKeys(option: true, rightOption: true)),
	])
	func eachChoicePressesAndReleases(_ choice: HotkeyChoice, _ keys: ModifierKeys) {
		var interpreter = HotkeyInterpreter(hotkey: choice)

		#expect(interpreter.modifiersChanged(to: keys, at: 0).action == .press)
		#expect(interpreter.modifiersChanged(to: none, at: 1).action == .release)
	}

	@Test(arguments: HotkeyChoice.allCases)
	func onlyTheChosenCombinationPresses(_ choice: HotkeyChoice) {
		let combinations: [HotkeyChoice: ModifierKeys] = [
			.controlOption: ModifierKeys(control: true, option: true, leftOption: true),
			.optionCommand: ModifierKeys(option: true, command: true, leftOption: true),
			.controlShift: ModifierKeys(control: true, shift: true),
			.rightOption: ModifierKeys(option: true, rightOption: true),
		]
		for (other, keys) in combinations where other != choice {
			var interpreter = HotkeyInterpreter(hotkey: choice)
			#expect(interpreter.modifiersChanged(to: keys, at: 0).action == nil, "\(other) pressed \(choice)")
		}
	}

	@Test
	func leftOptionAloneDoesNotPressRightOption() {
		var interpreter = HotkeyInterpreter(hotkey: .rightOption)

		#expect(interpreter.modifiersChanged(to: ModifierKeys(option: true, leftOption: true), at: 0).action == nil)
	}

	@Test
	func bothOptionKeysDoNotPressRightOption() {
		var interpreter = HotkeyInterpreter(hotkey: .rightOption)

		#expect(interpreter.modifiersChanged(to: ModifierKeys(option: true, leftOption: true, rightOption: true), at: 0).action == nil)
	}

	@Test
	func addingLeftOptionDuringARightOptionHoldCancels() {
		var interpreter = HotkeyInterpreter(hotkey: .rightOption)

		_ = interpreter.modifiersChanged(to: ModifierKeys(option: true, rightOption: true), at: 0)
		let both = ModifierKeys(option: true, leftOption: true, rightOption: true)
		#expect(interpreter.modifiersChanged(to: both, at: 1).action == .cancel)
	}

	@Test
	func changingTheChoiceTakesEffectOnTheNextPress() {
		var interpreter = HotkeyInterpreter()
		interpreter.hotkey = .optionCommand

		#expect(interpreter.modifiersChanged(to: hotkey, at: 0).action == nil)
		#expect(interpreter.modifiersChanged(to: none, at: 0.5).action == nil)
		#expect(interpreter.modifiersChanged(to: ModifierKeys(option: true, command: true), at: 1).action == .press)
	}
}
