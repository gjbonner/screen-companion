import AppKit
import BuddyCore
import SwiftUI

/// A floating panel that never takes focus and lets every click pass through to the app underneath.
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

/// Shows the pill on the display under the cursor whenever a request starts.
@MainActor
final class PillPanelController {
	private static let panelSize = NSSize(width: 460, height: 220)
	private static let bottomMargin: CGFloat = 16

	private let coordinator: BuddyCoordinator
	private let panel = PillPanel(size: panelSize)
	private var wasVisible = false

	init(coordinator: BuddyCoordinator) {
		self.coordinator = coordinator
		let host = NSHostingView(rootView: PillView(coordinator: coordinator))
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
