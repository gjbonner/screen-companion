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
	public var option: Bool
	public var command: Bool
	public var shift: Bool

	public init(control: Bool = false, option: Bool = false, command: Bool = false, shift: Bool = false) {
		self.control = control
		self.option = option
		self.command = command
		self.shift = shift
	}

	/// Exactly Control and Option, nothing else.
	var isHotkey: Bool {
		control && option && !command && !shift
	}

	var isEmpty: Bool {
		!control && !option && !command && !shift
	}
}

public enum HotkeyKey: Sendable, Equatable {
	case tab
	case escape
	case other
}

/// Turns raw keyboard events into Buddy actions. Pure and synchronous, because the event tap must decide instantly.
///
/// The hotkey is Control and Option held together with no other key.
/// - A hold shorter than `minimumHold` is treated as an accidental tap and cancelled.
/// - Any other key or modifier joining the hold cancels it and passes through, so Control-Option shortcuts keep working.
/// - After a cancel, nothing restarts until all modifiers are released.
public struct HotkeyInterpreter: Sendable {
	private enum Phase: Sendable, Equatable {
		case idle
		case holding(startedAt: TimeInterval)
		/// A hold was cancelled; wait for every modifier to be released before allowing a new press.
		case suppressed
	}

	public var minimumHold: TimeInterval
	private var phase: Phase = .idle

	public init(minimumHold: TimeInterval = 0.25) {
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
			if modifiers.isHotkey {
				phase = .holding(startedAt: time)
				return HotkeyDecision(action: .press, swallow: false)
			}
			return .passThrough

		case .holding(let startedAt):
			if modifiers.isHotkey {
				return .passThrough
			}
			if modifiers.command || modifiers.shift {
				phase = .suppressed
				return HotkeyDecision(action: .cancel, swallow: false)
			}
			// Control or Option was let go.
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
	public mutating func keyDown(_ key: HotkeyKey, isRepeat: Bool, buddyIsBusy: Bool) -> HotkeyDecision {
		if isHolding {
			switch key {
			case .tab:
				return HotkeyDecision(action: isRepeat ? nil : .toggleMode, swallow: true)
			case .escape:
				phase = .suppressed
				return HotkeyDecision(action: .cancel, swallow: true)
			case .other:
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
