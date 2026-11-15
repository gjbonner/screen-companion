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
}
