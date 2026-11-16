import BuddyCore
import Foundation
import Security

/// An API key store that setup can also save to. Tests provide an in-memory one.
protocol SavedAPIKeyStore: APIKeyStore {
	func save(_ key: String) throws
}

/// The Groq API key, stored in the user's Keychain.
///
/// Debug builds fall back to `GROQ_API_KEY` in the repo's gitignored `.env` when the Keychain has no key, so
/// development needs no setup. A key saved in Setup always wins, so it can be replaced. Release builds never look for that file.
struct KeychainAPIKeyStore: SavedAPIKeyStore {
	private static let service = "com.gilesbonner.screencompanion"
	private static let account = "groq-api-key"

	func apiKey() -> String? {
		if let key = Self.readKeychain() {
			return key
		}
		#if DEBUG
		return Self.keyFromDotEnv()
		#else
		return nil
		#endif
	}

	/// Replaces the saved key in place when there is one, so replacing never depends on deleting first.
	func save(_ key: String) throws {
		let data = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: Self.service,
			kSecAttrAccount as String: Self.account,
		]
		var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
		if status == errSecItemNotFound {
			var item = query
			item[kSecValueData as String] = data
			status = SecItemAdd(item as CFDictionary, nil)
		}
		guard status == errSecSuccess else {
			let reason = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
			Log.pill.error("Keychain save failed: \(status, privacy: .public) \(reason, privacy: .public)")
			throw BuddyError("Couldn't save the API key to the Keychain.")
		}
	}

	func delete() {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: Self.service,
			kSecAttrAccount as String: Self.account,
		]
		SecItemDelete(query as CFDictionary)
	}

	private static func readKeychain() -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
			let data = result as? Data,
			let key = String(data: data, encoding: .utf8),
			!key.isEmpty else {
			return nil
		}
		return key
	}

	#if DEBUG
	/// The repo root is found from this source file's location at compile time.
	private static func keyFromDotEnv() -> String? {
		let repoRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		guard let contents = try? String(contentsOf: repoRoot.appendingPathComponent(".env"), encoding: .utf8) else {
			return nil
		}
		for line in contents.split(whereSeparator: \.isNewline) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard trimmed.hasPrefix("GROQ_API_KEY=") else {
				continue
			}
			let value = trimmed.dropFirst("GROQ_API_KEY=".count)
				.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
			return value.isEmpty ? nil : value
		}
		return nil
	}
	#endif
}
