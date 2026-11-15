import BuddyCore
import Foundation
import Observation

/// Which modifier hold starts Buddy, remembered between launches.
/// Shared by the menu bar, the setup window and the hotkey monitor.
@MainActor
@Observable
final class HotkeySetting {
	private static let defaultsKey = "hotkey"

	var choice: HotkeyChoice {
		didSet {
			UserDefaults.standard.set(choice.rawValue, forKey: Self.defaultsKey)
		}
	}

	init() {
		let saved = UserDefaults.standard.string(forKey: Self.defaultsKey).flatMap(HotkeyChoice.init(rawValue:))
		choice = saved ?? .standard
	}
}

extension HotkeyChoice {
	/// The keys as macOS shows them in menus.
	var symbols: String {
		switch self {
		case .controlOption:
			return "⌃⌥"
		case .optionCommand:
			return "⌥⌘"
		case .controlShift:
			return "⌃⇧"
		case .rightOption:
			return "Right ⌥"
		}
	}

	/// For pickers: symbols and words.
	var title: String {
		switch self {
		case .controlOption:
			return "⌃⌥  Control + Option"
		case .optionCommand:
			return "⌥⌘  Option + Command"
		case .controlShift:
			return "⌃⇧  Control + Shift"
		case .rightOption:
			return "Right ⌥  Right Option"
		}
	}
}
