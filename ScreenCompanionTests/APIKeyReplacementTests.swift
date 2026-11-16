import BuddyCore
import Foundation
import Testing
@testable import ScreenCompanion

/// Saving a key from Setup, including replacing one Groq has started rejecting.
@MainActor
struct APIKeyReplacementTests {
	private static let savedKey = "gsk_saved"

	@Test
	func rejectedReplacementKeepsTheSavedKey() async {
		let store = InMemoryKeyStore(key: Self.savedKey)
		let rejection = BuddyError("Groq didn't accept the API key. Check it in Setup.")
		let setup = SetupMonitor(apiKeys: store, validateKey: { _ in
			throw rejection
		})

		await #expect(throws: rejection) {
			try await setup.saveAPIKey("gsk_bad")
		}
		#expect(store.apiKey() == Self.savedKey)
		#expect(setup.checklist.hasAPIKey)
	}

	@Test
	func acceptedReplacementIsSavedTrimmed() async throws {
		let store = InMemoryKeyStore(key: Self.savedKey)
		let checked = CheckedKeys()
		let setup = SetupMonitor(apiKeys: store, validateKey: { key in
			checked.append(key)
		})

		try await setup.saveAPIKey("  gsk_new\n")

		#expect(checked.keys == ["gsk_new"])
		#expect(store.apiKey() == "gsk_new")
		#expect(setup.checklist.hasAPIKey)
	}

	@Test
	func firstKeyIsSavedAndCompletesTheKeyStep() async throws {
		let store = InMemoryKeyStore(key: nil)
		let setup = SetupMonitor(apiKeys: store, validateKey: { _ in })
		#expect(!setup.checklist.hasAPIKey)

		try await setup.saveAPIKey("gsk_first")

		#expect(store.apiKey() == "gsk_first")
		#expect(setup.checklist.hasAPIKey)
	}

	@Test(arguments: ["", "   ", "\n\t"])
	func blankKeyIsRefusedWithoutCheckingIt(_ blank: String) async {
		let store = InMemoryKeyStore(key: Self.savedKey)
		let checked = CheckedKeys()
		let setup = SetupMonitor(apiKeys: store, validateKey: { key in
			checked.append(key)
		})

		await #expect(throws: BuddyError("Paste your Groq API key first.")) {
			try await setup.saveAPIKey(blank)
		}
		#expect(checked.keys.isEmpty)
		#expect(store.apiKey() == Self.savedKey)
	}
}

/// A key store that never touches the Keychain.
private final class InMemoryKeyStore: SavedAPIKeyStore, @unchecked Sendable {
	private let lock = NSLock()
	private var key: String?

	init(key: String?) {
		self.key = key
	}

	func apiKey() -> String? {
		lock.withLock {
			key
		}
	}

	func save(_ key: String) throws {
		lock.withLock {
			self.key = key
		}
	}
}

/// Records which keys were sent to be checked.
private final class CheckedKeys: @unchecked Sendable {
	private let lock = NSLock()
	private var recorded: [String] = []

	var keys: [String] {
		lock.withLock {
			recorded
		}
	}

	func append(_ key: String) {
		lock.withLock {
			recorded.append(key)
		}
	}
}
