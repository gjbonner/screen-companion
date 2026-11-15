import BuddyCore
import Foundation

// Stand-ins so the app runs before each feature exists. Each feature branch replaces one of these
// with the real implementation, and this file is deleted once none are left.

extension BuddyServices {
	/// What the app runs with: real implementations where they exist, placeholders for the rest.
	static var live: BuddyServices {
		var services = placeholders
		services.permissions = SystemPermissionChecker()
		services.transcriber = SpeechRecognizerTranscriber()
		return services
	}

	static var placeholders: BuddyServices {
		BuddyServices(
			permissions: AssumeGrantedPermissions(),
			transcriber: NotBuiltTranscriber(),
			screen: NotBuiltScreenCapturer(),
			answers: NotBuiltAnswerProvider(),
			cleaner: NotBuiltDictationCleaner(),
			speech: SilentSpeechOutput(),
			inserter: NotBuiltTextInserter(),
			apiKeys: NoAPIKeyStore()
		)
	}
}

private let notBuilt = BuddyError("This part of Buddy isn't built yet.")

struct AssumeGrantedPermissions: PermissionChecker {
	func isGranted(_ permission: Permission) -> Bool {
		true
	}
}

struct NotBuiltTranscriber: Transcriber {
	func start() async throws -> AsyncThrowingStream<TranscriptionEvent, any Error> {
		throw notBuilt
	}

	func finish() async {}

	func cancel() async {}
}

struct NotBuiltScreenCapturer: ScreenCapturer {
	func captureDisplayUnderCursor() async throws -> CapturedScreen {
		throw notBuilt
	}
}

struct NotBuiltAnswerProvider: AnswerProvider {
	func answer(question: String, screen: CapturedScreen) -> AsyncThrowingStream<AnswerEvent, any Error> {
		AsyncThrowingStream { $0.finish(throwing: notBuilt) }
	}
}

struct NotBuiltDictationCleaner: DictationCleaner {
	func clean(_ dictation: String) async throws -> String {
		throw notBuilt
	}
}

struct SilentSpeechOutput: SpeechOutput {
	func speak(_ text: String) async {}

	func stop() async {}
}

struct NotBuiltTextInserter: TextInserter {
	func insert(_ text: String) async -> InsertionResult {
		.copiedToClipboard(reason: "This part of Buddy isn't built yet.")
	}
}

struct NoAPIKeyStore: APIKeyStore {
	func apiKey() -> String? {
		nil
	}
}
