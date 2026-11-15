import Foundation
import Observation

/// Owns the request lifecycle: one request at a time, one cancellable task per request.
/// Created once at launch and injected into the UI; it is not a singleton.
@MainActor
@Observable
public final class BuddyCoordinator {
	public private(set) var state: BuddyState = .idle
	public private(set) var mode: BuddyMode = .ask

	@ObservationIgnored private let services: BuddyServices
	@ObservationIgnored private let messageDuration: Duration
	@ObservationIgnored private var requestTask: Task<Void, Never>?
	@ObservationIgnored private var captureTask: Task<CapturedScreen, any Error>?
	@ObservationIgnored private var messageTask: Task<Void, Never>?
	/// Stopping the previous request's transcriber and speech; a new request waits for this first.
	@ObservationIgnored private var cleanupTask: Task<Void, Never>?

	public init(services: BuddyServices, messageDuration: Duration = .seconds(3)) {
		self.services = services
		self.messageDuration = messageDuration
	}

	// MARK: - Mode

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

	// MARK: - Request lifecycle

	/// Hotkey pressed, or Ask/Draft clicked in the menu bar. Interrupts anything in progress.
	public func startListening() {
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
	}

	/// Hotkey released, or listening stopped from the menu bar.
	public func stopListening() {
		guard case .listening = state else {
			return
		}
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
			let transcript = try await transcribe().trimmingCharacters(in: .whitespacesAndNewlines)
			try Task.checkCancellation()
			guard !transcript.isEmpty else {
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

	private func transcribe() async throws -> String {
		await cleanupTask?.value
		try Task.checkCancellation()
		let stream = try await services.transcriber.start()
		var latest = ""
		for try await event in stream {
			try Task.checkCancellation()
			switch event {
			case .partial(let text):
				latest = text
				if case .listening(_, let level) = state {
					state = .listening(transcript: text, level: level)
				}
			case .level(let level):
				if case .listening(let text, _) = state {
					state = .listening(transcript: text, level: level)
				}
			case .final(let text):
				latest = text
			}
		}
		return latest
	}

	private func ask(_ question: String) async throws {
		guard services.permissions.isGranted(.screenRecording) else {
			throw BuddyError("Buddy can't see your screen. It needs Screen Recording access. Open Setup from the menu bar.")
		}
		try requireAPIKey()
		let capture = captureTask ?? startCapture()
		let screen = try await capture.value
		try Task.checkCancellation()

		var text = ""
		var point: PointGuess?
		for try await event in services.answers.answer(question: question, screen: screen) {
			try Task.checkCancellation()
			switch event {
			case .text(let chunk):
				text += chunk
			case .point(let guess):
				point = guess
			}
			state = .answering(text: text, point: point)
		}
		let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !answer.isEmpty else {
			throw BuddyError("No answer came back. Try again.")
		}
		await services.speech.speak(answer)
		try Task.checkCancellation()
		state = .idle
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
		case .copiedToClipboard(let reason):
			show(BuddyMessage(reason, kind: .info))
		}
	}

	// MARK: - Helpers

	private func requireAPIKey() throws {
		guard let key = services.apiKeys.apiKey(), !key.isEmpty else {
			throw BuddyError("Buddy needs a Groq API key. Open Setup from the menu bar.")
		}
	}

	@discardableResult
	private func startCapture() -> Task<CapturedScreen, any Error> {
		let screen = services.screen
		let task = Task {
			try await screen.captureDisplayUnderCursor()
		}
		captureTask = task
		return task
	}

	private func stopCurrentRequest() {
		let wasBusy = state.isBusy
		requestTask?.cancel()
		requestTask = nil
		captureTask?.cancel()
		captureTask = nil
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
