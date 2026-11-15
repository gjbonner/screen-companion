import AVFoundation
import BuddyCore
import Foundation
import Speech

/// Microphone input transcribed by Apple's speech recognizer.
///
/// Each hold gets its own `ListeningSession`, so late work from an earlier hold (its trailing audio,
/// timeouts, recognizer callbacks) can only ever touch that earlier session, never a new one.
/// On-device recognition is used automatically when its model is installed; otherwise macOS uses Apple's servers.
final class SpeechRecognizerTranscriber: Transcriber, @unchecked Sendable {
	private let lock = NSLock()
	private var current: ListeningSession?
	/// The hotkey was released before listening had started (for example, during a permission prompt).
	private var finishRequested = false

	/// How long to keep recording after the hotkey is released, so the last word isn't cut off.
	private let trailingAudio: Duration = .seconds(1)

	func start() async throws -> AsyncThrowingStream<TranscriptionEvent, any Error> {
		try await requestAuthorization()

		guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
			recognizer.isAvailable else {
			throw BuddyError("Speech recognition isn't available right now.")
		}

		let session = ListeningSession(recognizer: recognizer)
		try session.begin()
		lock.withLock {
			current = session
		}
		Log.speech.info("Listening (on-device available: \(recognizer.supportsOnDeviceRecognition, privacy: .public))")

		let finishEarly = lock.withLock {
			let requested = finishRequested
			finishRequested = false
			return requested
		}
		if finishEarly {
			await session.finish(after: .zero)
		}
		return session.stream
	}

	func finish() async {
		let session = lock.withLock { () -> ListeningSession? in
			guard let current else {
				finishRequested = true
				return nil
			}
			return current
		}
		await session?.finish(after: trailingAudio)
	}

	func cancel() async {
		let session = lock.withLock {
			finishRequested = false
			let session = current
			current = nil
			return session
		}
		session?.cancel()
	}

	private func requestAuthorization() async throws {
		switch AVCaptureDevice.authorizationStatus(for: .audio) {
		case .authorized:
			break
		case .notDetermined:
			guard await AVCaptureDevice.requestAccess(for: .audio) else {
				throw BuddyError("Buddy needs Microphone access. Open Setup from the menu bar.")
			}
		default:
			throw BuddyError("Buddy needs Microphone access. Open Setup from the menu bar.")
		}

		var speechStatus = SFSpeechRecognizer.authorizationStatus()
		if speechStatus == .notDetermined {
			speechStatus = await withCheckedContinuation { continuation in
				SFSpeechRecognizer.requestAuthorization { status in
					continuation.resume(returning: status)
				}
			}
		}
		guard speechStatus == .authorized else {
			throw BuddyError("Buddy needs Speech Recognition access. Open Setup from the menu bar.")
		}
	}
}

/// One hold's worth of listening: its own audio engine, output stream and recognition.
///
/// How segments, pauses and restarts combine into one transcript is decided by `TranscriptAccumulator`
/// (in BuddyCore, unit-tested). This type only connects it to the microphone and Apple's recognizer.
///
/// Audio and recognition callbacks arrive on their own threads, so all mutable state is guarded by `lock`.
/// That is why this type is `@unchecked Sendable`.
private final class ListeningSession: @unchecked Sendable {
	let stream: AsyncThrowingStream<TranscriptionEvent, any Error>

	private let recognizer: SFSpeechRecognizer
	private let engine = AVAudioEngine()
	private let lock = NSLock()
	private var continuation: AsyncThrowingStream<TranscriptionEvent, any Error>.Continuation?
	private var request: SFSpeechAudioBufferRecognitionRequest?
	private var task: SFSpeechRecognitionTask?
	/// Increments with each recognition restart, so callbacks from a replaced recognition are ignored.
	private var generation = 0
	private var configurationObserver: (any NSObjectProtocol)?
	private var transcript = TranscriptAccumulator()
	/// True once the stream has finished, after which nothing more happens.
	private var isOver = false
	private var lastLevelReport: TimeInterval = 0

	/// How long to wait for the recognizer's final result after the audio ends.
	private let finalResultTimeout: TimeInterval = 2
	/// The recognizer's "no speech detected" error code.
	private static let noSpeechErrorCode = 1110

	init(recognizer: SFSpeechRecognizer) {
		self.recognizer = recognizer
		let (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptionEvent.self, throwing: (any Error).self)
		self.stream = stream
		self.continuation = continuation
		continuation.onTermination = { [weak self] termination in
			if case .cancelled = termination {
				self?.cancel()
			}
		}
	}

	func begin() throws {
		let input = engine.inputNode
		let format = input.outputFormat(forBus: 0)
		guard format.sampleRate > 0, format.channelCount > 0 else {
			throw BuddyError("No microphone found.")
		}

		startRecognition()

		input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
			self?.receive(buffer)
		}

		let observer = NotificationCenter.default.addObserver(
			forName: .AVAudioEngineConfigurationChange,
			object: engine,
			queue: nil
		) { [weak self] _ in
			Log.speech.notice("Audio configuration changed during listening")
			self?.fail(BuddyError("Microphone changed. Try again."))
		}
		lock.withLock {
			configurationObserver = observer
		}

