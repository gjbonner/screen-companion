import AppKit
import ApplicationServices
import BuddyCore

/// Finds on-screen elements for pointing, using Accessibility (ADR 0004).
///
/// Two kinds of candidate: elements right around the guess (and their parents, so the text inside a button also
/// yields the button), and elements anywhere in the guess's window whose name matches the model's label. The second
/// covers icons with no visible text, such as Xcode's Run button, which text recognition can't find.
/// Blocking; call it off the main thread.
struct AccessibilitySnapper: Sendable {
	/// Where elements are looked up, relative to the guess: the guess itself, then rings at 10 and 20 pt.
	/// Only elements whose name matches count, so these mostly serve to find the window to search.
	static let sampleOffsets: [CGVector] = {
		var offsets = [CGVector(dx: 0, dy: 0)]
		for radius: CGFloat in [10, 20] {
			for step in 0..<8 {
				let angle = Double(step) * .pi / 4
				offsets.append(CGVector(dx: radius * cos(angle), dy: radius * sin(angle)))
			}
		}
		return offsets
	}()

	/// How many parents of each element found are also considered.
	static let ancestorLevels = 3
	/// Limits on the search of the window for a matching name, so a huge web page can't stall pointing.
	static let maxTreeNodes = 1500
	static let treeSearchBudget: Duration = .milliseconds(300)

	/// Buddy's own windows are skipped when they're on top of the guess. Tests can pass another process.
	var ownProcess: pid_t = ProcessInfo.processInfo.processIdentifier
	/// Longest wait for any one Accessibility call, in seconds, so a slow app can't hold up pointing.
	var messagingTimeout: Float = 0.1

	/// - Parameters:
	///   - point: the guess in AppKit global points.
	///   - primaryDisplayHeight: the height of the display with the menu bar, for converting to Accessibility coordinates.
	func candidates(near point: CGPoint, label: String, primaryDisplayHeight: CGFloat, frontmostProcess: pid_t?) -> [SnapCandidate] {
		let systemWide = AXUIElementCreateSystemWide()
		AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
		var frontmostApp: AXUIElement?
		if let frontmostProcess, frontmostProcess != ownProcess {
			let app = AXUIElementCreateApplication(frontmostProcess)
			AXUIElementSetMessagingTimeout(app, messagingTimeout)
			frontmostApp = app
		}

		var found: [SnapCandidate] = []
		var window: AXUIElement?
		for offset in Self.sampleOffsets {
			let screenPoint = CGPoint(x: point.x + offset.dx, y: point.y + offset.dy)
			let position = CoordinateMapper.accessibilityPoint(fromScreenPoint: screenPoint, primaryDisplayHeight: primaryDisplayHeight)
			guard let hit = element(at: position, systemWide: systemWide, underBuddyIn: frontmostApp) else {
				continue
			}
			if window == nil {
				window = self.window(of: hit)
			}
			for element in withAncestors(hit) {
				guard let candidate = candidate(for: element, primaryDisplayHeight: primaryDisplayHeight),
					!found.contains(candidate) else {
					continue
				}
				found.append(candidate)
			}
		}

		if let window {
			for match in nameMatches(for: label, in: window, primaryDisplayHeight: primaryDisplayHeight) where !found.contains(match) {
				found.append(match)
			}
		}
		return found
	}

	// MARK: - Lookup

	/// Elements in the window whose name matches the model's label.
	///
	/// Breadth-first, so shallow parts such as toolbars are reached before deep content, within node and time limits.
	private func nameMatches(for label: String, in window: AXUIElement, primaryDisplayHeight: CGFloat) -> [SnapCandidate] {
		let started = ContinuousClock.now
		let deadline = started + Self.treeSearchBudget
		var queue = [window]
		var next = 0
		var matches: [SnapCandidate] = []
		while next < queue.count, next < Self.maxTreeNodes, ContinuousClock.now < deadline {
			let element = queue[next]
			next += 1
			let role = string(kAXRoleAttribute, of: element)
			if let name = self.label(of: element, role: role),
				SnapGuardrails.labelsMatch(label, name),
				let frame = frame(of: element) {
				matches.append(SnapCandidate(
					frame: CoordinateMapper.screenRect(fromAccessibilityRect: frame, primaryDisplayHeight: primaryDisplayHeight),
					role: role,
					label: name
				))
			}
			queue.append(contentsOf: children(of: element))
		}
		Log.point.info("""
			Accessibility search for "\(label, privacy: .public)": \(matches.count, privacy: .public) matches, \
			\(next, privacy: .public) elements in \(ContinuousClock.now - started, privacy: .public)
			""")
		return matches
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

	/// The element's name: its title, description, text (for static text) or placeholder.
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
		self.element(kAXParentAttribute, of: element)
	}

	private func window(of element: AXUIElement) -> AXUIElement? {
		self.element(kAXWindowAttribute, of: element)
	}

	private func children(of element: AXUIElement) -> [AXUIElement] {
		guard let value = copyAttribute(kAXChildrenAttribute, of: element), CFGetTypeID(value) == CFArrayGetTypeID() else {
			return []
		}
		return (value as! [CFTypeRef]).compactMap { child in
			CFGetTypeID(child) == AXUIElementGetTypeID() ? (child as! AXUIElement) : nil
		}
	}

	private func element(_ name: String, of element: AXUIElement) -> AXUIElement? {
		guard let value = copyAttribute(name, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else {
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
