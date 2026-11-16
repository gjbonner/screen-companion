import AppKit
import AVFoundation
import BuddyCore
import SwiftUI

/// What first-run setup still needs, kept current while Buddy runs. Shared by the menu bar and the onboarding window.
@MainActor
@Observable
final class SetupMonitor {
	private static let screenRecordingRequestedKey = "screenRecordingRequested"
	private static let refreshInterval: TimeInterval = 2

	private(set) var checklist: SetupChecklist
	/// Whether an Enhanced or Premium voice is installed for the user's language.
	private(set) var hasEnhancedVoice: Bool

	@ObservationIgnored private let permissions = SystemPermissionChecker()
	@ObservationIgnored private let apiKeys: any SavedAPIKeyStore
	@ObservationIgnored private let validateKey: @Sendable (String) async throws -> Void
	@ObservationIgnored private var timer: Timer?

	/// - Parameters:
	///   - apiKeys: where the key is read and saved (the Keychain; tests pass an in-memory store).
	///   - validateKey: checks a key before it's saved, throwing a user-facing error if it's rejected (Groq; tests pass a stub).
	init(
		apiKeys: any SavedAPIKeyStore = KeychainAPIKeyStore(),
		validateKey: @escaping @Sendable (String) async throws -> Void = { try await GroqClient.validate(key: $0) }
	) {
		self.apiKeys = apiKeys
		self.validateKey = validateKey
		checklist = Self.readChecklist(permissions: permissions, apiKeys: apiKeys)
		hasEnhancedVoice = Self.enhancedVoiceInstalled()
		// Permissions change in System Settings, outside Buddy, so they're polled. Each check is a cheap local call.
		timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.refresh()
			}
		}
	}

	func refresh() {
		if permissions.status(of: .screenRecording) == .granted {
			UserDefaults.standard.removeObject(forKey: Self.screenRecordingRequestedKey)
		}
		let latest = Self.readChecklist(permissions: permissions, apiKeys: apiKeys)
		if latest != checklist {
			checklist = latest
		}
		let voice = Self.enhancedVoiceInstalled()
		if voice != hasEnhancedVoice {
			hasEnhancedVoice = voice
		}
	}

	/// Carries out a row's action.
	func perform(_ action: SetupAction, for permission: Permission) async {
		switch action {
		case .done, .enterKey, .relaunch:
			// Restarting for Screen Recording is left to macOS's own Quit & Reopen prompt, so there's only one way to do it.
			return
		case .allow:
			await permissions.request(permission)
		case .openSettings where permission == .screenRecording:
			// Only macOS's own screen recording prompt adds Buddy to the Screen & System Audio Recording list, when its
			// Open System Settings button is clicked. If Buddy opens Settings itself, the pane shows without Buddy and the
			// prompt is lost behind it. So Buddy only asks; clicking again brings the prompt back.
			await permissions.request(permission)
			UserDefaults.standard.set(true, forKey: Self.screenRecordingRequestedKey)
		case .openSettings:
			// Always ask macOS first: that is what puts Buddy in the permission's list in System Settings, and a
			// reset of permissions (tccutil) removes it again without Buddy knowing. Asking when Buddy is already
			// listed does nothing. The first request shows macOS's own prompt, whose button opens System Settings;
			// opening it as well would show both, so Buddy only opens Settings itself after that.
			let askedKey = Self.askedKey(for: permission)
			let askedBefore = UserDefaults.standard.bool(forKey: askedKey)
			UserDefaults.standard.set(true, forKey: askedKey)
			await permissions.request(permission)
			if askedBefore {
				permissions.openSettings(for: permission)
			}
		}
		refresh()
	}

	/// Checks the key, then saves it, replacing any saved key. A rejected key never overwrites the saved one.
	/// Throws a user-facing error.
	func saveAPIKey(_ key: String) async throws {
		let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			throw BuddyError("Paste your Groq API key first.")
		}
		try await validateKey(trimmed)
		try apiKeys.save(trimmed)
		refresh()
	}

	func openVoiceSettings() {
		if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess") {
			NSWorkspace.shared.open(url)
		}
	}

	/// Whether Buddy has already asked macOS for this permission, so its one-time prompt has been shown.
	private static func askedKey(for permission: Permission) -> String {
		"asked.\(permission)"
	}

	private static func readChecklist(permissions: SystemPermissionChecker, apiKeys: any APIKeyStore) -> SetupChecklist {
		let statuses = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, permissions.status(of: $0)) })
		return SetupChecklist(
			statuses: statuses,
			hasAPIKey: !(apiKeys.apiKey() ?? "").isEmpty,
			screenRecordingRequested: UserDefaults.standard.bool(forKey: screenRecordingRequestedKey)
		)
	}

	private static func enhancedVoiceInstalled() -> Bool {
		let language = AVSpeechSynthesisVoice.currentLanguageCode().prefix(2)
		return AVSpeechSynthesisVoice.speechVoices().contains { voice in
			voice.language.hasPrefix(language) && voice.quality != .default
		}
	}
}

