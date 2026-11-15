import BuddyCore
import SwiftUI

/// The pill: shows the mode, mic level and live transcript while listening, then progress, answers and notices.
struct PillView: View {
	let coordinator: BuddyCoordinator
	/// Reports where the mute button is, so the panel can accept clicks there and nowhere else.
	var onMuteButtonFrame: (CGRect?) -> Void = { _ in }

	var body: some View {
		VStack {
			Spacer(minLength: 0)
			if coordinator.state != .idle {
				content
					.padding(.horizontal, 16)
					.padding(.vertical, 10)
					.frame(maxWidth: 420)
					.fixedSize(horizontal: false, vertical: true)
					.background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
					.environment(\.colorScheme, .dark)
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
		.onChange(of: isAnswering) {
			if !isAnswering {
				onMuteButtonFrame(nil)
			}
		}
	}

	private var isAnswering: Bool {
		if case .answering = coordinator.state {
			return true
		}
		return false
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

		case .answering(let text, _, let spokenLength):
			HStack(alignment: .top, spacing: 10) {
				ModeBadge(mode: .ask)
				AnswerCard(text: text, spokenLength: coordinator.isMuted ? text.count : spokenLength)
				MuteButton(isMuted: coordinator.isMuted) {
					coordinator.toggleMuted()
				}
				.onGeometryChange(for: CGRect.self) { proxy in
					proxy.frame(in: .global)
				} action: { frame in
					onMuteButtonFrame(frame)
				}
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

/// Turns spoken answers on and off. The only clickable spot in the pill.
private struct MuteButton: View {
	let isMuted: Bool
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
				.font(.callout)
				.foregroundStyle(isMuted ? Color.secondary : Theme.accent)
				.frame(width: 28, height: 28)
				.contentShape(Circle())
				.contentTransition(.symbolEffect(.replace))
		}
		.buttonStyle(.plain)
		.help(isMuted ? "Speak answers" : "Mute answers")
		.accessibilityLabel(isMuted ? "Unmute answers" : "Mute answers")
	}
}

/// The answer text: what has been spoken in full color, the rest dimmed.
/// Long answers scroll in step with speech instead of growing over the screen.
private struct AnswerCard: View {
	let text: String
	let spokenLength: Int

	/// About ten lines. Normal answers (one to three sentences) fit without scrolling.
	private static let maxHeight: CGFloat = 200

	@State private var position = ScrollPosition(y: 0)
	@State private var contentHeight: CGFloat = 0

	var body: some View {
		ScrollView(.vertical, showsIndicators: false) {
			(Text(spoken).foregroundStyle(.primary) + Text(unspoken).foregroundStyle(.secondary))
				.font(.callout)
				.fixedSize(horizontal: false, vertical: true)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.vertical, 4)
				.onGeometryChange(for: CGFloat.self) { proxy in
					proxy.size.height
				} action: { height in
					contentHeight = height
				}
		}
		.frame(height: min(max(contentHeight, 1), Self.maxHeight))
		.scrollPosition($position)
		.onChange(of: spokenLength) {
			guard contentHeight > Self.maxHeight, !text.isEmpty else {
				return
			}
			// Keep the part being spoken in view, a little below the top.
			let fraction = Double(spokenLength) / Double(text.count)
			let target = max(0, min(contentHeight * fraction - Self.maxHeight * 0.6, contentHeight - Self.maxHeight))
			withAnimation(.easeInOut(duration: 0.4)) {
				position.scrollTo(y: target)
			}
		}
	}

	private var spoken: String {
		String(text.prefix(spokenLength))
	}

	private var unspoken: String {
		String(text.dropFirst(spokenLength))
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
