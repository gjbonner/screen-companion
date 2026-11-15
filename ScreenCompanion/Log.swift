import OSLog

/// Unified logging. View with:
/// `log stream --level info --predicate 'subsystem == "com.gilesbonner.screencompanion"'`
enum Log {
	private static let subsystem = "com.gilesbonner.screencompanion"

	static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
	static let pill = Logger(subsystem: subsystem, category: "pill")
	static let speech = Logger(subsystem: subsystem, category: "speech")
	static let capture = Logger(subsystem: subsystem, category: "capture")
	static let model = Logger(subsystem: subsystem, category: "model")
	static let draft = Logger(subsystem: subsystem, category: "draft")
	static let point = Logger(subsystem: subsystem, category: "point")
	/// Debug builds only: how long each Ask took to reach its first spoken word.
	static let timing = Logger(subsystem: subsystem, category: "timing")

	/// A duration in whole milliseconds, for timing logs.
	static func milliseconds(_ duration: Duration) -> Int {
		let (seconds, attoseconds) = duration.components
		return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
	}
}