/// The setup window: shown at launch while anything is missing, and from "Setup…" in the menu bar.
///
/// Buddy has no Dock icon, so once System Settings or a macOS prompt comes forward the window would be stranded
/// behind it. Whenever a step is completed, the window comes back to the front, and it closes itself shortly after
/// everything is in place. While System Settings or a permission prompt is in front, the window never jumps over
/// it: it waits until System Settings quits.
@MainActor
final class OnboardingWindowController {
	private static let closeDelay: Duration = .milliseconds(1500)
	/// System Settings, and the apps that show its password and permission prompts.
	private static let settingsApps: Set<String> = [
		"com.apple.systempreferences",
		"com.apple.SecurityAgent",
		"com.apple.UserNotificationCenter",
	]

	private let setup: SetupMonitor
	private let hotkey: HotkeySetting
	private var window: NSWindow?
	private var closeTask: Task<Void, Never>?
	/// Steps left at the last change, so the window only comes forward when one is completed.
	private var lastRemainingCount: Int
	/// A step was completed while System Settings was in front; come back once it quits.
	private var returnWhenSettingsQuits = false

	init(setup: SetupMonitor, hotkey: HotkeySetting) {
		self.setup = setup
		self.hotkey = hotkey
		lastRemainingCount = setup.checklist.remainingCount
		observeProgress()
		NSWorkspace.shared.notificationCenter.addObserver(
			forName: NSWorkspace.didTerminateApplicationNotification,
			object: nil,
			queue: .main
		) { [weak self] notification in
			let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
			let bundleID = app?.bundleIdentifier
			MainActor.assumeIsolated {
				self?.appQuit(bundleID)
			}
		}
	}

	func show() {
		if window == nil {
			let host = NSHostingController(rootView: OnboardingView(setup: setup, hotkey: hotkey))
			let window = NSWindow(contentViewController: host)
			window.title = "Set Up Buddy"
			window.styleMask = [.titled, .closable]
			window.isReleasedWhenClosed = false
			window.center()
			self.window = window
		}
		setup.refresh()
		NSApp.activate()
		window?.makeKeyAndOrderFront(nil)
	}

	private func observeProgress() {
		withObservationTracking {
			_ = setup.checklist
		} onChange: { [weak self] in
			DispatchQueue.main.async {
				self?.progressChanged()
				self?.observeProgress()
			}
		}
	}

	private func progressChanged() {
		closeTask?.cancel()
		let remaining = setup.checklist.remainingCount
		let stepCompleted = remaining < lastRemainingCount
		lastRemainingCount = remaining
		guard let window, window.isVisible else {
			return
		}
		// Bring the checklist back after the user flips a switch in System Settings or answers a prompt. Only a
		// completed step does this: coming forward for any other change (such as Screen Recording being requested)
		// would pull focus from System Settings while the user is entering their password there.
		guard stepCompleted else {
			return
		}
		if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences" {
			// The user is in System Settings: come back once it quits, never over it.
			returnWhenSettingsQuits = true
		} else if Self.settingsAppIsInFront {
			// A macOS prompt (Microphone, Speech Recognition) was just answered and is closing. System Settings may
			// never open in this case, so don't wait for it to quit: come back once the prompt is gone.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.bringForward()
			}
		} else {
			bringForward()
		}
		guard setup.checklist.isComplete else {
			return
		}
		// Leave the all-done state on screen for a moment before closing.
		closeTask = Task { [weak self] in
			try? await Task.sleep(for: Self.closeDelay)
			guard !Task.isCancelled, let self, setup.checklist.isComplete else {
				return
			}
			self.window?.close()
		}
	}

	private func appQuit(_ bundleID: String?) {
		guard bundleID == "com.apple.systempreferences", returnWhenSettingsQuits else {
			return
		}
		returnWhenSettingsQuits = false
		if let window, window.isVisible {
			bringForward()
		}
	}

	private func bringForward() {
		// macOS refuses activation for an app that isn't in front (Buddy has no Dock icon, and a permission prompt
		// hands focus back to the previous app), so `activate()` alone can leave the window buried.
		// `orderFrontRegardless()` lifts the window above other apps' windows either way.
		NSApp.activate()
		window?.makeKeyAndOrderFront(nil)
		window?.orderFrontRegardless()
	}

	private static var settingsAppIsInFront: Bool {
		guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
			return false
		}
		return settingsApps.contains(bundleID)
	}
}

