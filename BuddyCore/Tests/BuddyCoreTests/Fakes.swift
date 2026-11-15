import CoreGraphics
import Foundation
import Synchronization
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

/// An answer stream the test feeds by hand, to act while an answer is still arriving.
final class ControlledAnswerProvider: AnswerProvider {
	let stream: AsyncThrowingStream<AnswerEvent, any Error>
	let continuation: AsyncThrowingStream<AnswerEvent, any Error>.Continuation

	init() {
		(stream, continuation) = AsyncThrowingStream.makeStream(of: AnswerEvent.self, throwing: (any Error).self)
	}

	func answer(question: String, screen: CapturedScreen) -> AsyncThrowingStream<AnswerEvent, any Error> {
		stream
	}
}

/// Points at a 20×20 element centred on the guess, mapped to the screen, or nowhere if the guess is outside the screenshot.
struct FakePointLocator: PointLocator {
	func locate(_ guess: PointGuess, on screen: CapturedScreen) async -> PointTarget? {
		CoordinateMapper(screen: screen).screenPoint(forImagePoint: guess.imagePoint).map { point in
			PointTarget(frame: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20))
		}
	}
}

final class FakeCleaner: DictationCleaner {
	private let transform: @Sendable (String) -> String
	private let error: BuddyError?
	private let delay: Duration?
	private let calls = Mutex(0)

	/// - Parameters:
	///   - error: thrown instead of returning text.
	///   - delay: how long cleaning takes, to act while it's in progress. Cancellation ends it early.
	init(transform: @escaping @Sendable (String) -> String = { $0 }, error: BuddyError? = nil, delay: Duration? = nil) {
		self.transform = transform
		self.error = error
		self.delay = delay
	}

	var callCount: Int {
		calls.withLock { $0 }
	}

	func clean(_ dictation: String) async throws -> String {
		calls.withLock { $0 += 1 }
		if let delay {
			try await Task.sleep(for: delay)
		}
		if let error {
			throw error
		}
		return transform(dictation)
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

/// Secure Input (a password field) that a test can switch on and off.
final class FakeSecureInput: SecureInputDetector {
	private let active: Mutex<Bool>

	init(active: Bool = false) {
		self.active = Mutex(active)
	}

	func set(_ isActive: Bool) {
		active.withLock { $0 = isActive }
	}

	func isSecureInputActive() -> Bool {
		active.withLock { $0 }
	}
}

/// Wraps an answer provider and counts requests, to prove whether anything was sent to the model.
final class CountingAnswerProvider: AnswerProvider {
	private let wrapped: any AnswerProvider
	private let count = Mutex(0)

	init(_ wrapped: any AnswerProvider) {
		self.wrapped = wrapped
	}

	var requestCount: Int {
		count.withLock { $0 }
	}

	func answer(question: String, screen: CapturedScreen) -> AsyncThrowingStream<AnswerEvent, any Error> {
		count.withLock { $0 += 1 }
		return wrapped.answer(question: question, screen: screen)
	}
}

struct Harness {
	let coordinator: BuddyCoordinator
	let transcriber: FakeTranscriber
	let screen: FakeScreenCapturer
	let secureInput: FakeSecureInput
	let answers: CountingAnswerProvider
	let speech: FakeSpeech
	let inserter: FakeInserter

	@MainActor
	init(
		finalText: String = "where is the budget",
		permissions: FakePermissions = FakePermissions(),
		secureInput: FakeSecureInput = FakeSecureInput(),
		answers: FakeAnswerProvider = FakeAnswerProvider(),
		cleaner: FakeCleaner = FakeCleaner(),
		speech: FakeSpeech = FakeSpeech(),
		inserter: FakeInserter = FakeInserter(),
		apiKeys: FakeAPIKeys = FakeAPIKeys()
	) {
		transcriber = FakeTranscriber(finalText: finalText)
		screen = FakeScreenCapturer()
		self.secureInput = secureInput
		self.answers = CountingAnswerProvider(answers)
		self.speech = speech
		self.inserter = inserter
		coordinator = BuddyCoordinator(
			services: BuddyServices(
				permissions: permissions,
				transcriber: transcriber,
				screen: screen,
				secureInput: secureInput,
				answers: self.answers,
				pointer: FakePointLocator(),
				cleaner: cleaner,
				speech: speech,
				inserter: inserter,
				apiKeys: apiKeys
			),
			messageDuration: .seconds(60),
			answerLinger: .zero,
			readingTimePerWord: .zero
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
