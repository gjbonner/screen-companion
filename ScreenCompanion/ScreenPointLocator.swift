import AppKit
import ApplicationServices
import BuddyCore

/// Finds where to point (ADR 0004).
///
/// The model names the right element far more reliably than it places it, so the label leads: Buddy looks for it
/// as text in the screenshot and as an Accessibility element name, in parallel, and the guess only breaks ties
/// between matches. If nothing matches, Buddy doesn't point.
struct ScreenPointLocator: PointLocator {
	let accessibility = AccessibilitySnapper()

	func locate(_ guess: PointGuess, on screen: CapturedScreen) async -> PointTarget? {
		guard let point = CoordinateMapper(screen: screen).screenPoint(forImagePoint: guess.imagePoint) else {
			Log.point.info("Guess \(String(describing: guess.imagePoint), privacy: .public) is outside the screenshot")
			return nil
		}
		let (trusted, primaryDisplayHeight, frontmost) = await MainActor.run {
			(AXIsProcessTrusted(), NSScreen.screens.first?.frame.height, NSWorkspace.shared.frontmostApplication?.processIdentifier)
		}
		let started = ContinuousClock.now

		async let textMatches = Task.detached(priority: .userInitiated) {
			ScreenTextFinder.candidates(matching: guess.label, in: screen)
		}.value
		async let elements = Task.detached(priority: .userInitiated) { [accessibility] () -> [SnapCandidate] in
			guard trusted, let primaryDisplayHeight else {
				return []
			}
			return accessibility.candidates(
				near: point,
				label: guess.label,
				primaryDisplayHeight: primaryDisplayHeight,
				frontmostProcess: frontmost
			)
		}.value
		let text = await textMatches
		let candidates = text + (await elements)

		let target = SnapGuardrails.target(guess: point, label: guess.label, candidates: candidates, displayFrame: screen.displayFrame)
		Log.point.info("""
			Guess \(String(describing: guess.imagePoint), privacy: .public) "\(guess.label, privacy: .public)" → \
			\(String(describing: point), privacy: .public); \(text.count, privacy: .public) text matches, \
			\(candidates.count - text.count, privacy: .public) elements in \(ContinuousClock.now - started, privacy: .public); \
			target \(String(describing: target), privacy: .public)
			""")
		#if DEBUG
		PointDebug.record(guess, screen: screen, target: target)
		#endif
		return target
	}
}
