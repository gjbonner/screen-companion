import AppKit
import ApplicationServices
import BuddyCore

/// Snaps the model's guess to the real UI element there, using Accessibility (ADR 0004).
///
/// It asks which element is at the guess and at points around it, adds each one's parents (so the text inside
/// a button also yields the button), and lets `SnapGuardrails` pick one or keep the guess.
struct AccessibilitySnapper: Sendable {
	/// Where elements are looked up, relative to the guess: the guess itself, then rings at half and full snapping distance.
	static let sampleOffsets: [CGVector] = {
		var offsets = [CGVector(dx: 0, dy: 0)]
		for radius in [SnapGuardrails.maxDistance / 2, SnapGuardrails.maxDistance] {
			for step in 0..<8 {
				let angle = Double(step) * .pi / 4
				offsets.append(CGVector(dx: radius * cos(angle), dy: radius * sin(angle)))
			}
		}
		return offsets
	}()

	/// How many parents of each element found are also considered.
	static let ancestorLevels = 3

	/// Buddy's own windows are skipped when they're on top of the guess. Tests can pass another process.
	var ownProcess: pid_t = ProcessInfo.processInfo.processIdentifier
	/// Longest wait for any one Accessibility call, in seconds, so a slow app can't hold up pointing.
	var messagingTimeout: Float = 0.1

	/// Where to point for the model's guess on the captured screen, or nil if the guess is outside the screenshot.
	@MainActor
	func target(for guess: PointGuess, on screen: CapturedScreen) async -> PointTarget? {
		guard let point = CoordinateMapper(screen: screen).screenPoint(forImagePoint: guess.imagePoint) else {
			Log.point.info("Guess \(String(describing: guess.imagePoint), privacy: .public) is outside the screenshot")
			return nil
		}
		guard AXIsProcessTrusted(), let primaryDisplayHeight = NSScreen.screens.first?.frame.height else {
			return .guess(point)
		}
		let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
		let started = ContinuousClock.now
		let candidates = await Task.detached { [self] in
			candidates(near: point, primaryDisplayHeight: primaryDisplayHeight, frontmostProcess: frontmost)
		}.value
		let target = SnapGuardrails.target(guess: point, label: guess.label, candidates: candidates, displayFrame: screen.displayFrame)
		Log.point.info("""
			Guess \(String(describing: guess.imagePoint), privacy: .public) "\(guess.label, privacy: .public)" → \
			\(String(describing: point), privacy: .public), \(candidates.count, privacy: .public) candidates in \
			\(ContinuousClock.now - started, privacy: .public), target \(String(describing: target), privacy: .public)
			""")
		return target
	}

	// MARK: - Lookup

	private func candidates(near point: CGPoint, primaryDisplayHeight: CGFloat, frontmostProcess: pid_t?) -> [SnapCandidate] {
		let systemWide = AXUIElementCreateSystemWide()
		AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
		var frontmostApp: AXUIElement?
		if let frontmostProcess, frontmostProcess != ownProcess {
			let app = AXUIElementCreateApplication(frontmostProcess)
			AXUIElementSetMessagingTimeout(app, messagingTimeout)
			frontmostApp = app
		}

		var found: [SnapCandidate] = []
		for offset in Self.sampleOffsets {
			let screenPoint = CGPoint(x: point.x + offset.dx, y: point.y + offset.dy)
			let position = CoordinateMapper.accessibilityPoint(fromScreenPoint: screenPoint, primaryDisplayHeight: primaryDisplayHeight)
			guard let hit = element(at: position, systemWide: systemWide, underBuddyIn: frontmostApp) else {
				continue
			}
			for element in withAncestors(hit) {
				guard let candidate = candidate(for: element, primaryDisplayHeight: primaryDisplayHeight),
					!found.contains(candidate) else {
					continue
				}
				found.append(candidate)
			}
		}
		return found
	}

	/// The element at a point (Accessibility coordinates). If Buddy's own window is on top there, looks in the frontmost app instead.
	private func element(at position: CGPoint, systemWide: AXUIElement, underBuddyIn frontmostApp: AXUIElement?) -> AXUIElement? {
		var hit: AXUIElement?
		guard AXUIElementCopyElementAtPosition(systemWide, Float(position.x), Float(position.y), &hit) == .success,
			let hit else {
			return nil
		}
		var process: pid_t = 0
		AXUIElementGetPid(hit, &process)
		guard process == ownProcess else {
			return hit
		}
		guard let frontmostApp else {
			return nil
		}
		var underneath: AXUIElement?
		guard AXUIElementCopyElementAtPosition(frontmostApp, Float(position.x), Float(position.y), &underneath) == .success else {
			return nil
		}
		return underneath
	}

	/// The element and up to `ancestorLevels` parents, stopping below the window.
	private func withAncestors(_ element: AXUIElement) -> [AXUIElement] {
		var chain = [element]
		var current = element
		for _ in 0..<Self.ancestorLevels {
			guard let parent = parent(of: current) else {
				break
			}
			let role = string(kAXRoleAttribute, of: parent)
			if role == kAXWindowRole || role == kAXApplicationRole {
				break
			}
			chain.append(parent)
			current = parent
		}
		return chain
	}

	private func candidate(for element: AXUIElement, primaryDisplayHeight: CGFloat) -> SnapCandidate? {
		guard let frame = frame(of: element) else {
			return nil
		}
		let role = string(kAXRoleAttribute, of: element)
		return SnapCandidate(
			frame: CoordinateMapper.screenRect(fromAccessibilityRect: frame, primaryDisplayHeight: primaryDisplayHeight),
			role: role,
			label: label(of: element, role: role)
		)
	}

	// MARK: - Attributes

	/// The element's visible name: its title, description, text (for static text) or placeholder.
	private func label(of element: AXUIElement, role: String?) -> String? {
		var names = [kAXTitleAttribute, kAXDescriptionAttribute]
		if role == kAXStaticTextRole {
			names.append(kAXValueAttribute)
		}
		names.append(kAXPlaceholderValueAttribute)
		for name in names {
			if let text = string(name, of: element), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				return text
			}
		}
		return nil
	}

	/// The element's frame in Accessibility coordinates (origin top-left of the primary display).
	private func frame(of element: AXUIElement) -> CGRect? {
		var origin = CGPoint.zero
		var size = CGSize.zero
		guard let position = axValue(kAXPositionAttribute, of: element),
			AXValueGetValue(position, .cgPoint, &origin),
			let sizeValue = axValue(kAXSizeAttribute, of: element),
			AXValueGetValue(sizeValue, .cgSize, &size) else {
			return nil
		}
		return CGRect(origin: origin, size: size)
	}

	private func parent(of element: AXUIElement) -> AXUIElement? {
		guard let value = copyAttribute(kAXParentAttribute, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else {
			return nil
		}
		return (value as! AXUIElement)
	}

	private func axValue(_ name: String, of element: AXUIElement) -> AXValue? {
		guard let value = copyAttribute(name, of: element), CFGetTypeID(value) == AXValueGetTypeID() else {
			return nil
		}
		return (value as! AXValue)
	}

	private func string(_ name: String, of element: AXUIElement) -> String? {
		copyAttribute(name, of: element) as? String
	}

	private func copyAttribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
		var value: CFTypeRef?
		guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
			return nil
		}
		return value
	}
}
