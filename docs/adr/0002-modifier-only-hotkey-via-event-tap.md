# Modifier-only hotkey through an event tap

Push-to-talk is holding Control and Option with no other key. That combination is unused by apps and macOS, sits side by side for one-handed use, and suits holding. Carbon's `RegisterEventHotKey` cannot register a modifier-only combination, so Buddy watches key events with a `CGEventTap`. This requires the Accessibility permission, which Buddy needs anyway for pointing and Draft.

The tap is active rather than listen-only so that it can swallow Tab (switch mode) and Esc (cancel) during a hold, keeping them out of the focused app. Any other key joining the hold cancels it, so that Control-Option shortcuts in other apps still work. Holds under 250 ms are ignored.

## Consequences

Without Accessibility there is no hotkey. Click-to-start from the menu bar is the fallback. The tap callback must stay trivial, because macOS disables slow taps and Buddy must re-enable it when that happens.
