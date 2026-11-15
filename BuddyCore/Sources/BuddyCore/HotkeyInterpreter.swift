import Foundation

/// What a hotkey event means for Buddy.
public enum HotkeyAction: Sendable, Equatable {
	/// Control and Option are now the only modifiers held: start listening.
	case press
	/// The hold ended normally: stop listening and handle the request.
	case release
	/// The hold was abandoned: a quick accidental tap, or another key joined in (the user was typing a shortcut).
	case cancel
	/// Tab during a hold: switch between Ask and Draft.
	case toggleMode
	/// Esc while Buddy is busy: abandon the current request.
	case escape
}

/// The interpreter's answer for one keyboard event.
public struct HotkeyDecision: Sendable, Equatable {
	public var action: HotkeyAction?
	/// Whether the event should be kept from reaching the focused app.
	public var swallow: Bool

	public static let passThrough = HotkeyDecision(action: nil, swallow: false)

	public init(action: HotkeyAction?, swallow: Bool) {
		self.action = action
		self.swallow = swallow
	}
}

public struct ModifierKeys: Sendable, Equatable {
	public var control: Bool
	/// Either Option key.
	public var option: Bool
	public var command: Bool
	public var shift: Bool
	/// Which Option key is down, for the Right Option hotkey.
	public var leftOption: Bool
	public var rightOption: Bool

	public init(
		control: Bool = false,
		option: Bool = false,
		command: Bool = false,
		shift: Bool = false,
		leftOption: Bool = false,
		rightOption: Bool = false
	) {
		self.control = control
		self.option = option
		self.command = command
		self.shift = shift
		self.leftOption = leftOption
		self.rightOption = rightOption
	}

	var isEmpty: Bool {
		!control && !option && !command && !shift
	}
}

/// The modifier-only hold that starts Buddy, chosen by the user.
///
/// None of them takes a key from any app: Buddy never claims a letter, number or function key, and another key
/// joining the hold cancels it and passes through. Globe/fn and Control alone are left out because macOS uses them.
public enum HotkeyChoice: String, Sendable, CaseIterable, Codable {
	case controlOption
	case optionCommand
	case controlShift
	case rightOption

	public static let standard = HotkeyChoice.controlOption

	/// Exactly this combination is held, nothing else.
	public func matches(_ keys: ModifierKeys) -> Bool {
		switch self {
		case .controlOption:
			return keys.control && keys.option && !keys.command && !keys.shift
		case .optionCommand:
			return keys.option && keys.command && !keys.control && !keys.shift
		case .controlShift:
			return keys.control && keys.shift && !keys.option && !keys.command
		case .rightOption:
			return keys.rightOption && !keys.leftOption && !keys.control && !keys.command && !keys.shift
		}
	}

	/// All of this combination's keys are still down, possibly with others.
	func isHeld(in keys: ModifierKeys) -> Bool {
		switch self {
		case .controlOption:
			return keys.control && keys.option
		case .optionCommand:
			return keys.option && keys.command
		case .controlShift:
			return keys.control && keys.shift
		case .rightOption:
			return keys.rightOption
		}
	}
}

public enum HotkeyKey: Sendable, Equatable {
	case tab
	case escape
	case other
}

/// Turns raw keyboard events into Buddy actions. Pure and synchronous, because the event tap must decide instantly.
///
/// The hotkey is the chosen modifier combination (`HotkeyChoice`) held with no other key.
/// - A hold shorter than `minimumHold` is treated as an accidental tap and cancelled.
/// - Any other key or modifier joining the hold cancels it and passes through, so shortcuts using those modifiers keep working.
/// - Tab and Esc belong to Buddy only once the hold has lasted `minimumHold`; in a quick chord such as ⌃⇧Tab
///   (previous browser tab) or ⌥⌘Esc (Force Quit) they pass through like any other key.
/// - After a cancel, nothing restarts until all modifiers are released.
public struct HotkeyInterpreter: Sendable {
	private enum Phase: Sendable, Equatable {
		case idle
		case holding(startedAt: TimeInterval)
		/// A hold was cancelled; wait for every modifier to be released before allowing a new press.
		case suppressed
	}

	public var minimumHold: TimeInterval
	/// Which combination starts a hold. Changing it takes effect from the next press.
	public var hotkey: HotkeyChoice
	private var phase: Phase = .idle

	public init(hotkey: HotkeyChoice = .standard, minimumHold: TimeInterval = 0.25) {
		self.hotkey = hotkey
		self.minimumHold = minimumHold
	}

	public var isHolding: Bool {
		if case .holding = phase {
			return true
		}
		return false
	}

	public mutating func modifiersChanged(to modifiers: ModifierKeys, at time: TimeInterval) -> HotkeyDecision {
		switch phase {
		case .idle:
			if hotkey.matches(modifiers) {
				phase = .holding(startedAt: time)
				return HotkeyDecision(action: .press, swallow: false)
			}
			return .passThrough

		case .holding(let startedAt):
			if hotkey.matches(modifiers) {
				return .passThrough
			}
			if hotkey.isHeld(in: modifiers) {
				// Another modifier joined: the user is typing a shortcut.
				phase = .suppressed
				return HotkeyDecision(action: .cancel, swallow: false)
			}
			// One of the hotkey's keys was let go.
			phase = modifiers.isEmpty ? .idle : .suppressed
			if time - startedAt < minimumHold {
				return HotkeyDecision(action: .cancel, swallow: false)
			}
			return HotkeyDecision(action: .release, swallow: false)

		case .suppressed:
			if modifiers.isEmpty {
				phase = .idle
			}
			return .passThrough
		}
	}

	/// - Parameter buddyIsBusy: whether a request is in progress, so Esc outside a hold knows whether it belongs to Buddy.
	public mutating func keyDown(_ key: HotkeyKey, isRepeat: Bool, buddyIsBusy: Bool, at time: TimeInterval) -> HotkeyDecision {
		if case .holding(let startedAt) = phase {
			// Too soon after the press, Tab and Esc are part of a shortcut (⌃⇧Tab, ⌥⌘Esc), not meant for Buddy.
			let deliberate = time - startedAt >= minimumHold
			switch key {
			case .tab where deliberate:
				return HotkeyDecision(action: isRepeat ? nil : .toggleMode, swallow: true)
			case .escape where deliberate:
				phase = .suppressed
				return HotkeyDecision(action: .cancel, swallow: true)
			case .tab, .escape, .other:
				phase = .suppressed
				return HotkeyDecision(action: .cancel, swallow: false)
			}
		}
		if key == .escape, buddyIsBusy {
			return HotkeyDecision(action: isRepeat ? nil : .escape, swallow: true)
		}
		return .passThrough
	}
}