// MARK: - Views

struct OnboardingView: View {
	let setup: SetupMonitor
	let hotkey: HotkeySetting

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			VStack(alignment: .leading, spacing: 4) {
				Text("Set up Buddy")
					.font(.title2.weight(.semibold))
				Text(setup.checklist.isComplete ? "You're all set. Hold \(hotkey.choice.symbols) anywhere to talk." : "Buddy needs a few things before it can help.")
					.foregroundStyle(.secondary)
			}

			VStack(spacing: 0) {
				ForEach(Array(Permission.allCases.enumerated()), id: \.element) { index, permission in
					if index > 0 {
						Divider()
					}
					PermissionRow(permission: permission, setup: setup)
				}
				Divider()
				APIKeyRow(setup: setup)
			}
			.padding(.horizontal, 14)
			.background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

			HStack(alignment: .firstTextBaseline, spacing: 10) {
				VStack(alignment: .leading, spacing: 2) {
					Text("Hotkey")
						.font(.body.weight(.medium))
					Text("Hold it to talk. Another key pressed with it goes to your app as usual, so no shortcut is taken over.")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
				Spacer(minLength: 8)
				HotkeyPicker(hotkey: hotkey)
					.labelsHidden()
					.fixedSize()
			}

			if !setup.hasEnhancedVoice {
				VoiceTip(setup: setup)
			}
		}
		.padding(22)
		.frame(width: 480)
	}
}

private struct PermissionRow: View {
	let permission: Permission
	let setup: SetupMonitor

	var body: some View {
		let action = setup.checklist.action(for: permission)
		HStack(alignment: .center, spacing: 12) {
			Image(systemName: permission.symbol)
				.font(.title3)
				.frame(width: 26)
				.foregroundStyle(Theme.accent)
			VStack(alignment: .leading, spacing: 2) {
				Text(permission.title)
					.font(.body.weight(.medium))
					Text(action == .relaunch ? "In the macOS prompt about recording your screen, click Open System Settings, switch Buddy on, then choose Quit & Reopen. No prompt? Click Open Settings again." : permission.reason)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: 8)
			StatusControl(action: action) { chosen in
				Task {
					await setup.perform(chosen, for: permission)
				}
			}
		}
		.padding(.vertical, 12)
	}
}

private struct StatusControl: View {
	let action: SetupAction
	let perform: (SetupAction) -> Void

	var body: some View {
		switch action {
		case .done, .enterKey:
			Image(systemName: "checkmark.circle.fill")
				.font(.title3)
				.foregroundStyle(.green)
				.accessibilityLabel("Done")
		case .allow:
			Button("Allow") {
				perform(.allow)
			}
		case .openSettings, .relaunch:
			// While waiting for the restart, Settings stays reachable: the switch may not be on yet, for example
			// after permissions were reset. The restart itself is macOS's Quit & Reopen prompt, not a Buddy button.
			Button("Open Settings") {
				perform(.openSettings)
			}
		}
	}
}

private struct APIKeyRow: View {
	let setup: SetupMonitor
	@State private var key = ""
	@State private var isChecking = false
	@State private var problem: String?
	/// The user chose to replace a saved key, for example after Groq rejected it. The saved key stays until a new one passes the check.
	@State private var isReplacing = false

