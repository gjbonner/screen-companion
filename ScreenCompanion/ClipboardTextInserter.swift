import AppKit
import ApplicationServices
import BuddyCore
import Carbon.HIToolbox

/// Inserts Draft text by putting it on the clipboard and pasting it into the focused app (ADR 0006).
///
/// The text is always left on the clipboard, so if the paste went nowhere the user can paste it themselves.
/// When pasting isn't safe or possible, only the clipboard is used and the reason is returned for the pill.
@MainActor
final class ClipboardTextInserter: TextInserter {
	private static let heldModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]

	private let pasteboard: NSPasteboard
	private let secureInput: any SecureInputDetector
	private let modifierReleaseTimeout: Duration
	/// Pasting into this process is refused (Buddy itself, e.g. after Draft was started from the menu bar). Tests pass nil.
	private let ownProcess: pid_t?

	init(
		pasteboard: NSPasteboard = .general,
		secureInput: any SecureInputDetector = SystemSecureInputDetector(),
		modifierReleaseTimeout: Duration = .seconds(1),
		ownProcess: pid_t? = ProcessInfo.processInfo.processIdentifier
	) {
		self.pasteboard = pasteboard
		self.secureInput = secureInput
		self.modifierReleaseTimeout = modifierReleaseTimeout
		self.ownProcess = ownProcess
	}

	func insert(_ text: String) async -> InsertionResult {
		// The hotkey "releases" when either Control or Option comes up; ⌘V must not be sent with the other still held.
		let modifiersReleased = await waitForModifierRelease()
		let focus = focusedInput()
		let delivery = DraftInsertion.delivery(
			focus: focus,
			secureInputActive: secureInput.isSecureInputActive(),
			canPostKeystrokes: AXIsProcessTrusted(),
			modifiersReleased: modifiersReleased
		)
		Log.draft.info("Focus \(String(describing: focus), privacy: .public), delivery \(String(describing: delivery), privacy: .public)")

		pasteboard.clearContents()
		pasteboard.setString(text, forType: .string)
		switch delivery {
		case .paste:
			guard postCommandV() else {
				Log.draft.error("Couldn't create the ⌘V keystroke")
				return .copiedToClipboard(reason: DraftInsertion.copiedMessage)
			}
			return .insertedAndCopied(note: DraftInsertion.copiedToClipboardMessage)
		case .copy(let reason):
			return .copiedToClipboard(reason: reason)
		}
	}

	// MARK: - Focus

	private func focusedInput() -> FocusedInput {
		let report = focusReport()
		Log.draft.info("Focus report \(String(describing: report), privacy: .public)")
		return DraftInsertion.focusedInput(report)
	}

	/// Asks Accessibility what has focus in the frontmost app. What that means for Draft is decided in `DraftInsertion`.
	private func focusReport() -> FocusReport {
		guard let app = NSWorkspace.shared.frontmostApplication else {
			return .unavailable
		}
		if let ownProcess, app.processIdentifier == ownProcess {
			return .buddyItself
		}
		let appName = app.localizedName ?? app.bundleIdentifier ?? "unknown app"
		let appElement = AXUIElementCreateApplication(app.processIdentifier)
		var focused: CFTypeRef?
		let focusError = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused)
		guard focusError == .success,
			let focused,
			CFGetTypeID(focused) == AXUIElementGetTypeID() else {
			Log.draft.info("\(appName, privacy: .public): no focused element, AXError \(focusError.rawValue, privacy: .public)")
			return focusError == .noValue ? .nothingFocused : .unavailable
		}
		var role: CFTypeRef?
		let roleError = AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXRoleAttribute as CFString, &role)
		Log.draft.info("\(appName, privacy: .public): focused role \((role as? String) ?? "none", privacy: .public), AXError \(roleError.rawValue, privacy: .public)")
		return .element(role: role as? String)
	}

	/// Waits until no modifier key is physically held. Returns false if one still is after the timeout.
	private func waitForModifierRelease() async -> Bool {
		let deadline = ContinuousClock.now + modifierReleaseTimeout
		while !CGEventSource.flagsState(.combinedSessionState).intersection(Self.heldModifiers).isEmpty {
			guard ContinuousClock.now < deadline, !Task.isCancelled else {
				return false
			}
			try? await Task.sleep(for: .milliseconds(20))
		}
		return true
	}

	// MARK: - Keystroke

	private func postCommandV() -> Bool {
		let source = CGEventSource(stateID: .hidSystemState)
		let key = CGKeyCode(kVK_ANSI_V)
		guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
			let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
			return false
		}
		down.flags = .maskCommand
		up.flags = .maskCommand
		down.post(tap: .cghidEventTap)
		up.post(tap: .cghidEventTap)
		return true
	}
}
