import AppKit
import BuddyCore

/// Watches the keyboard system-wide with a `CGEventTap` and turns events into Buddy actions.
///
/// The tap needs the Accessibility permission. Until it's granted, `start()` keeps retrying quietly.
/// The tap's callback runs on the main run loop and must stay fast, or macOS disables the tap.
@MainActor
final class HotkeyMonitor {
	private var interpreter = HotkeyInterpreter()
	private var tap: CFMachPort?
	private var retryTimer: Timer?
	/// Key codes whose key-down was swallowed, so their key-up is swallowed too.
	private var swallowedKeyCodes: Set<Int64> = []
	private let onAction: @MainActor (HotkeyAction) -> Void
	private let isBuddyBusy: @MainActor () -> Bool

	private static let tabKeyCode: Int64 = 48
	private static let escapeKeyCode: Int64 = 53

	init(onAction: @escaping @MainActor (HotkeyAction) -> Void, isBuddyBusy: @escaping @MainActor () -> Bool) {
		self.onAction = onAction
		self.isBuddyBusy = isBuddyBusy
	}

	var isRunning: Bool {
		tap != nil
	}

	func start() {
		if installTap() {
			return
		}
		retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else {
					return
				}
				if self.installTap() {
					self.retryTimer?.invalidate()
					self.retryTimer = nil
				}
			}
		}
	}

	private func installTap() -> Bool {
		if tap != nil {
			return true
		}
		guard AXIsProcessTrusted() else {
			Log.hotkey.info("Waiting for Accessibility permission")
			return false
		}
		let mask = (1 << CGEventType.flagsChanged.rawValue)
			| (1 << CGEventType.keyDown.rawValue)
			| (1 << CGEventType.keyUp.rawValue)
		guard let tap = CGEvent.tapCreate(
			tap: .cgSessionEventTap,
			place: .headInsertEventTap,
			options: .defaultTap,
			eventsOfInterest: CGEventMask(mask),
			callback: hotkeyTapCallback,
			userInfo: Unmanaged.passUnretained(self).toOpaque()
		) else {
			Log.hotkey.error("Accessibility is granted but the event tap could not be created")
			return false
		}
		let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
		CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
		CGEvent.tapEnable(tap: tap, enable: true)
		self.tap = tap
		Log.hotkey.notice("Event tap installed")
		return true
	}

	/// Returns true when the event should be kept from reaching the focused app.
	fileprivate func handle(_ event: TapEvent) -> Bool {
		switch event.type {
		case .tapDisabledByTimeout, .tapDisabledByUserInput:
			Log.hotkey.notice("Event tap was disabled by macOS; re-enabling")
			if let tap {
				CGEvent.tapEnable(tap: tap, enable: true)
			}
			return false

		case .flagsChanged:
			let modifiers = ModifierKeys(
				control: event.flags.contains(.maskControl),
				option: event.flags.contains(.maskAlternate),
				command: event.flags.contains(.maskCommand),
				shift: event.flags.contains(.maskShift)
			)
			let decision = interpreter.modifiersChanged(to: modifiers, at: ProcessInfo.processInfo.systemUptime)
			perform(decision.action)
			return decision.swallow

		case .keyDown:
			let decision = interpreter.keyDown(Self.key(for: event.keyCode), isRepeat: event.isRepeat, buddyIsBusy: isBuddyBusy())
			if decision.swallow {
				swallowedKeyCodes.insert(event.keyCode)
			}
			perform(decision.action)
			return decision.swallow

		case .keyUp:
			return swallowedKeyCodes.remove(event.keyCode) != nil

		default:
			return false
		}
	}

	/// Runs the action after the callback returns, keeping the tap fast. Main-queue order keeps press before release.
	private func perform(_ action: HotkeyAction?) {
		guard let action else {
			return
		}
		Log.hotkey.info("Hotkey action: \(String(describing: action), privacy: .public)")
		let onAction = self.onAction
		DispatchQueue.main.async {
			onAction(action)
		}
	}

	private static func key(for keyCode: Int64) -> HotkeyKey {
		switch keyCode {
		case tabKeyCode:
			return .tab
		case escapeKeyCode:
			return .escape
		default:
			return .other
		}
	}
}

/// The parts of a `CGEvent` the monitor needs, copied out so no `CGEvent` crosses into main-actor code.
private struct TapEvent: Sendable {
	var type: CGEventType
	var flags: CGEventFlags
	var keyCode: Int64
	var isRepeat: Bool
}

private func hotkeyTapCallback(
	proxy: CGEventTapProxy,
	type: CGEventType,
	event: CGEvent,
	userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
	guard let userInfo else {
		return Unmanaged.passUnretained(event)
	}
	let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
	let tapEvent = TapEvent(
		type: type,
		flags: event.flags,
		keyCode: event.getIntegerValueField(.keyboardEventKeycode),
		isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
	)
	// The tap's run loop source is on the main run loop, so this is the main thread.
	let swallow = MainActor.assumeIsolated {
		monitor.handle(tapEvent)
	}
	if swallow {
		return nil
	}
	return Unmanaged.passUnretained(event)
}
