# Keep Buddy out of its own screenshots with a capture filter

Buddy must never see its own UI in the screenshot it sends to the model, but people must still be able to screen-record Buddy. Buddy captures with ScreenCaptureKit and an `SCContentFilter` that excludes its own application. The window server re-composites the screen without Buddy's windows, so the content underneath is fully present and nothing flickers on screen.

## Considered Options

- `NSWindow.sharingType = .none` hides the windows from every capture, including QuickTime, Loom and screen sharing, which breaks the requirement that Buddy can be recorded.
- Hiding Buddy, capturing, then showing it again (how Electron apps do it) causes a visible flicker and depends on timing.

Verified on macOS 15 before building (see `docs/notes/spikes.md`).
