import AppKit
import ApplicationServices
import AVFoundation
import BuddyCore
import CoreGraphics
import ScreenCaptureKit
import Speech

/// Reads and requests the real macOS permissions.
///
/// For a request, Microphone and Speech Recognition count as granted until the user actually denies them, because
/// macOS shows their prompt when Buddy first uses them. Accessibility and Screen Recording have no in-app prompt,
/// so they are granted only when switched on in System Settings.
struct SystemPermissionChecker: PermissionChecker {
	func isGranted(_ permission: Permission) -> Bool {
		switch status(of: permission) {
		case .granted:
			return true
		case .notRequested:
			return permission == .microphone || permission == .speechRecognition
		case .denied:
			return false
		}
	}

	/// Where the permission stands, for setup.
	func status(of permission: Permission) -> PermissionStatus {
		switch permission {
		case .microphone:
			switch AVCaptureDevice.authorizationStatus(for: .audio) {
			case .authorized:
				return .granted
			case .notDetermined:
				return .notRequested
			default:
				return .denied
			}
		case .speechRecognition:
			switch SFSpeechRecognizer.authorizationStatus() {
			case .authorized:
				return .granted
			case .notDetermined:
				return .notRequested
			default:
				return .denied
			}
		case .accessibility:
			return AXIsProcessTrusted() ? .granted : .notRequested
		case .screenRecording:
			return CGPreflightScreenCaptureAccess() ? .granted : .notRequested
		}
	}

	/// Shows macOS's own prompt, for the permissions that have one.
	func request(_ permission: Permission) async {
		switch permission {
		case .microphone:
			_ = await AVCaptureDevice.requestAccess(for: .audio)
		case .speechRecognition:
			await withCheckedContinuation { continuation in
				SFSpeechRecognizer.requestAuthorization { _ in
					continuation.resume()
				}
			}
		case .accessibility:
			// Adds Buddy to the Accessibility list, so the user only has to switch it on.
			let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
			_ = AXIsProcessTrustedWithOptions(options)
		case .screenRecording:
			// Asking ScreenCaptureKit for the list of displays (no capture) shows macOS's prompt and adds Buddy to the
			// Screen Recording list, even after permissions were reset. The older CGRequestScreenCaptureAccess() isn't
			// also called: it opens System Settings on its own, so the two showed one after the other, a click apart.
			_ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
		}
	}

	/// Opens the permission's pane in System Settings.
	@MainActor
	func openSettings(for permission: Permission) {
		let anchor: String
		switch permission {
		case .microphone:
			anchor = "Privacy_Microphone"
		case .speechRecognition:
			anchor = "Privacy_SpeechRecognition"
		case .accessibility:
			anchor = "Privacy_Accessibility"
		case .screenRecording:
			anchor = "Privacy_ScreenCapture"
		}
		guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)") else {
			return
		}
		// When System Settings is already open on another pane (such as Accessibility, from the step before), the first
		// link only brings it forward without changing pane. Sending the link again once it's in front navigates.
		let settingsWasOpen = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").isEmpty
		NSWorkspace.shared.open(url)
		if settingsWasOpen {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				NSWorkspace.shared.open(url)
			}
		}
	}
}
