import BuddyCore
import Foundation
import Testing
@testable import ScreenCompanion

/// Every error message the user sees from Groq comes from these two mappings.
struct GroqClientTests {
	// MARK: - HTTP status

	@Test(arguments: [401, 403])
	func rejectedKeyPointsToSetup(_ status: Int) {
		let error = GroqClient.httpError(status: status, retryAfter: nil, body: #"{"error":{"message":"Invalid API Key"}}"#)
		#expect(error == BuddyError("Groq didn't accept the API key. Check it in Setup."))
	}

	@Test
	func rateLimitSaysWhenToTryAgain() {
		let error = GroqClient.httpError(status: 429, retryAfter: "12", body: "")
		#expect(error == BuddyError("Groq's rate limit was reached. Try again in 12s."))
	}

	@Test
	func fractionalRetryAfterRoundsUp() {
		let error = GroqClient.httpError(status: 429, retryAfter: "1.2", body: "")
		#expect(error == BuddyError("Groq's rate limit was reached. Try again in 2s."))
	}

	@Test(arguments: [nil, "", "Wed, 21 Oct 2026 07:28:00 GMT"])
	func rateLimitWithoutUsableRetryAfterSaysAMinute(_ retryAfter: String?) {
		let error = GroqClient.httpError(status: 429, retryAfter: retryAfter, body: "")
		#expect(error == BuddyError("Groq's rate limit was reached. Try again in a minute."))
	}

	@Test(arguments: [500, 502, 503])
	func serverErrorSaysTryAgainShortly(_ status: Int) {
		let error = GroqClient.httpError(status: status, retryAfter: nil, body: "upstream unavailable")
		#expect(error == BuddyError("Groq is having trouble right now. Try again shortly."))
	}

	@Test(arguments: [400, 404, 413])
	func otherClientErrorSaysItCouldNotAnswer(_ status: Int) {
		let error = GroqClient.httpError(status: status, retryAfter: nil, body: "not json")
		#expect(error == BuddyError("Groq couldn't answer that request."))
	}

	// MARK: - Other failures

	@Test
	func buddyErrorPassesThrough() {
		let original = BuddyError("Buddy needs a Groq API key. Open Setup from the menu bar.")
		#expect(GroqClient.userFacing(original) as? BuddyError == original)
	}

	@Test
	func cancellationStaysACancellation() {
		#expect(GroqClient.userFacing(CancellationError()) is CancellationError)
		#expect(GroqClient.userFacing(URLError(.cancelled)) is CancellationError)
	}

	@Test(arguments: [
		URLError.Code.notConnectedToInternet,
		.networkConnectionLost,
		.cannotFindHost,
		.cannotConnectToHost,
		.dnsLookupFailed,
	])
	func offlineSaysNoInternet(_ code: URLError.Code) {
		#expect(GroqClient.userFacing(URLError(code)) as? BuddyError == BuddyError("No internet connection."))
	}

	@Test
	func timeoutSaysItTookTooLong() {
		#expect(GroqClient.userFacing(URLError(.timedOut)) as? BuddyError == BuddyError("Groq took too long to answer. Try again."))
	}

	@Test
	func anythingElseSaysCouldNotReachGroq() {
		let unexpected = NSError(domain: "Test", code: 1)
		#expect(GroqClient.userFacing(unexpected) as? BuddyError == BuddyError("Couldn't reach Groq. Try again."))
		#expect(GroqClient.userFacing(URLError(.badServerResponse)) as? BuddyError == BuddyError("Couldn't reach Groq. Try again."))
	}
}
