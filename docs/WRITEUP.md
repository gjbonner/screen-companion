# Buddy: write-up

Nov 15, 2026 · Giles Bonner

## How it's structured

All of Buddy's behavior lives in a Swift package with no AppKit, so it runs under test; the app target only connects it to macOS.

`BuddyCoordinator` is the only thing that changes `BuddyState`, and it handles one request at a time with one cancellable task, so pressing the hotkey again or Esc always wins cleanly. Every call to macOS or the network goes through a protocol, which the app implements and the tests replace with fakes. The UI only reads the state.

The larger decisions are written up as six ADRs in `docs/adr/`: running unsandboxed, the modifier-only hotkey, leaving Buddy out of its own screenshots, how pointing works, the model provider, and inserting Draft text by paste.

## The hardest problem: pointing at the right thing

The model knew what to point at but not where it was, so Buddy now finds the element by its name and uses the model's position only to break ties.

With the free `qwen/qwen3.8-27b` on Groq, the model named the right element every time ("Run button", "README.md") but placed it 60 to 400 pt away, in both directions. Six guesses for Xcode's Run button, which sits at x ≈ 190 in the screenshot, ranged from x = 128 to x = 604. That is not a fixed offset I could correct for.

The first design snapped the guess to the nearest Accessibility element within 40 pt. It either found nothing or confidently outlined the wrong neighbor, leading to false positives such as the Help menu.

The design that works:

1. The model returns a label: the element's exact visible text, or the name an app would give an icon ("Run", "Settings").
2. Buddy looks for that label on the same screenshot with on-device text recognition (Vision), and in parallel by name in the window's Accessibility tree.
3. A match counts anywhere on the display; with several matches, the one nearest the guess wins. No match means no pointing, and the spoken answer still says where it is.

Matching treats icon words as synonyms (play, run, start) and requires the label's most distinctive word, so README.md never matches LICENSE.md. The lookup takes 0.1 to 0.2 s once text recognition is warmed up at launch; the first cold lookup took 23.6 s.

After the change, YouTube's History link, GitHub's README.md and Xcode's Run button were all found exactly. One gap remains: icons with no text inside Chrome web pages, because Chrome hides page elements from Accessibility. A model trained to locate interface elements, such as Claude, would close it, and the label lookup would still correct small misses.

## What I cut

I built all six required features and two stretch goals: speech starts before the full answer arrives, and multiple displays work, with Buddy capturing, answering and pointing on whichever display the mouse pointer is focused on, which in practice is usually the one you're working on. Beyond the brief, the hotkey can be changed from a dropdown: ⌃⌥, ⌥⌘, ⌃⇧ or Right ⌥. It also runs on macOS 15 and later, so it works on older Macs: speech uses SFSpeechRecognizer, on device where possible, rather than macOS 26's newer recognizer. I cut the rest on purpose:

- **Follow-up questions and history.** Each request stands alone.
- **Screenshot-to-message.** The stretch goal of cropping the screen into a drafted message.
- **Signing and notarization.** The release is unsigned, so the first launch needs Open Anyway in Privacy & Security (ADR 0001).
- **Restoring the clipboard after Draft.** Built, then dropped: Chrome can't report whether a paste landed, so the text stays on the clipboard rather than risk losing it (ADR 0006).
- **A stronger model.** Groq's free preview model kept the project at no cost, behind a protocol so it can be swapped (ADR 0005).

## With another week

First I'd swap in Claude and measure pointing properly, then build what users would notice next.

1. **Claude as the model, with a pointing eval.** Debug builds already save every pointing attempt as an annotated screenshot; turn those into a scored set and compare models on it.
2. **Follow-up questions.** Keep the last answer and screenshot for a short window, so "and where's the other one?" works.
3. **Icons inside web pages.** Use the model's own coordinates when Accessibility and text recognition both come up empty, once a model is accurate enough to trust them.
4. **Screenshot-to-message.** Crop the region Buddy points at and put it, with a drafted message, on the clipboard.
5. **A signed, notarized build with updates,** so installing Buddy is a normal double-click.
6. **Answers from Shadow's data,** as proposed below.

## Proposal: answering from Shadow's data

Buddy would answer "why does this number look off?" with Shadow's figures instead of only what the pixels show. It would do that by sending Shadow the question plus what's on screen, through the same answer protocol the app already uses. This is a design, not built.

**What Buddy adds to the question.** Buddy already has the screenshot and the text on it. It would also read the page's address and window title through Accessibility, which tell it the app and the record: an Ads Manager campaign, a Shopify order, a Klaviyo flow. Names and IDs read from the screen (a campaign name, an order number) go along with it.

**How Shadow answers.** A new `AnswerProvider`, signed in as the user, sends Shadow the question, the screenshot and those details. Shadow answers from the connected ad accounts, store and warehouse. The reply keeps Buddy's format: one to three spoken sentences, plus a label to point at. Speaking early, pointing and the answer card work unchanged.

**Privacy.** Same rules as today:

- Nothing is sent unless the user holds the hotkey.
- The screen is never captured while a password field is active.
- The pill says when an answer used Shadow data.
- A list of approved apps controls which ones are ever sent to Shadow.

**First version.** Ads Manager and Shopify, read-only, questions about numbers, checked against the same question asked in Shadow's web app.

**Open questions.** How Buddy signs in to Shadow, and whether Shadow can answer within about 2 seconds so the first word still comes quickly.
