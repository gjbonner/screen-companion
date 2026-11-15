import AppKit
import ApplicationServices
import Testing
@testable import ScreenCompanion

/// Opt-in: sends a real ⌘V into a test window and uses the real clipboard. Needs Accessibility granted to ScreenCompanion.
///
/// Run with:
/// `TEST_RUNNER_BUDDY_INTEGRATION=1 xcodebuild test -project ScreenCompanion.xcodeproj -scheme ScreenCompanion -destination 'platform=macOS'`
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BUDDY_INTEGRATION"] == "1"))
struct DraftInsertionIntegrationTests {
	@Test
	func draftTextIsPastedAndTheClipboardIsRestored() async throws {
		try #require(AXIsProcessTrusted(), "Grant Accessibility to ScreenCompanion first.")

		let pasteboard = NSPasteboard.general
		let original = try #require(pasteboard.pasteboardItems).map { item in
			item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
		}
		defer {
			// Leave the clipboard as the test found it.
			pasteboard.clearContents()
			pasteboard.writeObjects(original.map { contents in
				let item = NSPasteboardItem()
				for (type, data) in contents {
					item.setData(data, forType: type)
				}
				return item
			})
		}
		pasteboard.clearContents()
		pasteboard.setString("What was on the clipboard", forType: .string)

		let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
		let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
		window.contentView = textView
		NSApp.activate()
		window.makeKeyAndOrderFront(nil)
		window.makeFirstResponder(textView)
		defer {
			window.orderOut(nil)
		}
		try await Task.sleep(for: .milliseconds(300))

		// The test runs inside the app, so the frontmost process is Buddy's own; allow pasting into it here.
		let inserter = ClipboardTextInserter(restoreDelay: .milliseconds(400), ownProcess: nil)
		let result = await inserter.insert("Hi Greg, the budget looks right.")
		#expect(result == .inserted)

		try await Task.sleep(for: .milliseconds(800))
		#expect(textView.string == "Hi Greg, the budget looks right.")
		#expect(pasteboard.string(forType: .string) == "What was on the clipboard")
	}
}
