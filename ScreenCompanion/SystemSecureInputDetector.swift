import BuddyCore
import Carbon

/// macOS turns on Secure Input while a password field has focus, so keystrokes can't be read by other apps.
/// Buddy uses the same signal to avoid capturing or sending the screen at those moments.
struct SystemSecureInputDetector: SecureInputDetector {
	func isSecureInputActive() -> Bool {
		IsSecureEventInputEnabled()
	}
}
