import Foundation
import Observation

/// Owns the request lifecycle: one request at a time, one cancellable task per request.
/// Created once at launch and injected into the UI; it is not a singleton.
@MainActor
@Observable
public final class BuddyCoordinator {
	public private(set) var state: BuddyState = .idle
	public private(set) var mode: BuddyMode = .ask
	/// When true, Ask answers are shown but not spoken. Takes effect immediately, even mid-answer.
	public private(set) var isMuted: Bool

	@ObservationIgnored private let services: BuddyServices
	@ObservationIgnored private let messageDuration: Duration
	@ObservationIgnored private let answerLinger: Duration
	@ObservationIgnored private let readingTimePerWord: Duration
	@ObservationIgnored private let silenceTimeout: Duration
	@ObservationIgnored private var requestTask: Task<Void, Never>?
	/// Ends listening started from the menu bar after `silenceTimeout` without sound.
	@ObservationIgnored private var silenceTask: Task<Void, Never>?
	/// When sound or new words last arrived while listening.
	@ObservationIgnored private var lastSoundAt = ContinuousClock.now
	@ObservationIgnored private var captureTask: Task<CapturedScreen, any Error>?
	@ObservationIgnored private var pointTask: Task<Void, Never>?
	@ObservationIgnored private var messageTask: Task<Void, Never>?
	/// Stopping the previous request's transcriber and speech; a new request waits for this first.
	@ObservationIgnored private var cleanupTask: Task<Void, Never>?

	/// - Parameters:
	///   - isMuted: whether answers start muted (the app restores the user's last choice).
	///   - messageDuration: how long a notice stays in the pill.
	///   - answerLinger: how long the answer card stays after Buddy finishes speaking.
	///   - readingTimePerWord: when muted, the card stays this long per word so there's time to read it.
	///   - silenceTimeout: listening started from the menu bar stops after this long without sound.
	public init(
		services: BuddyServices,
		isMuted: Bool = false,
		messageDuration: Duration = .seconds(3),
		answerLinger: Duration = .seconds(2),
		readingTimePerWord: Duration = .milliseconds(300),
		silenceTimeout: Duration = .seconds(5)
	) {
		self.services = services
		self.isMuted = isMuted
		self.messageDuration = messageDuration
		self.answerLinger = answerLinger
		self.readingTimePerWord = readingTimePerWord
		self.silenceTimeout = silenceTimeout
	}

	// MARK: - Mode and mute

	public func setMode(_ newMode: BuddyMode) {
		mode = newMode
		// Switching to Ask mid-hold still needs a screenshot.
		if newMode == .ask, case .listening = state, captureTask == nil {
			startCapture()
		}
	}

	public func toggleMode() {
		setMode(mode.toggled)
	}

	public func setMuted(_ muted: Bool) {
		guard muted != isMuted else {
			return
		}
		isMuted = muted
		if muted {
			// Stop the sentence being spoken now; later sentences are skipped while muted.
			let speech = services.speech
			Task {
				await speech.stop()
			}
		}
	}

	public func toggleMuted() {
		setMuted(!isMuted)
	}

	// MARK: - Request lifecycle

	/// Hotkey pressed, or Ask/Draft clicked in the menu bar. Interrupts anything in progress.
	/// - Parameter stopsOnSilence: true when started from the menu bar, where no key release ends listening;
	///   it then stops by itself after `silenceTimeout` without sound.
	public func startListening(stopsOnSilence: Bool = false) {
		stopCurrentRequest()
		guard services.permissions.isGranted(.microphone), services.permissions.isGranted(.speechRecognition) else {
			show(BuddyMessage("Buddy needs Microphone and Speech Recognition access. Open Setup from the menu bar.", kind: .problem))
			return
		}
		state = .listening(transcript: "", level: 0)
		if mode == .ask {
			startCapture()
		}
		requestTask = Task { [weak self] in
			await self?.runRequest()
		}
		if stopsOnSilence {
			startSilenceTimer()
		}
	}

	/// Called once per Ask, when its first sentence is handed to the voice. Debug builds log it.
	@ObservationIgnored public var onAskTiming: ((AskTiming) -> Void)?
	/// When listening last stopped; Ask timings are measured from here.
	@ObservationIgnored private var listeningStoppedAt: ContinuousClock.Instant?

	/// Hotkey released, or listening stopped from the menu bar.
	public func stopListening() {
		guard case .listening = state else {
			return
		}
		listeningStoppedAt = .now
		silenceTask?.cancel()
		silenceTask = nil
		state = .thinking
		let transcriber = services.transcriber
		Task {
			await transcriber.finish()
		}
	}

	/// Esc: abandon whatever is happening.
	public func cancel() {
		guard state != .idle else {
			return
		}
		stopCurrentRequest()
		state = .idle
	}

	// MARK: - Pipeline

