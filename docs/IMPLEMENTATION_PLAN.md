# Implementation plan

The focused-day scope, about 10 hours. Terms follow `GLOSSARY.md`; the larger decisions are recorded in `docs/adr/`.

## Workflow

Each feature gets its own branch, cut from the latest `master`, named `screen-companion/<feature>`. Every change is reviewed, the tests pass, the branch is committed, and it is merged into `master` before the next feature starts.

## Features, in order

### 1. `screen-companion/skeleton`: done
- Project settings: App Sandbox off, Hardened Runtime on, menu bar only, display name "Buddy", microphone entitlement, permission usage text.
- `BuddyCore` local package: `BuddyMode`, `BuddyState`, `BuddyCoordinator`, the service protocols, and unit tests with fakes.
- App: menu bar shell (Ask | Draft toggle, start/stop, quit), `Theme`, placeholder services.
- Docs: glossary, ADRs 0001–0006, spike findings, this plan.

### 2. `screen-companion/talk` (≈1.5 h)
- `HotkeyInterpreter` (core, pure): Control+Option press and release, holds under 250 ms ignored, another key cancels, Tab switches mode, Esc cancels.
- `EventTapHotkeySource` (app): active `CGEventTap` that swallows Tab and Esc only during a request and re-enables itself if macOS disables it.
- `PillPanel`: non-activating, click-through panel at the bottom center of the cursor's display, showing the mode, mic level, live transcript, and "Tab to switch".
- `SpeechRecognizerTranscriber`: `SFSpeechRecognizer` with `AVAudioEngine`, preferring on-device recognition, with partial results and microphone-change handling.
- `SpeechFilters` (core): silence, empty, and filler-only input.

### 3. `screen-companion/ask` (≈2 h)
- `ScreenCaptureKitCapturer`: the cursor's display, captured at key-down, with Buddy excluded and the image downscaled to about 1600 px.
- `GroqAnswerProvider`: streaming over `URLSession`, typed errors, and no retries. A rate limit reports when to try again.
- `AnswerStreamParser` and `SentenceSplitter` (core): sentences plus the trailing `POINT` line, including lines split across chunks.
- `SystemSpeechOutput`: `AVSpeechSynthesizer`, speaking sentence by sentence, with word callbacks driving the answer card captions.
- Answer card: the pill expands and auto-scrolls in time with speech.
- `KeychainAPIKeyStore`, with a gitignored `.env` read in Debug builds only.
- Integration test: capture exclusion (opt-in test plan).

### 4. `screen-companion/draft` (≈1 h)
- Cleanup prompt: remove filler, fix punctuation, apply spoken corrections, never add content.
- `ClipboardTextInserter`: wait for the hotkey to be released, check the focused element, detect Secure Input, paste, restore the clipboard after about 400 ms with transient marking, or fall back to a "Copied" notice.
- Integration test: Draft insertion into a test text view.

### 5. `screen-companion/point` (≈2 h)
- `CoordinateMapper` (core): image pixels to global screen points, tested for Retina, non-Retina, downscaled images, and offset or negative display origins.
- `SnapGuardrails` (core) and `AccessibilitySnapper` (app).
- Overlay panel on the cursor's display, on all Spaces and over full-screen apps.
- Mark flight: curved path with spring easing from the menu bar and back. Fades in place instead when Reduce Motion is on.
- Accuracy check: about five real screenshots, raw guess versus snapped result, recorded for the write-up.

### 6. `screen-companion/onboarding` (≈1 h)
- `SystemPermissionChecker` for Microphone, Speech Recognition, Accessibility, and Screen Recording.
- Onboarding window: four rows with live status, a relaunch step for Screen Recording, API key entry checked with one request, an optional Enhanced-voice tip, and it closes itself when everything is granted.
- Menu bar: a warning badge and a "Setup…" item whenever something is missing.

### 7. `screen-companion/ship` (≈1 h, plus recording)
- Brand: Shadow-inspired palette in `Theme` and an original mark.
- README: the existing copyright and ownership text kept exactly, followed by "Try it", "Build it", and "What it needs".
- Write-up, the Shadow-data proposal, and a manual test checklist.
- Release build zipped and attached to a GitHub Release, plus a 2–3 minute recording.

## If time runs short

Cut in this order: motion polish, the Draft insertion integration test, then onboarding extras. Point and ship are never cut.

## Out of scope, listed in the write-up

Follow-up questions and history, screenshot-to-message, full multi-display support, the macOS 26 `SpeechAnalyzer` path, hotkey rebinding, and the remaining integration tests.
