/// What has keyboard focus when Draft text is about to be inserted, as far as Accessibility can tell.
public enum FocusedInput: Sendable, Equatable {
	/// A text field, text area or other element that takes typed text.
	case text
	/// Something that clearly doesn't take text, such as a button, a list or Buddy itself.
	case notText
	/// Accessibility can't tell, as often happens in browsers and Electron apps.
	case unknown
}

/// How Draft text reaches the user (ADR 0006).
public enum DraftDelivery: Sendable, Equatable {
	/// Paste into the focused app with ⌘V, then restore the clipboard.
	case paste
	/// Leave the text on the clipboard and show `reason`.
	case copy(reason: String)
}

/// Decides whether Draft text is pasted or left on the clipboard.
///
/// Paste is the default: a paste where no text field is listening does nothing, so only a focus that is
/// clearly not text falls back to the clipboard. Browsers and Electron apps often report nothing useful
/// about focus, and they are where most Draft text goes.
public enum DraftInsertion {
	public static let copiedMessage = "Copied. Paste with ⌘V."
	public static let noTextFieldMessage = "No text field is focused. Copied, paste with ⌘V."
	public static let secureInputMessage = "A password field is active, so Buddy didn't type. Copied, paste with ⌘V."
	public static let accessibilityMessage = "Copied. Allow Accessibility in Setup so Buddy can paste for you."

	/// Roles of elements that take typed text.
	static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
	/// Roles that web content and Electron apps report for focused editable areas, among other things.
	static let unclearRoles: Set<String> = ["AXWebArea", "AXGroup", "AXWindow", "AXApplication", "AXUnknown"]

	/// - Parameters:
	///   - modifiersReleased: whether every modifier key was let go in time. If not, ⌘V would arrive as another shortcut.
	///   - canPostKeystrokes: whether Buddy has the Accessibility permission needed to send ⌘V.
	public static func delivery(
		focus: FocusedInput,
		secureInputActive: Bool,
		canPostKeystrokes: Bool,
		modifiersReleased: Bool
	) -> DraftDelivery {
		if secureInputActive {
			return .copy(reason: secureInputMessage)
		}
		if !canPostKeystrokes {
			return .copy(reason: accessibilityMessage)
		}
		if !modifiersReleased {
			return .copy(reason: copiedMessage)
		}
		switch focus {
		case .text, .unknown:
			return .paste
		case .notText:
			return .copy(reason: noTextFieldMessage)
		}
	}

	/// Classifies what Accessibility reported about the frontmost app's focus.
	public static func focusedInput(_ report: FocusReport) -> FocusedInput {
		switch report {
		case .element(let role):
			guard let role else {
				return .unknown
			}
			if textRoles.contains(role) {
				return .text
			}
			if unclearRoles.contains(role) {
				return .unknown
			}
			return .notText
		case .nothingFocused, .buddyItself:
			// A paste would go nowhere, or into Buddy.
			return .notText
		case .unavailable:
			return .unknown
		}
	}
}

/// What Accessibility said when asked for the frontmost app's focused element.
public enum FocusReport: Sendable, Equatable {
	/// An element has focus. `role` is nil if it couldn't be read.
	case element(role: String?)
	/// The app says nothing has focus (`AXError.noValue`), e.g. Chrome with no field clicked.
	case nothingFocused
	/// Buddy itself is frontmost, e.g. after Draft was started from the menu bar.
	case buddyItself
	/// Accessibility couldn't answer: no frontmost app, or any other error.
	case unavailable
}