	private func runRequest() async {
		do {
			let heard = try await transcribe()
			try Task.checkCancellation()
			let transcript: String
			switch SpeechFilter.classify(transcript: heard.transcript, peakLevel: heard.peakLevel) {
			case .speech(let text):
				transcript = text
			case .silence:
				show(BuddyMessage("Didn't hear anything.", kind: .info))
				return
			case .nothingUsable:
				show(BuddyMessage("Didn't catch that. Try again.", kind: .info))
				return
			}
			// The mode is read at release, so Tab during the hold decides it.
			switch mode {
			case .ask:
				try await ask(transcript)
			case .draft:
				try await draft(transcript)
			}
		} catch is CancellationError {
			return
		} catch let error as BuddyError {
			showUnlessCancelled(BuddyMessage(error.userMessage, kind: .problem))
		} catch {
			showUnlessCancelled(BuddyMessage("Something went wrong. Try again.", kind: .problem))
		}
	}

	private func transcribe() async throws -> (transcript: String, peakLevel: Float) {
		await cleanupTask?.value
		try Task.checkCancellation()
		let stream = try await services.transcriber.start()
		var latest = ""
		var peakLevel: Float = 0
		for try await event in stream {
			try Task.checkCancellation()
			switch event {
			case .partial(let text):
				if text != latest {
					lastSoundAt = .now
				}
				latest = text
				if case .listening(_, let level) = state {
					state = .listening(transcript: text, level: level)
				}
			case .level(let level):
				if level >= SpeechFilter.silenceThreshold {
					lastSoundAt = .now
				}
				peakLevel = max(peakLevel, level)
				if case .listening(let text, _) = state {
					state = .listening(transcript: text, level: level)
				}
			case .final(let text):
				latest = text
			}
		}
		return (latest, peakLevel)
	}

