import BuddyCore
import SwiftUI

/// The pill: shows the mode, mic level and live transcript while listening, then progress, answers and notices.
struct PillView: View {
	let coordinator: BuddyCoordinator

	var body: some View {
		VStack {
			Spacer(minLength: 0)
			if coordinator.state != .idle {
				content
					.padding(.horizontal, 16)
					.padding(.vertical, 10)
					.frame(maxWidth: 420)
					.fixedSize(horizontal: false, vertical: true)
					.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
					.overlay(
						RoundedRectangle(cornerRadius: 20, style: .continuous)
							.strokeBorder(.white.opacity(0.12))
					)
					.shadow(color: .black.opacity(0.18), radius: 10, y: 4)
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
		.padding(.bottom, 8)
		.animation(.spring(duration: 0.3), value: coordinator.state)
		.animation(.spring(duration: 0.25), value: coordinator.mode)
	}

	@ViewBuilder
	private var content: some View {
		switch coordinator.state {
		case .idle:
			EmptyView()

		case .listening(let transcript, let level):
			VStack(alignment: .leading, spacing: 6) {
				HStack(spacing: 10) {
					ModeBadge(mode: coordinator.mode)
					LevelMeter(level: level)
					Text(transcript.isEmpty ? "Listening…" : transcript)
						.font(.callout)
						.foregroundStyle(transcript.isEmpty ? .secondary : .primary)
						.lineLimit(1)
						.truncationMode(.head)
						.frame(maxWidth: .infinity, alignment: .leading)
				}
				Text("Tab to switch to \(coordinator.mode.toggled.title) · Esc to cancel")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}

		case .thinking:
			HStack(spacing: 10) {
				ModeBadge(mode: coordinator.mode)
				ProgressView()
					.controlSize(.small)
				Text(coordinator.mode == .ask ? "Thinking…" : "Cleaning up…")
					.font(.callout)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
			}

		case .answering(let text, _):
			HStack(alignment: .top, spacing: 10) {
				ModeBadge(mode: .ask)
				Text(text)
					.font(.callout)
					.lineLimit(4)
					.frame(maxWidth: .infinity, alignment: .leading)
			}

		case .message(let message):
			HStack(spacing: 10) {
				Image(systemName: message.kind == .problem ? "exclamationmark.circle.fill" : "info.circle.fill")
					.foregroundStyle(message.kind == .problem ? Color.orange : Theme.accent)
				Text(message.text)
					.font(.callout)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
	}
}

private struct ModeBadge: View {
	let mode: BuddyMode

	var body: some View {
		Label(mode.title, systemImage: mode == .ask ? "questionmark.bubble.fill" : "text.cursor")
			.font(.caption.weight(.semibold))
			.labelStyle(.titleAndIcon)
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
			.background(Theme.accent.opacity(0.18), in: Capsule())
			.foregroundStyle(Theme.accent)
			.contentTransition(.opacity)
	}
}

private struct LevelMeter: View {
	let level: Float

	private let barWeights: [Float] = [0.5, 0.8, 1.0, 0.8, 0.5]

	var body: some View {
		HStack(spacing: 2) {
			ForEach(barWeights.indices, id: \.self) { index in
				Capsule()
					.fill(Theme.accent)
					.frame(width: 3, height: barHeight(weight: barWeights[index]))
			}
		}
		.frame(height: 18)
		.animation(.easeOut(duration: 0.08), value: level)
	}

	private func barHeight(weight: Float) -> CGFloat {
		CGFloat(4 + 14 * min(max(level * weight, 0), 1))
	}
}
