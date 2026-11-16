import AppKit
import BuddyCore
import SwiftUI

/// Shows the mark pointing at what an Ask answer refers to.
///
/// When an answer's point has been located, the controller covers that display with a click-through panel and the
/// mark flies there from the menu bar. When the answer ends, the mark flies back.
/// The panel belongs to Buddy, so it's left out of Buddy's own screenshots like every other Buddy window.
@MainActor
final class PointOverlayController {
	/// How long the return flight takes before the panel is taken off screen.
	private static let returnDuration: Duration = .milliseconds(700)

	private let coordinator: BuddyCoordinator
	private let panel = PillPanel(size: .zero)
	private let model = PointOverlayModel()
	/// The point currently shown.
	private var current: Pointing?
	private var hideTask: Task<Void, Never>?

	init(coordinator: BuddyCoordinator) {
		self.coordinator = coordinator
		let host = NSHostingView(rootView: PointOverlayView(model: model))
		host.sizingOptions = []
		panel.contentView = host
		observeState()
	}

	private func observeState() {
		withObservationTracking {
			_ = coordinator.state
		} onChange: { [weak self] in
			DispatchQueue.main.async {
				self?.stateChanged()
				self?.observeState()
			}
		}
	}

	private func stateChanged() {
		var pointing: Pointing?
		if case .answering(_, let point, _) = coordinator.state {
			pointing = point
		}
		guard pointing != current else {
			return
		}
		current = pointing
		if let pointing {
			show(pointing)
		} else {
			flyBack()
		}
	}

	private func show(_ pointing: Pointing) {
		hideTask?.cancel()
		let display = pointing.displayFrame
		panel.setFrame(display, display: false)
		panel.orderFrontRegardless()
		model.present(
			highlight: OverlayGeometry.highlight(for: pointing.target, in: display),
			from: OverlayGeometry.viewPoint(Self.menuBarIconPoint(on: display), in: display),
			reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		)
	}

	private func flyBack() {
		guard model.markVisible else {
			return
		}
		model.dismiss()
		hideTask = Task { [weak self] in
			try? await Task.sleep(for: Self.returnDuration)
			guard !Task.isCancelled, let self, current == nil else {
				return
			}
			panel.orderOut(nil)
		}
	}

	/// Where the mark rests: Buddy's menu bar icon on this display.
	///
	/// If the icon's window is on another display, the same spot is used on this one: menu bar icons sit at the same
	/// distance from the right edge on every display's menu bar.
	private static func menuBarIconPoint(on display: CGRect) -> CGPoint {
		let statusWindows = NSApp.windows.filter { $0.className.contains("StatusBarWindow") }
		let centers = statusWindows.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
		if let onThisDisplay = centers.first(where: { display.contains($0) }) {
			return onThisDisplay
		}
		if let elsewhere = centers.first,
			let iconScreen = NSScreen.screens.first(where: { $0.frame.contains(elsewhere) }) {
			let fromRightEdge = iconScreen.frame.maxX - elsewhere.x
			let fromTopEdge = iconScreen.frame.maxY - elsewhere.y
			return CGPoint(x: display.maxX - fromRightEdge, y: display.maxY - fromTopEdge)
		}
		return CGPoint(x: display.maxX - 60, y: display.maxY - 12)
	}
}

// MARK: - Geometry

enum OverlayGeometry {
	static let framePadding: CGFloat = 4
	/// How far the mark sits outside the highlight's top-right corner.
	static let markOffset: CGFloat = 8
	/// Keeps the mark fully on screen.
	static let edgeInset: CGFloat = 16

	/// Converts an AppKit global point to the overlay view, which covers `display` with a top-left origin.
	static func viewPoint(_ point: CGPoint, in display: CGRect) -> CGPoint {
		CGPoint(x: point.x - display.minX, y: display.maxY - point.y)
	}

	static func viewRect(_ rect: CGRect, in display: CGRect) -> CGRect {
		CGRect(x: rect.minX - display.minX, y: display.maxY - rect.maxY, width: rect.width, height: rect.height)
	}

	/// The highlight around the target, in the overlay view's coordinates (top-left origin).
	static func highlight(for target: PointTarget, in display: CGRect) -> CGRect {
		viewRect(target.frame, in: display).insetBy(dx: -framePadding, dy: -framePadding)
	}

	/// Where the mark settles: just outside the highlight's top-right corner, kept on the display.
	static func markPoint(for highlight: CGRect, displaySize: CGSize) -> CGPoint {
		let point = CGPoint(x: highlight.maxX + markOffset, y: highlight.minY - markOffset)
		return CGPoint(
			x: min(max(point.x, edgeInset), displaySize.width - edgeInset),
			y: min(max(point.y, edgeInset), displaySize.height - edgeInset)
		)
	}
}

