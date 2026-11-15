import AppKit
import BuddyCore
import SwiftUI

/// A floating panel that never takes focus and lets clicks pass through to the app underneath.
final class PillPanel: NSPanel {
	init(size: NSSize) {
		super.init(
			contentRect: NSRect(origin: .zero, size: size),
			styleMask: [.nonactivatingPanel, .borderless],
			backing: .buffered,
			defer: false
		)
		isOpaque = false
		backgroundColor = .clear
		hasShadow = false
		ignoresMouseEvents = true
		level = .statusBar
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
		isReleasedWhenClosed = false
	}

	override var canBecomeKey: Bool {
		false
	}

	override var canBecomeMain: Bool {
		false
	}
}

/// Lets a click on a control work straight away, without first having to activate the window.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
		true
	}
}

/// Shows the pill on the display under the cursor whenever a request starts.
///
/// The pill is click-through, except over the mute button while an answer is showing:
/// the panel only accepts clicks while the pointer is inside that button.
@MainActor
final class PillPanelController {
	private static let panelSize = NSSize(width: 460, height: 420)
	private static let bottomMargin: CGFloat = 16

	private let coordinator: BuddyCoordinator
	private let panel = PillPanel(size: panelSize)
	private var wasVisible = false
	/// The mute button's frame in the panel's content view, top-left origin.
	private var muteButtonFrame: CGRect?
	private var pointerTimer: Timer?

	init(coordinator: BuddyCoordinator) {
		self.coordinator = coordinator
		let view = PillView(coordinator: coordinator) { [weak self] frame in
			self?.muteButtonFrame = frame
		}
		let host = FirstClickHostingView(rootView: view)
		host.sizingOptions = []
		panel.contentView = host
		// The panel stays ordered in, transparent and click-through; SwiftUI animates the pill in and out.
		panel.orderFrontRegardless()
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
		let visible = coordinator.state != .idle
		Log.pill.info("State: \(String(describing: self.coordinator.state), privacy: .public)")
		if visible, !wasVisible {
			moveToCursorDisplay()
			panel.orderFrontRegardless()
			Log.pill.info("Showing pill at \(NSStringFromRect(self.panel.frame), privacy: .public)")
		}
		wasVisible = visible

		if case .answering = coordinator.state {
			startTrackingPointer()
		} else {
			stopTrackingPointer()
		}
	}

	// MARK: - Clicks on the mute button only

	private func startTrackingPointer() {
		guard pointerTimer == nil else {
			return
		}
		pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.updateClickThrough()
			}
		}
	}

	private func stopTrackingPointer() {
		pointerTimer?.invalidate()
		pointerTimer = nil
		panel.ignoresMouseEvents = true
	}

	private func updateClickThrough() {
		guard let frame = muteButtonFrame, let content = panel.contentView else {
			panel.ignoresMouseEvents = true
			return
		}
		// Convert from SwiftUI's top-left window coordinates to screen coordinates.
		let panelFrame = panel.frame
		let onScreen = CGRect(
			x: panelFrame.minX + frame.minX,
			y: panelFrame.minY + content.bounds.height - frame.maxY,
			width: frame.width,
			height: frame.height
		)
		panel.ignoresMouseEvents = !onScreen.contains(NSEvent.mouseLocation)
	}

	private func moveToCursorDisplay() {
		let mouse = NSEvent.mouseLocation
		guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
			return
		}
		let visible = screen.visibleFrame
		let size = Self.panelSize
		let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + Self.bottomMargin)
		panel.setFrame(NSRect(origin: origin, size: size), display: false)
	}
}
