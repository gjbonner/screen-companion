# Insert Draft text by clipboard paste

Draft text is inserted by placing it on the clipboard and sending ⌘V, then restoring the previous clipboard contents after about 400 ms. Paste works in native apps, browsers and Electron apps alike, and one ⌘Z undoes the whole insertion.

## Considered Options

- Setting the focused element's selected text through Accessibility leaves the clipboard alone, but it is ignored or unreliable in browsers and Electron apps, where Shadow's users spend their time.
- Typing characters one by one is slow, can trigger autocomplete or shortcuts, and undoes word by word.

## Consequences

The clipboard is temporarily replaced, so Buddy snapshots every item and format, marks its own content as transient so clipboard managers skip it, and restores afterwards. When a password field has focus (Secure Input) or no text field has focus, the text is left on the clipboard with a "Copied" notice instead.
