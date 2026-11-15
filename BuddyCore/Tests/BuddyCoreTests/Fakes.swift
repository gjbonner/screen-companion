import CoreGraphics
import Foundation
import Testing
@testable import BuddyCore

actor FakeTranscriber: Transcriber {
	private var continuation: AsyncThrowingStream<TranscriptionEvent, any Error>.Continuation?
	private var finishRequested = false
	private var finalText: String
	private(set) var startCount = 0
	private(set) var cancelCount = 0

	init(finalText: String = "") {
		self.finalText = finalText
	}

	func setFinalText(_ text: String) {
		finalText = text
	}

	func start() async throws -> AsyncThrowingStream<TranscriptionEvent, any Error> {
		startCount += 1
		let (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptionEvent.self, throwing: (any Error).self)
		self.continuation = continuation
		if finishRequested {
			finishRequested = false
			finish()
		}
		return stream
	}

	func emit(_ event: TranscriptionEvent) {
		continuation?.yield(event)
	}

	func finish() {
		guard let continuation else {
			finishRequested = true
			return
		}
		continuation.yield(.final(finalText))
		continuation.finish()
		self.continuation = nil
	}

	func cancel() {
		cancelCount += 1
		continuation?.finish(throwing: CancellationError())
		continuation = nil
	}
}

actor FakeScreenCapturer: ScreenCapturer {
	static let sample = CapturedScreen(
		imageData: Data([0x01]),
		imagePixelSize: CGSize(width: 1600, height: 900),
		displayFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
	)

	private(set) var captureCount = 0

	func captureDisplayUnderCursor() async throws -> CapturedScreen {
		captureCount += 1
		return FakeScreenCapturer.sample
	}
}

struct FakeAnswerProvider: AnswerProvider {
	var events: [AnswerEvent] = [.text("Click Edit.")]
	var error: BuddyError?

	func answer(question: String, screen: CapturedScreen) -> AsyncThrowingStream<AnswerEvent, any Error> {
		AsyncThrowingStream { continuation in
			for event in events {
				continuation.yield(event)
			}
			if let error {
				continuation.finish(throwing: error)
			} else {
				continuation.finish()
			}
		}
	}
}

struct FakeCleaner: DictationCleaner {
	var transform: @Sendable (String) -> String = { $0 }

	func clean(_ dictation: String) async throws -> String {
		transform(dictation)
	}
}

actor FakeSpeech: SpeechOutput {
	private(set) var spoken: [String] = []
	private(set) var stopCount = 0
	private var holdsUntilStopped: Bool
	private var pending: CheckedContinuation<Void, Never>?

	init(holdsUntilStopped: Bool = false) {
		self.holdsUntilStopped = holdsUntilStopped
	}

	func speak(_ text: String) async {
		spoken.append(text)
		if holdsUntilStopped {
			await withCheckedContinuation { continuation in
				pending = continuation
			}
		}
	}

	func stop() {
		stopCount += 1
		pending?.resume()
		pending = nil
	}
}

actor FakeInserter: TextInserter {
	private(set) var inserted: [String] = []
	private let result: InsertionResult

	init(result: InsertionResult = .inserted) {
		self.result = result
	}

	func insert(_ text: String) async -> InsertionResult {
		inserted.append(text)
		return result
	}
}

struct FakePermissions: PermissionChecker {
	var granted: Set<Permission> = Set(Permission.allCases)

	func isGranted(_ permission: Permission) -> Bool {
		granted.contains(permission)
	}
}

struct FakeAPIKeys: APIKeyStore {
	var key: String? = "test-key"

	func apiKey() -> String? {
		key
	}
}

struct Harness {
	let coordinator: BuddyCoordinator
	let transcriber: FakeTranscriber
	let screen: FakeScreenCapturer
	let speech: FakeSpeech
	let inserter: FakeInserter

	@MainActor
	init(
		finalText: String = "where is the budget",
		permissions: FakePermissions = FakePermissions(),
		answers: FakeAnswerProvider = FakeAnswerProvider(),
		cleaner: FakeCleaner = FakeCleaner(),
		speech: FakeSpeech = FakeSpeech(),
		inserter: FakeInserter = FakeInserter(),
		apiKeys: FakeAPIKeys = FakeAPIKeys()
	) {
		transcriber = FakeTranscriber(finalText: finalText)
		screen = FakeScreenCapturer()
		self.speech = speech
		self.inserter = inserter
		coordinator = BuddyCoordinator(
			services: BuddyServices(
				permissions: permissions,
				transcriber: transcriber,
				screen: screen,
				answers: answers,
				cleaner: cleaner,
				speech: speech,
				inserter: inserter,
				apiKeys: apiKeys
			),
			messageDuration: .seconds(60)
		)
	}
}

struct WaitTimedOut: Error {}

/// Polls until the condition holds, failing the test after the timeout.
@MainActor
func waitUntil(
	timeout: Duration = .seconds(2),
	sourceLocation: SourceLocation = #_sourceLocation,
	_ condition: @MainActor () async -> Bool
) async throws {
	let deadline = ContinuousClock.now + timeout
	while ContinuousClock.now < deadline {
		if await condition() {
			return
		}
		try await Task.sleep(for: .milliseconds(5))
	}
	Issue.record("Timed out waiting for condition", sourceLocation: sourceLocation)
	throw WaitTimedOut()
}
