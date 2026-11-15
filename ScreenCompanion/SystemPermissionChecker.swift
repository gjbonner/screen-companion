import ApplicationServices
import AVFoundation
import BuddyCore
import CoreGraphics
import Speech

/// Reads the real macOS permission state.
///
/// Microphone and Speech Recognition count as granted until the user actually denies them, because macOS
/// only shows their prompt when Buddy first uses them. Accessibility and Screen Recording have no in-app
/// prompt, so they are granted only when switched on in System Settings.
struct SystemPermissionChecker: PermissionChecker {
	func isGranted(_ permission: Permission) -> Bool {
		switch permission {
		case .microphone:
			let status = AVCaptureDevice.authorizationStatus(for: .audio)
			return status == .authorized || status == .notDetermined
		case .speechRecognition:
			let status = SFSpeechRecognizer.authorizationStatus()
			return status == .authorized || status == .notDetermined
		case .accessibility:
			return AXIsProcessTrusted()
		case .screenRecording:
			return CGPreflightScreenCaptureAccess()
		}
	}
}