	private func ask(_ question: String) async throws {
		let stoppedAt = listeningStoppedAt
		let transcribedAt = ContinuousClock.now
		guard services.permissions.isGranted(.screenRecording) else {
			throw BuddyError(Self.screenRecordingMessage)
		}
		try requireAPIKey()
		// Never send the screen while a password field is active, even if it was captured earlier.
		guard !services.secureInput.isSecureInputActive() else {
			captureTask?.cancel()
			captureTask = nil
			throw BuddyError(Self.secureInputMessage)
		}
		let capture = captureTask ?? startCapture()
		let screen = try await capture.value
		let screenReadyAt = ContinuousClock.now
		try Task.checkCancellation()
		guard !services.secureInput.isSecureInputActive() else {
			throw BuddyError(Self.secureInputMessage)
		}

		// Sentences are spoken as soon as they're complete, while the rest of the answer is still arriving.
		let (sentences, sentenceQueue) = AsyncStream.makeStream(of: SpokenSentence.self)
		async let speaking: Void = speak(sentences)

		var splitter = SentenceSplitter()
		var text = ""
		var searchOffset = 0
		var firstTokenAt: ContinuousClock.Instant?
		var timingReported = false

		func reportTiming() {
			guard !timingReported, let stoppedAt, let firstTokenAt else {
				return
			}
			timingReported = true
			onAskTiming?(AskTiming(
				transcript: transcribedAt - stoppedAt,
				screen: screenReadyAt - stoppedAt,
				firstToken: firstTokenAt - stoppedAt,
				firstSentence: .now - stoppedAt
			))
		}

		func queue(_ completed: [String]) {
			for sentence in completed {
				let end = Self.endOffset(of: sentence, in: text, from: searchOffset)
				searchOffset = end
				sentenceQueue.yield(SpokenSentence(text: sentence, endOffset: end))
			}
			if !completed.isEmpty {
				reportTiming()
			}
		}

		do {
			for try await event in services.answers.answer(question: question, screen: screen) {
				try Task.checkCancellation()
				switch event {
				case .text(let chunk):
					if firstTokenAt == nil {
						firstTokenAt = .now
					}
					text += chunk
					queue(splitter.add(chunk))
				case .point(let guess):
					locatePoint(guess, on: screen)
				}
				state = .answering(text: text, point: currentPoint, spokenLength: currentSpokenLength)
			}
			queue(splitter.finish())
		} catch {
			sentenceQueue.finish()
			throw error
		}
		sentenceQueue.finish()

		guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw BuddyError("No answer came back. Try again.")
		}
		await speaking
		try Task.checkCancellation()
		// Muted answers stay up long enough to read; spoken ones only briefly after the voice ends.
		try await Task.sleep(for: isMuted ? readingTime(for: text) : answerLinger)
		state = .idle
	}

	private func speak(_ sentences: AsyncStream<SpokenSentence>) async {
		for await sentence in sentences {
			guard !Task.isCancelled else {
				return
			}
			if case .answering(let text, let point, _) = state {
				state = .answering(text: text, point: point, spokenLength: sentence.endOffset)
			}
			guard !isMuted else {
				continue
			}
			await services.speech.speak(sentence.text)
		}
	}

	private func readingTime(for text: String) -> Duration {
		let words = text.split(whereSeparator: \.isWhitespace).count
		return max(answerLinger, readingTimePerWord * words)
	}

	private func draft(_ dictation: String) async throws {
		try requireAPIKey()
		let cleaned = try await services.cleaner.clean(dictation).trimmingCharacters(in: .whitespacesAndNewlines)
		try Task.checkCancellation()
		guard !cleaned.isEmpty else {
			show(BuddyMessage("Nothing to insert.", kind: .info))
			return
		}
		let result = await services.inserter.insert(cleaned)
		try Task.checkCancellation()
		switch result {
		case .inserted:
			state = .idle
		case .insertedAndCopied(let note):
			show(BuddyMessage(note, kind: .info))
		case .copiedToClipboard(let reason):
			show(BuddyMessage(reason, kind: .info))
		}
	}

	// MARK: - Helpers

	private struct SpokenSentence: Sendable {
		var text: String
		/// Character offset in the answer text where this sentence ends.
		var endOffset: Int
	}

	private var currentSpokenLength: Int {
		if case .answering(_, _, let spokenLength) = state {
			return spokenLength
		}
		return 0
	}

	private var currentPoint: Pointing? {
		if case .answering(_, let point, _) = state {
			return point
		}
		return nil
	}

	/// Locates the guess in the background, while the answer keeps arriving and being spoken,
	/// and adds it to the answer once found.
	private func locatePoint(_ guess: PointGuess, on screen: CapturedScreen) {
		pointTask?.cancel()
		let locator = services.pointer
		pointTask = Task { [weak self] in
			let target = await locator.locate(guess, on: screen)
			guard !Task.isCancelled, let self, let target, case .answering(let text, _, let spokenLength) = self.state else {
				return
			}
			self.state = .answering(
				text: text,
				point: Pointing(target: target, displayFrame: screen.displayFrame),
				spokenLength: spokenLength
			)
		}
	}

	/// Where `sentence` ends in `text`, searching from `offset`. Falls back to the end of the text.
	static func endOffset(of sentence: String, in text: String, from offset: Int) -> Int {
		let start = text.index(text.startIndex, offsetBy: min(offset, text.count))
		guard let range = text.range(of: sentence, range: start..<text.endIndex) else {
			return text.count
		}
		return text.distance(from: text.startIndex, to: range.upperBound)
	}

	private func requireAPIKey() throws {
		guard let key = services.apiKeys.apiKey(), !key.isEmpty else {
			throw BuddyError("Buddy needs a Groq API key. Open Setup from the menu bar.")
		}
	}

	public nonisolated static let screenRecordingMessage = "Buddy needs Screen Recording to take screenshots. Allow it in System Settings, then relaunch."
	public nonisolated static let secureInputMessage = "Buddy won't look at your screen while a password field is active."

	@discardableResult
	private func startCapture() -> Task<CapturedScreen, any Error> {
		let screen = services.screen
		let secureInput = services.secureInput
		let task = Task {
			// Never capture while a password field is active.
			guard !secureInput.isSecureInputActive() else {
				throw BuddyError(BuddyCoordinator.secureInputMessage)
			}
			return try await screen.captureDisplayUnderCursor()
		}
		captureTask = task
		return task
	}

	/// Checks a few times a second; sound or new words reset the countdown.
	private func startSilenceTimer() {
		lastSoundAt = .now
		let timeout = silenceTimeout
		let interval = min(Duration.milliseconds(250), timeout / 4)
		silenceTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: interval)
				guard !Task.isCancelled, let self, case .listening = self.state else {
					return
				}
				if ContinuousClock.now - self.lastSoundAt >= timeout {
					self.stopListening()
					return
				}
			}
		}
	}

	private func stopCurrentRequest() {
		let wasBusy = state.isBusy
		requestTask?.cancel()
		requestTask = nil
		silenceTask?.cancel()
		silenceTask = nil
		captureTask?.cancel()
		captureTask = nil
		pointTask?.cancel()
		pointTask = nil
		messageTask?.cancel()
		messageTask = nil
		if wasBusy {
			let transcriber = services.transcriber
			let speech = services.speech
			let previousCleanup = cleanupTask
			cleanupTask = Task {
				await previousCleanup?.value
				await transcriber.cancel()
				await speech.stop()
			}
		}
	}

	private func showUnlessCancelled(_ message: BuddyMessage) {
		guard !Task.isCancelled else {
			return
		}
		show(message)
	}

	private func show(_ message: BuddyMessage) {
		state = .message(message)
		messageTask?.cancel()
		let duration = messageDuration
		messageTask = Task { [weak self] in
			try? await Task.sleep(for: duration)
			guard !Task.isCancelled, let self, self.state == .message(message) else {
				return
			}
			self.state = .idle
		}
	}
}
