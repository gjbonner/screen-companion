# Modifier-only hotkey through an event tap

Push-to-talk is holding a combination of modifier keys with no other key: Control and Option by default, or Option and Command, Control and Shift, or Right Option alone, chosen in the menu bar or the setup window. A modifier-only hold takes no key from any app, sits under one hand and suits holding. Carbon's `RegisterEventHotKey` cannot register a modifier-only combination, so Buddy watches key events with a `CGEventTap`. This requires the Accessibility permission, which Buddy needs anyway for pointing and Draft.

The tap is active rather than listen-only so that it can swallow Tab (switch mode) and Esc (cancel) during a hold, keeping them out of the focused app. It claims them only once the hold has lasted 250 ms: in a quick chord such as ⌃⇧Tab (previous browser tab) or ⌥⌘Esc (Force Quit) they pass through. Any other key or modifier joining the hold cancels it and passes through, so shortcuts that use the same modifiers still work. Holds under 250 ms are ignored.

## Considered Options

- Recording any shortcut the user presses (for example ⌥Space): Buddy would have to swallow that key, and macOS offers no complete list of shortcuts apps use, so it couldn't warn about clashes.
- Globe/fn or Control alone: macOS uses them for dictation, emoji and input sources.

## Consequences

Without Accessibility there is no hotkey. Click-to-start from the menu bar is the fallback, and it stops by itself after 5 seconds without sound, since no key release ends it. The tap callback must stay trivial, because macOS disables slow taps and Buddy must re-enable it when that happens.