		do {
			engine.prepare()
			try engine.start()
		} catch {
			Log.speech.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
			teardown()
			throw BuddyError("Couldn't start the microphone.")
		}
	}

	/// Keeps recording for `tail`, then ends the audio and waits for the final transcript.
	func finish(after tail: Duration) async {
		if tail > .zero {
			try? await Task.sleep(for: tail)
		}
		let request = lock.withLock { () -> SFSpeechAudioBufferRecognitionRequest? in
			guard !isOver, !transcript.audioEnded else {
				return nil
			}
			transcript.endAudio()
			return self.request
		}
		guard let request else {
			return
		}
		engine.stop()
		engine.inputNode.removeTap(onBus: 0)
		request.endAudio()

		// If the recognizer never sends a final result, use what has been heard so far.
		DispatchQueue.global().asyncAfter(deadline: .now() + finalResultTimeout) { [weak self] in
			self?.completeWithHeardText()
		}
	}

	func cancel() {
		guard let continuation = takeContinuation() else {
			return
		}
		continuation.finish(throwing: CancellationError())
		teardown()
	}

	// MARK: - Recognition

	/// Starts (or restarts) recognition on a fresh request; the microphone keeps running throughout.
	private func startRecognition() {
		let request = SFSpeechAudioBufferRecognitionRequest()
		request.shouldReportPartialResults = true
		request.addsPunctuation = true
		request.contextualStrings = SpeechVocabulary.phrases

		let (generation, previousTask) = lock.withLock {
			self.generation += 1
			self.request = request
			let previous = task
			task = nil
			return (self.generation, previous)
		}
		previousTask?.cancel()

		let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
			self?.handle(result: result, error: error, generation: generation)
		}
		lock.withLock {
			if self.generation == generation {
				self.task = task
			}
		}
	}

	private func receive(_ buffer: AVAudioPCMBuffer) {
		let request = lock.withLock { self.request }
		request?.append(buffer)
		reportLevel(of: buffer)
	}

	private func handle(result: SFSpeechRecognitionResult?, error: (any Error)?, generation: Int) {
		let isCurrent = lock.withLock { !isOver && generation == self.generation }
		guard isCurrent else {
			return
		}

		let next: TranscriptAccumulator.Next
		if let result {
			let segmentClosed = result.speechRecognitionMetadata != nil
			next = lock.withLock {
				transcript.receive(
					text: result.bestTranscription.formattedString,
					segmentClosed: segmentClosed,
					isFinal: result.isFinal
				)
			}
		} else if let error {
			let nsError = error as NSError
			let audioEnded = lock.withLock { transcript.audioEnded }
			if audioEnded || nsError.code == Self.noSpeechErrorCode {
				Log.speech.info("Recognizer stopped: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
				next = lock.withLock { transcript.recognizerStoppedWithoutSpeech() }
			} else {
				Log.speech.error("Recognizer failed while listening: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .public)")
				fail(BuddyError("Speech recognition stopped: \(nsError.localizedDescription)"))
				return
			}
		} else {
			return
		}

		let heard = lock.withLock { transcript.heard }
		switch next {
		case .keepListening:
			yield(.partial(heard))
		case .restartRecognition:
			Log.speech.info("Recognizer stopped while the key is held; restarting")
			startRecognition()
			yield(.partial(heard))
		case .finish:
			complete(with: heard)
		}
	}

	private func reportLevel(of buffer: AVAudioPCMBuffer) {
		let now = ProcessInfo.processInfo.systemUptime
		let shouldReport = lock.withLock {
			guard now - lastLevelReport >= 0.05 else {
				return false
			}
			lastLevelReport = now
			return true
		}
		guard shouldReport, let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
			return
		}
		var sum: Float = 0
		for index in 0..<Int(buffer.frameLength) {
			sum += samples[index] * samples[index]
		}
		let rms = (sum / Float(buffer.frameLength)).squareRoot()
		let decibels = 20 * log10(max(rms, 0.000_01))
		// Map roughly -50 dB (quiet room) ... 0 dB (loud) onto 0 ... 1.
		let level = min(max((decibels + 50) / 50, 0), 1)
		yield(.level(level))
	}

	// MARK: - Helpers

	private func yield(_ event: TranscriptionEvent) {
		let continuation = lock.withLock { isOver ? nil : self.continuation }
		continuation?.yield(event)
	}

	private func completeWithHeardText() {
		let text = lock.withLock { transcript.heard }
		complete(with: text)
	}

	/// Sends the final transcript once and closes the stream. Later calls do nothing.
	private func complete(with text: String) {
		guard let continuation = takeContinuation() else {
			return
		}
		continuation.yield(.final(text))
		continuation.finish()
		teardown()
	}

	private func fail(_ error: BuddyError) {
		guard let continuation = takeContinuation() else {
			return
		}
		continuation.finish(throwing: error)
		teardown()
	}

	/// Marks the session over and hands back the continuation, exactly once.
	private func takeContinuation() -> AsyncThrowingStream<TranscriptionEvent, any Error>.Continuation? {
		lock.withLock {
			guard !isOver else {
				return nil
			}
			isOver = true
			let continuation = self.continuation
			self.continuation = nil
			return continuation
		}
	}

	private func teardown() {
		let (task, observer) = lock.withLock {
			let parts = (self.task, configurationObserver)
			self.task = nil
			request = nil
			configurationObserver = nil
			return parts
		}
		engine.stop()
		engine.inputNode.removeTap(onBus: 0)
		task?.cancel()
		if let observer {
			NotificationCenter.default.removeObserver(observer)
		}
	}
}
