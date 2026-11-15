import CoreGraphics
import Foundation

// The coordinator talks to macOS and the network only through these protocols.
// The app target provides the real implementations; tests provide fakes.

// MARK: - Permissions

public enum Permission: Sendable, CaseIterable {
	case microphone
	case speechRecognition
	case accessibility
	case screenRecording
}

public protocol PermissionChecker: Sendable {
	func isGranted(_ permission: Permission) -> Bool
}

// MARK: - Speech in

public enum TranscriptionEvent: Sendable, Equatable {
	/// The best transcript so far, replacing any earlier partial.
	case partial(String)
	/// Microphone input level from 0 to 1, for the pill's meter.
	case level(Float)
	/// The final transcript, sent once after `finish()`.
	case final(String)
}

public protocol Transcriber: Sendable {
	/// Starts listening. The stream ends after `finish()` (with a `.final` event) or `cancel()`.
	func start() async throws -> AsyncThrowingStream<TranscriptionEvent, any Error>
	/// Stops listening and produces the final transcript. Safe to call before `start()` returns.
	func finish() async
	/// Stops listening and discards everything.
	func cancel() async
}

// MARK: - Screen

/// A screenshot of one display, with what's needed to map image pixels back to the screen.
public struct CapturedScreen: Sendable, Equatable {
	/// Encoded image sent to the model.
	public var imageData: Data
	/// Size of the encoded image in pixels.
	public var imagePixelSize: CGSize
	/// The display's frame in global screen points.
	public var displayFrame: CGRect

	public init(imageData: Data, imagePixelSize: CGSize, displayFrame: CGRect) {
		self.imageData = imageData
		self.imagePixelSize = imagePixelSize
		self.displayFrame = displayFrame
	}
}

public protocol ScreenCapturer: Sendable {
	/// Captures the display under the mouse cursor, without any of Buddy's windows.
	func captureDisplayUnderCursor() async throws -> CapturedScreen
}

/// Reports whether a password field (macOS Secure Input) is active. Screenshots go to a cloud model,
/// so Buddy never captures or sends the screen while one is.
public protocol SecureInputDetector: Sendable {
	func isSecureInputActive() -> Bool
}

// MARK: - Model

/// The model's guess at where to point, in the captured image's pixel coordinates (origin top-left).
public struct PointGuess: Sendable, Equatable {
	public var imagePoint: CGPoint
	public var label: String

	public init(imagePoint: CGPoint, label: String) {
		self.imagePoint = imagePoint
		self.label = label
	}
}

public enum AnswerEvent: Sendable, Equatable {
	/// More answer text, appended to what has arrived so far.
	case text(String)
	/// Where to point, if pointing helps.
	case point(PointGuess)
}

public protocol AnswerProvider: Sendable {
	func answer(question: String, screen: CapturedScreen) -> AsyncThrowingStream<AnswerEvent, any Error>
}

public protocol DictationCleaner: Sendable {
	/// Removes filler, fixes punctuation and applies spoken corrections, without adding content.
	func clean(_ dictation: String) async throws -> String
}

// MARK: - Speech out

public protocol SpeechOutput: Sendable {
	/// Speaks the text and returns when finished or stopped.
	func speak(_ text: String) async
	func stop() async
}

// MARK: - Draft insertion

public enum InsertionResult: Sendable, Equatable {
	case inserted
	/// The text couldn't be inserted, so it was left on the clipboard. `reason` is shown to the user.
	case copiedToClipboard(reason: String)
}

public protocol TextInserter: Sendable {
	func insert(_ text: String) async -> InsertionResult
}

// MARK: - API key

public protocol APIKeyStore: Sendable {
	func apiKey() -> String?
}

// MARK: - Bundle

public struct BuddyServices: Sendable {
	public var permissions: any PermissionChecker
	public var transcriber: any Transcriber
	public var screen: any ScreenCapturer
	public var secureInput: any SecureInputDetector
	public var answers: any AnswerProvider
	public var cleaner: any DictationCleaner
	public var speech: any SpeechOutput
	public var inserter: any TextInserter
	public var apiKeys: any APIKeyStore

	public init(
		permissions: any PermissionChecker,
		transcriber: any Transcriber,
		screen: any ScreenCapturer,
		secureInput: any SecureInputDetector,
		answers: any AnswerProvider,
		cleaner: any DictationCleaner,
		speech: any SpeechOutput,
		inserter: any TextInserter,
		apiKeys: any APIKeyStore
	) {
		self.permissions = permissions
		self.transcriber = transcriber
		self.screen = screen
		self.secureInput = secureInput
		self.answers = answers
		self.cleaner = cleaner
		self.speech = speech
		self.inserter = inserter
		self.apiKeys = apiKeys
	}
}
