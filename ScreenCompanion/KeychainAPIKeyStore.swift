import BuddyCore
import Foundation
import Security

/// The Groq API key, stored in the user's Keychain.
///
/// Debug builds also read `GROQ_API_KEY` from the repo's gitignored `.env`, so development needs no setup.
/// Release builds never look for that file.
struct KeychainAPIKeyStore: APIKeyStore {
	private static let service = "com.gilesbonner.screencompanion"
	private static let account = "groq-api-key"

	func apiKey() -> String? {
		#if DEBUG
		if let key = Self.keyFromDotEnv() {
			return key
		}
		#endif
		return Self.readKeychain()
	}

	func save(_ key: String) throws {
		let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
		delete()
		let item: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: Self.service,
			kSecAttrAccount as String: Self.account,
			kSecValueData as String: Data(trimmed.utf8),
		]
		let status = SecItemAdd(item as CFDictionary, nil)
		guard status == errSecSuccess else {
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