	var body: some View {
		let showsEntry = !setup.checklist.hasAPIKey || isReplacing
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: "key")
				.font(.title3)
				.frame(width: 26)
				.foregroundStyle(Theme.accent)
			VStack(alignment: .leading, spacing: 6) {
				Text("Groq API key")
					.font(.body.weight(.medium))
				if !showsEntry {
					Text("Saved in your Keychain.")
						.font(.caption)
						.foregroundStyle(.secondary)
					Button("Replace key…") {
						problem = nil
						isReplacing = true
					}
					.buttonStyle(.link)
					.font(.caption)
				} else {
					Text(isReplacing ? "Paste a new key. Your saved key is kept until this one is checked." : "Answers and Draft clean-up use Groq. A free key works.")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
					HStack {
						SecureField("gsk_…", text: $key)
							.textFieldStyle(.roundedBorder)
							.onSubmit(save)
						Button(isChecking ? "Checking…" : "Save", action: save)
							.disabled(isChecking || key.isEmpty)
						if isReplacing {
							Button("Cancel") {
								key = ""
								problem = nil
								isReplacing = false
							}
							.disabled(isChecking)
						}
					}
					if let problem {
						Text(problem)
							.font(.caption)
							.foregroundStyle(.red)
					}
					Link("Get a free key at console.groq.com", destination: URL(string: "https://console.groq.com/keys")!)
						.font(.caption)
				}
			}
			Spacer(minLength: 8)
			if !showsEntry {
				Image(systemName: "checkmark.circle.fill")
					.font(.title3)
					.foregroundStyle(.green)
					.accessibilityLabel("Done")
			}
		}
		.padding(.vertical, 12)
	}

	private func save() {
		guard !isChecking else {
			return
		}
		isChecking = true
		problem = nil
		Task {
			do {
				try await setup.saveAPIKey(key)
				key = ""
				isReplacing = false
			} catch let error as BuddyError {
				problem = error.userMessage
			} catch {
				problem = "Couldn't check the key. Try again."
			}
			isChecking = false
		}
	}
}

struct VoiceTip: View {
	/// The first macOS version known to call the pane "Read & Speak" rather than "Spoken Content".
	/// Verified on 27.2 (and "Spoken Content" on 15); whether 26 already had the new name is unconfirmed.
	nonisolated static let readAndSpeakMajorVersion = 27

	let setup: SetupMonitor

	/// Where to download a better voice, using the pane's name on this version of macOS.
	nonisolated static func instructions(for version: OperatingSystemVersion) -> String {
		let pane = version.majorVersion >= readAndSpeakMajorVersion ? "Read & Speak" : "Spoken Content"
		return "In System Settings, search for \"System voice\" (it's in Accessibility › \(pane)), open the voice menu, choose Manage Voices, and download an Enhanced or Premium voice. Buddy uses it automatically."
	}

	var body: some View {
		HStack(alignment: .top, spacing: 10) {
			Image(systemName: "waveform")
				.foregroundStyle(.secondary)
			VStack(alignment: .leading, spacing: 4) {
				Text("Optional: a more natural voice")
					.font(.caption.weight(.semibold))
				Text(Self.instructions(for: ProcessInfo.processInfo.operatingSystemVersion))
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
				Button("Open Accessibility Settings", action: setup.openVoiceSettings)
					.font(.caption)
					.buttonStyle(.link)
			}
		}
	}
}

private extension Permission {
	var title: String {
		switch self {
		case .microphone:
			return "Microphone"
		case .speechRecognition:
			return "Speech Recognition"
		case .accessibility:
			return "Accessibility"
		case .screenRecording:
			return "Screen Recording"
		}
	}

	var reason: String {
		switch self {
		case .microphone:
			return "To hear your questions and dictation while you hold the hotkey."
		case .speechRecognition:
			return "To turn your speech into text, on your Mac when possible."
		case .accessibility:
			return "For the hotkey, pasting Draft text, and finding what to point at."
		case .screenRecording:
			return "To see your screen when you ask. Buddy never sees its own windows, and doesn't look while a password field is active."
		}
	}

	var symbol: String {
		switch self {
		case .microphone:
			return "mic"
		case .speechRecognition:
			return "waveform"
		case .accessibility:
			return "accessibility"
		case .screenRecording:
			return "rectangle.dashed.badge.record"
		}
	}
}
