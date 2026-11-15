# Take-home: Shadow Buddy (native macOS)
## Context
Shadow is an AI teammate for e-commerce brands. It connects to a brand's ad accounts, store, email and data warehouse, and answers questions or does work across them.
Most of that work doesn't happen inside Shadow, though. It happens in Ads Manager, Shopify, an inbox, a spreadsheet, Slack. Every time someone has to stop, switch to a Shadow tab and describe what they're looking at, we lose them.
The Shadow macOS suite exists to close that gap: small native tools that bring Shadow to wherever the user already is. This take-home is one of them.
## The idea
**Shadow Buddy** is a screen-aware voice companion that lives on your Mac.
You hold a hotkey and ask a question about whatever is on your screen: "what does this setting do?", "where do I change the budget?", "why does this number look off?" Buddy looks at your screen, answers out loud in a sentence or two, and, when it helps, a small Shadow mark flies across the screen and points at the exact thing it's talking about.
It also has a second mode for writing. You dictate, and it types clean, corrected text (with your own "no, actually…" corrections applied) into whatever app you're focused on.
Why it matters for Shadow: it turns "go open Shadow and explain your problem" into "just ask." It works in any app, needs no integration with that app, and gives us a natural place to later bring in Shadow's real data, so an on-screen question can be answered with real numbers and not just what the model can read from the pixels.
## What to build
A native macOS app that we can download, run and use. At minimum:
1. **Talk.** A global push-to-talk hotkey, plus a way to start without one. Show clearly that it's listening.
2. **See.** Capture what's on screen when the user asks.
3. **Answer.** Send the question and the screen to a multimodal model of your choice. Speak a short answer and show it on screen.
4. **Point.** When it's useful, animate the buddy to the UI element the answer refers to, and highlight it.
5. **Draft mode.** Dictation is cleaned up and inserted where the user's cursor is. Switching between Ask and Draft should be easy to discover. Don't make people memorize a shortcut.
6. **First run.** Walk a new user through the macOS permissions the app needs so it works on a fresh machine.
**Stretch goals** (pick any, or none):
- Multiple displays
- Lower latency: speech starts before the full answer has arrived
- "Screenshot this and write a message to Greg about it": crop the relevant part of the screen and put the image plus a drafted message on the clipboard
- Conversation history or follow-up questions
- A short proposal for how Buddy would answer from Shadow's data and not just the screen (written, not built)
## How it should feel
This matters as much as the feature list:
- **Present, not clingy.** At rest the buddy sits quietly in one place. It comes to you while you're using it and goes back when you're done. It should never follow you around all day.
- **Never in the way.** It doesn't steal focus, doesn't block clicks on what's underneath it, and never moves the real cursor. Don't make a moving element something the user has to click.
- **Short and spoken.** Answers are one to three sentences, written to be heard. Long answers scroll instead of covering the screen.
- **Shareable.** People should be able to screen-record Buddy in action, but Buddy should never see its own UI in the captures it sends to the model.
- **Crafted.** Restrained, native-feeling, with good motion. Treat it like a product, not a demo.
## Ground rules
- Native macOS (Swift, using SwiftUI and/or AppKit). Pick any model or speech provider you like.
- Don't commit API keys. Tell us how to supply our own.
- Aim for roughly **a day of focused work.** We care about your judgment more than how many features you finish. Cutting scope deliberately is a good answer.
## What to send back
1. A repo with a README: how to build it, how to run it, and what it needs.
2. A 2–3 minute screen recording of it working.
3. A short write-up (one page is plenty) covering:
   - how you structured the app
   - the hardest problem you hit and how you solved it
   - what you cut, and what you'd do next with another week
## What we'll look at
- **Does it work, and does it feel good to use?**
- **Accuracy:** does the pointer land where it should, on any display?
- **Responsiveness:** how quickly the first word comes back.
- **Robustness:** permissions, errors, empty or garbled speech, the user interrupting.
- **Code:** clear state handling, sensible structure, readable code.
- **Judgment:** what you chose to build and what you chose to skip.
In the follow-up conversation, we'll walk through the recording together and talk about the trade-offs you made.

