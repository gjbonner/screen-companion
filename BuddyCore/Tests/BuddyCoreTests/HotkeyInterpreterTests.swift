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
		let decision = interpreter.keyDown(.other, isRepeat: false, buddyIsBusy: true)

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

		#expect(interpreter.keyDown(.tab, isRepeat: false, buddyIsBusy: true) == HotkeyDecision(action: .toggleMode, swallow: true))
		#expect(interpreter.keyDown(.tab, isRepeat: true, buddyIsBusy: true) == HotkeyDecision(action: nil, swallow: true))
		#expect(interpreter.isHolding)
	}

	@Test
	func escapeDuringHoldCancelsAndIsSwallowed() {
		var interpreter = HotkeyInterpreter()

		_ = interpreter.modifiersChanged(to: hotkey, at: 0)

		#expect(interpreter.keyDown(.escape, isRepeat: false, buddyIsBusy: true) == HotkeyDecision(action: .cancel, swallow: true))
		#expect(interpreter.modifiersChanged(to: none, at: 2).action == nil)
	}

	@Test
	func escapeWhileBuddyIsBusyEscapesAndIsSwallowed() {
		var interpreter = HotkeyInterpreter()

		#expect(interpreter.keyDown(.escape, isRepeat: false, buddyIsBusy: true) == HotkeyDecision(action: .escape, swallow: true))
	}

	@Test
	func escapeAndTabWhenBuddyIsIdlePassThrough() {
		var interpreter = HotkeyInterpreter()

		#expect(interpreter.keyDown(.escape, isRepeat: false, buddyIsBusy: false) == .passThrough)
		#expect(interpreter.keyDown(.tab, isRepeat: false, buddyIsBusy: true) == .passThrough)
	}
}
