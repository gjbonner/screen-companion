# Buddy

Buddy is a screen-aware voice companion for the Mac. You hold a hotkey, speak, and it either answers a question about your screen or types cleaned-up dictation where your cursor is.

## Modes and requests

**Request**:
One use of Buddy, from starting to listen until the answer finishes, the text is inserted, or it is cancelled.
_Avoid_: Session, query, interaction

**Mode**:
What a request does with your speech: Ask or Draft. The mode is sticky and stays until changed.
_Avoid_: Action, intent

**Ask**:
The mode where you ask about what's on screen and Buddy answers aloud, shows the answer, and may point.
_Avoid_: Question mode, Q&A

**Draft**:
The mode where your dictation is cleaned up and inserted into the focused app, with nothing added that you didn't say.
_Avoid_: Dictation mode, write mode, type mode

**Hold**:
Keeping the hotkey (Control and Option) pressed while speaking. Releasing it ends listening.
_Avoid_: Press, push

## On screen

**Buddy**:
The app as a whole.
_Avoid_: Companion, assistant, ScreenCompanion (the project's code name)

**Mark**:
The small animated glyph that flies out of the menu bar to point at something, then returns.
_Avoid_: Buddy (for the glyph), cursor, pointer, avatar

**Pill**:
The small capsule at the bottom of the screen that shows the mode, the microphone level, and the live transcript while a request is active.
_Avoid_: HUD, indicator, toast, bar

**Answer card**:
The pill expanded to show an Ask answer as it is spoken.
_Avoid_: Bubble, popup, response panel

**Notice**:
A short line in the pill explaining why a request stopped or what happened, such as a missing permission or "Copied".
_Avoid_: Toast, alert, error popup

## Pointing

**Point target**:
The on-screen element an answer refers to.
_Avoid_: Target element, hotspot

**Guess**:
The model's estimate of where the point target is, in screenshot pixels.
_Avoid_: Prediction, coordinates

**Snap**:
Replacing the guess with the exact frame of the real UI element found at that spot, when that element is plausible.
_Avoid_: Correction, refinement, lock-on

**Highlight**:
The ring drawn around the point target while the mark points at it.
_Avoid_: Outline, focus ring (which macOS already uses)

**Cursor**:
The real mouse pointer. Buddy never moves it.
_Avoid_: Using this word for the mark
