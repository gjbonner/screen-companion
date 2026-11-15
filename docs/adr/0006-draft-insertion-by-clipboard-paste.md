# Insert Draft text by clipboard paste

Draft text is inserted by placing it on the clipboard and sending ⌘V. The text stays on the clipboard afterwards. Paste works in native apps, browsers and Electron apps alike, and one ⌘Z undoes the whole insertion.

## Considered Options

- Setting the focused element's selected text through Accessibility leaves the clipboard alone, but it is ignored or unreliable in browsers and Electron apps, where Shadow's users spend their time.
- Typing characters one by one is slow, can trigger autocomplete or shortcuts, and undoes word by word.

## Consequences

Whatever was on the clipboard before is replaced. Restoring it after the paste was built first and dropped: Chrome reports no focused element even when a field is focused, so Buddy can't tell whether a paste landed, and restoring would lose the dictation whenever it didn't. Leaving the text on the clipboard means the user can always paste it themselves, and the pill says "Copied to clipboard". When a password field has focus (Secure Input) or an element that clearly isn't text has focus, Buddy doesn't paste and says why.
