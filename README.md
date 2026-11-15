Copyright © 2026 Giles Bonner. All rights reserved.

This software and its source code are independently developed and owned by Giles Bonner.

This project was created solely as an interview demonstration for evaluation by Shadow.

No ownership rights or license to use, reproduce, modify, distribute, sublicense, or incorporate this software into Shadow's products or services are granted.

Any use beyond reviewing and running the software for the purposes of evaluating this interview submission requires prior written permission from the copyright holder.

The Shadow Buddy name and Shadow branding are referenced solely to identify the product concept described in the interview assignment. This project is not an official Shadow product.

---

# Buddy

Buddy is a screen-aware voice companion for the Mac. Hold **Control + Option**, speak, and let go.

- **Ask** (default): Buddy looks at your screen, answers out loud in a sentence or two, and points at what it's talking about.
- **Draft**: Buddy cleans up your dictation and pastes it where your cursor is.

## Try it

1. Download `Buddy.zip` from the [latest release](https://github.com/gjbonner/screen-companion/releases/latest) and unzip it.
2. Move **Buddy** into **Applications**.
3. Open it. The build isn't notarized, so macOS blocks the first launch. Click **Done**, then go to **System Settings › Privacy & Security**, scroll down, and click **Open Anyway** next to Buddy. Or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Buddy.app
   ```
4. Buddy appears in the menu bar and opens **Set Up Buddy**. Follow the rows (details in [What it needs](#what-it-needs)). Screen Recording needs Buddy to relaunch once.
5. Paste a Groq API key when asked. A free key from [console.groq.com/keys](https://console.groq.com/keys) works.

The window closes itself when everything is set. You can reopen it any time from **Setup…** in the menu bar.

### Using it

| To | Do this |
| --- | --- |
| Ask about your screen | Hold **⌃⌥**, ask, let go |
| Switch between Ask and Draft | Press **Tab** while holding **⌃⌥**, or use the switch in the menu bar |
| Cancel | Press **Esc** |
| Start without the hotkey | Click the menu bar icon, then **Start Ask** or **Start Draft** |
| Read answers without hearing them | Turn off **Speak answers** in the menu bar |

- **Pointing:** Buddy points only when it finds the element on screen. If it can't, it says where the element is instead.
- **Draft:** text is pasted into the focused field and also left on the clipboard, so you can paste it again if no field was focused.
- **Password fields:** while one is active, Buddy never captures or sends your screen.

### Voice

Buddy speaks with the voice set in **System Settings › Accessibility › Read & Speak** (called **Spoken Content** before macOS 27). Search Settings for "System voice". For a more natural voice, choose **Manage Voices** there and download an Enhanced or Premium voice.

## Build it

You need a Mac on macOS 15 or later and Xcode (built and tested with Xcode 27.2).

```sh
git clone git@github.com:gjbonner/screen-companion.git
cd screen-companion
open ScreenCompanion.xcodeproj
```

1. In **Signing & Capabilities**, choose your own team (the project has the author's).
2. For development, put your Groq key in a `.env` file at the repo root. Debug builds read it; it's gitignored and Release builds never look for it.
   ```sh
   echo 'GROQ_API_KEY=gsk_...' > .env
   ```
3. Run the **ScreenCompanion** scheme. Grant permissions in the setup window as above.

### Release build

```sh
xcodebuild -project ScreenCompanion.xcodeproj -scheme ScreenCompanion -configuration Release \
	-derivedDataPath build clean build
rm -rf build/Buddy.app Buddy.zip
ditto build/Build/Products/Release/ScreenCompanion.app build/Buddy.app
ditto -c -k --keepParent build/Buddy.app Buddy.zip
```

The project builds `ScreenCompanion.app` (its display name is Buddy); the copy is named `Buddy.app` for people downloading it.

### Tests

```sh
cd BuddyCore && swift test          # core logic: coordinator, hotkey, pointing, Draft, setup
xcodebuild test -project ScreenCompanion.xcodeproj -scheme ScreenCompanion -destination 'platform=macOS'
```

Two integration tests take over the screen and clipboard, so they only run when asked:

```sh
TEST_RUNNER_BUDDY_INTEGRATION=1 xcodebuild test -project ScreenCompanion.xcodeproj -scheme ScreenCompanion -destination 'platform=macOS'
```

They check that Buddy never appears in its own screenshots and that Draft pastes into a text field. They need Screen Recording and Accessibility granted to ScreenCompanion.

## What it needs

| Permission | Why | How it's granted |
| --- | --- | --- |
| Microphone | To hear you while you hold ⌃⌥ | **Allow** in the setup window |
| Speech Recognition | To turn speech into text, on your Mac when possible | **Allow** in the setup window |
| Accessibility | The ⌃⌥ hotkey, pasting Draft text, finding what to point at | **Open Settings**, then switch Buddy on |
| Screen Recording | To see your screen when you ask | **Open Settings**, switch Buddy on, then **Relaunch Buddy** |

- **A Groq API key,** stored in your Keychain. Buddy uses `qwen/qwen3.8-27b` for answers and Draft clean-up.
- **An internet connection** for answers and Draft. Speech recognition and pointing run on the Mac.
- **macOS 15 or later.**

If Buddy isn't in the Screen Recording list, click **+** under the list and add it from Applications.

## Design notes

Decisions are recorded in [`docs/adr/`](docs/adr), terms in [`GLOSSARY.md`](GLOSSARY.md), and the build plan in [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).
