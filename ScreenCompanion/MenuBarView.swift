import BuddyCore
import SwiftUI

/// The menu bar popover: mode toggle, start without the hotkey, and app controls.
struct MenuBarView: View {
	let coordinator: BuddyCoordinator

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Buddy")
				.font(.headline)

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

			Button("Quit Buddy") {
				NSApplication.shared.terminate(nil)
			}
			.buttonStyle(.plain)
		}
		.padding(14)
		.frame(width: 240)
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
struct MenuBarIcon: View {
	let coordinator: BuddyCoordinator

	var body: some View {
		Image(systemName: symbolName)
	}

	private var symbolName: String {
		switch coordinator.mode {
		case .ask:
			return "questionmark.bubble"
		case .draft:
			return "text.cursor"
		}
	}
}
