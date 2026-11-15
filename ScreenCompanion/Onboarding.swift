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
	@ObservationIgnored private let apiKeys: KeychainAPIKeyStore
	@ObservationIgnored private var timer: Timer?

	init(apiKeys: KeychainAPIKeyStore = KeychainAPIKeyStore()) {
		self.apiKeys = apiKeys
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
		case .done, .enterKey:
			return
		case .allow:
			await permissions.request(permission)
		case .openSettings:
			// The first request shows macOS's own prompt, whose button opens System Settings; opening it as well
			// would show both. macOS only prompts once, so after that Buddy opens Settings itself.
			let askedKey = Self.askedKey(for: permission)
			if UserDefaults.standard.bool(forKey: askedKey) {
				permissions.openSettings(for: permission)
			} else {
				UserDefaults.standard.set(true, forKey: askedKey)
				await permissions.request(permission)
			}
			if permission == .screenRecording {
				UserDefaults.standard.set(true, forKey: Self.screenRecordingRequestedKey)
			}
		case .relaunch:
			relaunch()
		}
		refresh()
	}

	/// Checks the key with Groq, then saves it to the Keychain. Throws a user-facing error.
	func saveAPIKey(_ key: String) async throws {
		let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			throw BuddyError("Paste your Groq API key first.")
		}
		try await GroqClient.validate(key: trimmed)
		try apiKeys.save(trimmed)
		refresh()
	}

	func openVoiceSettings() {
		if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess") {
			NSWorkspace.shared.open(url)
		}
	}

	/// Starts a new copy of Buddy once this one has quit, so Screen Recording takes effect.
	private func relaunch() {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
		do {
			try process.run()
			NSApp.terminate(nil)
		} catch {
			Log.pill.error("Couldn't relaunch: \(error.localizedDescription, privacy: .public)")
		}
	}

	/// Whether Buddy has already asked macOS for this permission, so its one-time prompt has been shown.
	private static func askedKey(for permission: Permission) -> String {
		"asked.\(permission)"
	}

	private static func readChecklist(permissions: SystemPermissionChecker, apiKeys: KeychainAPIKeyStore) -> SetupChecklist {
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
/// behind it. Whenever a step changes, the window comes back to the front, and it closes itself shortly after
/// everything is in place.
@MainActor
final class OnboardingWindowController {
	private static let closeDelay: Duration = .milliseconds(1500)

	private let setup: SetupMonitor
	private var window: NSWindow?
	private var closeTask: Task<Void, Never>?

	init(setup: SetupMonitor) {
		self.setup = setup
		observeProgress()
	}

	func show() {
		if window == nil {
			let host = NSHostingController(rootView: OnboardingView(setup: setup))
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
		guard let window, window.isVisible else {
			return
		}
		// Bring the checklist back after the user flips a switch in System Settings or answers a prompt.
		NSApp.activate()
		window.makeKeyAndOrderFront(nil)
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
}

// MARK: - Views

struct OnboardingView: View {
	let setup: SetupMonitor

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			VStack(alignment: .leading, spacing: 4) {
				Text("Set up Buddy")
					.font(.title2.weight(.semibold))
				Text(setup.checklist.isComplete ? "You're all set. Hold ⌃⌥ anywhere to talk." : "Buddy needs a few things before it can help.")
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
				Text(action == .relaunch ? "Once it's switched on in System Settings, relaunch Buddy to use it." : permission.reason)
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
		case .openSettings:
			Button("Open Settings") {
				perform(.openSettings)
			}
		case .relaunch:
			// Settings stays reachable: the switch may not be on yet, for example after permissions were reset.
			VStack(alignment: .trailing, spacing: 6) {
				Button("Relaunch Buddy") {
					perform(.relaunch)
				}
				.buttonStyle(.borderedProminent)
				.tint(Theme.accent)
				Button("Open Settings") {
					perform(.openSettings)
				}
				.buttonStyle(.link)
				.font(.caption)
			}
		}
	}
}

private struct APIKeyRow: View {
	let setup: SetupMonitor
	@State private var key = ""
	@State private var isChecking = false
	@State private var problem: String?

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: "key")
				.font(.title3)
				.frame(width: 26)
				.foregroundStyle(Theme.accent)
			VStack(alignment: .leading, spacing: 6) {
				Text("Groq API key")
					.font(.body.weight(.medium))
				if setup.checklist.hasAPIKey {
					Text("Saved in your Keychain.")
						.font(.caption)
						.foregroundStyle(.secondary)
				} else {
					Text("Answers and Draft clean-up use Groq. A free key works.")
						.font(.caption)
						.foregroundStyle(.secondary)
					HStack {
						SecureField("gsk_…", text: $key)
							.textFieldStyle(.roundedBorder)
							.onSubmit(save)
						Button(isChecking ? "Checking…" : "Save", action: save)
							.disabled(isChecking || key.isEmpty)
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
			if setup.checklist.hasAPIKey {
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
			return "To hear your questions and dictation while you hold ⌃⌥."
		case .speechRecognition:
			return "To turn your speech into text, on your Mac when possible."
		case .accessibility:
			return "For the ⌃⌥ hotkey, pasting Draft text, and finding what to point at."
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
