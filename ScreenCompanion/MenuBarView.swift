import BuddyCore
import SwiftUI

/// The menu bar popover: mode toggle, start without the hotkey, and app controls.
struct MenuBarView: View {
	let coordinator: BuddyCoordinator
	let setup: SetupMonitor
	let openSetup: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Buddy")
				.font(.headline)

			if let warning = Self.setupWarning(for: setup.checklist) {
				Button(action: openSetup) {
					Label(warning, systemImage: "exclamationmark.triangle.fill")
						.frame(maxWidth: .infinity, alignment: .leading)
				}
				.buttonStyle(.bordered)
				.tint(.orange)
			}

			Picker("Mode", selection: modeBinding) {
				ForEach(BuddyMode.allCases, id: \.self) { mode in
					Text(mode.title).tag(mode)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()

			Button(action: toggleListening) {
				Text(listenButtonTitle)
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.tint(Theme.accent)

			Text("Or hold ⌃⌥ anywhere to talk.")
				.font(.caption)
				.foregroundStyle(.secondary)

			Toggle("Speak answers", isOn: speakAnswersBinding)
				.toggleStyle(.switch)
				.controlSize(.small)

			Divider()

			Button("Setup…", action: openSetup)
				.buttonStyle(.plain)

			Button("Quit Buddy") {
				NSApplication.shared.terminate(nil)
			}
			.buttonStyle(.plain)
		}
		.padding(14)
		.frame(width: 240)
	}

	/// The warning at the top of the menu while setup is incomplete, or nil once it's done.
	static func setupWarning(for checklist: SetupChecklist) -> String? {
		guard !checklist.isComplete else {
			return nil
		}
		let remaining = checklist.remainingCount
		return remaining == 1 ? "Setup: 1 step left" : "Setup: \(remaining) steps left"
	}

	private var modeBinding: Binding<BuddyMode> {
		Binding(
			get: { coordinator.mode },
			set: { coordinator.setMode($0) }
		)
	}

	private var speakAnswersBinding: Binding<Bool> {
		Binding(
			get: { !coordinator.isMuted },
			set: { coordinator.setMuted(!$0) }
		)
	}

	private var isListening: Bool {
		if case .listening = coordinator.state {
			return true
		}
		return false
	}

	private var listenButtonTitle: String {
		if isListening {
			return "Stop"
		}
		return "Start \(coordinator.mode.title)"
	}

	private func toggleListening() {
		if isListening {
			coordinator.stopListening()
		} else {
			coordinator.startListening()
		}
	}
}

/// The menu bar icon. It reflects the current mode, and is where the mark rests.
/// While setup is incomplete it shows a warning instead: menu bar icons are single-colour templates,
/// so a coloured badge wouldn't show reliably.
struct MenuBarIcon: View {
	let coordinator: BuddyCoordinator
	let setup: SetupMonitor

	var body: some View {
		Image(systemName: Self.symbolName(mode: coordinator.mode, setupComplete: setup.checklist.isComplete))
	}

	static func symbolName(mode: BuddyMode, setupComplete: Bool) -> String {
		guard setupComplete else {
			return "exclamationmark.triangle"
		}
		switch mode {
		case .ask:
			return "questionmark.bubble"
		case .draft:
			return "text.cursor"
		}
	}
}
