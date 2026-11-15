/// Builds one hold's transcript from a speech recognizer that splits speech into segments at pauses,
/// and may stop on its own after a silence.
///
/// Listening must only end when the hotkey is released. While it's held, closed segments are kept and
/// recognition restarts, so nothing said before a pause is lost.
public struct TranscriptAccumulator: Sendable, Equatable {
	/// What the recognizer wrapper should do next.
	public enum Next: Sendable, Equatable {
		/// Keep going with the current recognition.
		case keepListening
		/// The recognizer stopped while the key is still held: start a fresh recognition on the same microphone.
		case restartRecognition
		/// The audio has ended and the recognizer is done: deliver `heard` as the final transcript.
		case finish
	}

	/// Text from segments the recognizer has already closed during this hold.
	private var committed = ""
	/// Text of the segment in progress; each result replaces it.
	private var segment = ""
	public private(set) var audioEnded = false

	public init() {}

	/// Everything heard so far in this hold.
	public var heard: String {
		Self.join(committed, segment)
	}

	/// A result from the recognizer.
	/// - Parameters:
	///   - text: the recognizer's text for the current segment, which replaces any earlier text for it.
	///   - segmentClosed: the recognizer has finished this segment (it paused); later text starts a new segment.
	///   - isFinal: the recognizer has stopped and will send nothing more.
	public mutating func receive(text: String, segmentClosed: Bool, isFinal: Bool) -> Next {
		segment = text
		if segmentClosed || isFinal {
			commitSegment()
		}
		if isFinal {
			return audioEnded ? .finish : .restartRecognition
		}
		return .keepListening
	}

	/// The recognizer gave up because it heard no speech for a while.
	public mutating func recognizerStoppedWithoutSpeech() -> Next {
		if audioEnded {
			return .finish
		}
		commitSegment()
		return .restartRecognition
	}

	/// The hotkey was released and the trailing audio has been recorded; no more audio is coming.
	public mutating func endAudio() {
		audioEnded = true
	}

	private mutating func commitSegment() {
		committed = heard
		segment = ""
	}

	static func join(_ first: String, _ second: String) -> String {
		if first.isEmpty {
			return second
		}
		if second.isEmpty {
			return first
		}
		return first + " " + second
	}
}