// MARK: - Model

@MainActor
@Observable
final class PointOverlayModel {
	private(set) var start: CGPoint = .zero
	private(set) var highlight: CGRect?
	/// 0 at the menu bar, 1 at the target. Animated along a curve.
	private(set) var progress: CGFloat = 0
	private(set) var markVisible = false
	private(set) var highlightVisible = false
	private var reduceMotion = false

	func present(highlight: CGRect, from start: CGPoint, reduceMotion: Bool) {
		self.highlight = highlight
		self.start = start
		self.reduceMotion = reduceMotion
		highlightVisible = false
		if reduceMotion {
			progress = 1
			withAnimation(.easeOut(duration: 0.25)) {
				markVisible = true
				highlightVisible = true
			}
			return
		}
		progress = 0
		markVisible = true
		withAnimation(.spring(duration: 0.7, bounce: 0.2)) {
			progress = 1
		} completion: { [weak self] in
			withAnimation(.easeOut(duration: 0.2)) {
				self?.highlightVisible = true
			}
		}
	}

	func dismiss() {
		withAnimation(.easeIn(duration: 0.15)) {
			highlightVisible = false
		}
		if reduceMotion {
			withAnimation(.easeIn(duration: 0.25)) {
				markVisible = false
			}
			return
		}
		withAnimation(.spring(duration: 0.6, bounce: 0)) {
			progress = 0
		} completion: { [weak self] in
			self?.markVisible = false
		}
	}
}

// MARK: - Views

struct PointOverlayView: View {
	let model: PointOverlayModel

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .topLeading) {
				if let highlight = model.highlight {
					HighlightView(highlight: highlight)
						.opacity(model.highlightVisible ? 1 : 0)

					MarkView()
						.modifier(CurvedFlight(
							progress: model.progress,
							start: model.start,
							end: OverlayGeometry.markPoint(for: highlight, displaySize: geometry.size),
							bounds: geometry.size
						))
						.opacity(model.markVisible ? 1 : 0)
				}
			}
			.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
		}
		.allowsHitTesting(false)
	}
}

private struct HighlightView: View {
	let highlight: CGRect

	var body: some View {
		RoundedRectangle(cornerRadius: 6, style: .continuous)
			.fill(Theme.highlight.opacity(0.12))
			.overlay {
				RoundedRectangle(cornerRadius: 6, style: .continuous)
					.strokeBorder(Theme.highlight, lineWidth: 2.5)
			}
			.frame(width: highlight.width, height: highlight.height)
			.position(x: highlight.midX, y: highlight.midY)
	}
}

/// Buddy's mark: a purple dot with a white ring, the same mark as in the app icon.
private struct MarkView: View {
	var body: some View {
		Circle()
			.fill(Theme.accent)
			.overlay {
				Circle().strokeBorder(.white, lineWidth: 2)
			}
			.frame(width: 18, height: 18)
			.shadow(color: .black.opacity(0.3), radius: 4, y: 2)
	}
}

/// Moves a view along a curve from `start` to `end` as `progress` animates from 0 to 1.
private struct CurvedFlight: ViewModifier, Animatable {
	var progress: CGFloat
	let start: CGPoint
	let end: CGPoint
	/// The display's size; the whole flight stays inside it.
	let bounds: CGSize

	nonisolated var animatableData: CGFloat {
		get { progress }
		set { progress = newValue }
	}

	func body(content: Content) -> some View {
		content.position(Self.point(at: progress, from: start, to: end, within: bounds))
	}

	/// A quadratic curve bowing toward the middle of the display, so the flight arcs rather than slides
	/// and never leaves the screen. A quadratic curve stays within the triangle of its three points, so keeping
	/// the control point on the display keeps the whole flight on it.
	static func point(at t: CGFloat, from start: CGPoint, to end: CGPoint, within bounds: CGSize) -> CGPoint {
		let dx = end.x - start.x
		let dy = end.y - start.y
		let length = (dx * dx + dy * dy).squareRoot()
		guard length > 0 else {
			return end
		}
		let bow = min(length * 0.25, 160)
		let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
		let normal = CGPoint(x: -dy / length, y: dx / length)
		let towardCenter = (bounds.width / 2 - mid.x) * normal.x + (bounds.height / 2 - mid.y) * normal.y
		let side: CGFloat = towardCenter >= 0 ? 1 : -1
		let control = CGPoint(
			x: min(max(mid.x + normal.x * bow * side, 0), bounds.width),
			y: min(max(mid.y + normal.y * bow * side, 0), bounds.height)
		)
		let u = 1 - t
		return CGPoint(
			x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
			y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
		)
	}
}
