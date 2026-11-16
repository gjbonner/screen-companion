/// Where one macOS permission stands.
public enum PermissionStatus: Sendable, Equatable {
	case granted
	/// macOS hasn't asked yet.
	case notRequested
	/// The user said no, or switched it off in System Settings.
	case denied
}

/// What a setup row offers the user.
public enum SetupAction: Sendable, Equatable {
	/// Nothing to do.
	case done
	/// Show macOS's own prompt from inside Buddy (Microphone, Speech Recognition).
	case allow
	/// Send the user to the right pane of System Settings.
	case openSettings
	/// Screen Recording only takes effect after Buddy restarts. The restart is macOS's own Quit & Reopen prompt, so the
	/// row explains it rather than offering a second way to restart.
	case relaunch
	/// Paste a Groq API key.
	case enterKey
}

/// What first-run setup still needs, and what each step should offer (onboarding window and menu bar).
public struct SetupChecklist: Sendable, Equatable {
	public var statuses: [Permission: PermissionStatus]
	public var hasAPIKey: Bool
	/// Whether the user has already been sent to System Settings for Screen Recording. macOS only reports the
	/// grant after a restart, so from then on the row says how to restart.
	public var screenRecordingRequested: Bool

	public init(statuses: [Permission: PermissionStatus], hasAPIKey: Bool, screenRecordingRequested: Bool) {
		self.statuses = statuses
		self.hasAPIKey = hasAPIKey
		self.screenRecordingRequested = screenRecordingRequested
	}

	public func status(of permission: Permission) -> PermissionStatus {
		statuses[permission] ?? .notRequested
	}

	public func action(for permission: Permission) -> SetupAction {
		switch status(of: permission) {
		case .granted:
			return .done
		case .denied:
			if permission == .screenRecording, screenRecordingRequested {
				return .relaunch
			}
			return .openSettings
		case .notRequested:
			switch permission {
			case .microphone, .speechRecognition:
				return .allow
			case .accessibility:
				return .openSettings
			case .screenRecording:
				return screenRecordingRequested ? .relaunch : .openSettings
			}
		}
	}

	public var apiKeyAction: SetupAction {
		hasAPIKey ? .done : .enterKey
	}

	/// How many steps are left, permissions and API key together.
	public var remainingCount: Int {
		Permission.allCases.filter { action(for: $0) != .done }.count + (hasAPIKey ? 0 : 1)
	}

	public var isComplete: Bool {
		remainingCount == 0
	}
}
