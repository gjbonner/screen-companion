/// How long an Ask took to reach each step, measured from when listening stopped (the hotkey's release,
/// or the menu bar's silence stop). For measuring responsiveness; never shown to the user.
public struct AskTiming: Sendable, Equatable {
	/// The final transcript is ready.
	public var transcript: Duration
	/// Ask has the screenshot. Capture starts at key-down and Ask waits for it after the transcript, so anything
	/// beyond `transcript` is time spent waiting for the capture.
	public var screen: Duration
	/// The model's first text arrives.
	public var firstToken: Duration
	/// The first complete sentence is handed to the voice. The voice's own start-up comes after this.
	public var firstSentence: Duration

	public init(transcript: Duration, screen: Duration, firstToken: Duration, firstSentence: Duration) {
		self.transcript = transcript
		self.screen = screen
		self.firstToken = firstToken
		self.firstSentence = firstSentence
	}
}
