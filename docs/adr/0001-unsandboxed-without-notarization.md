# Unsandboxed, Hardened Runtime, not notarized

Buddy needs a global hotkey with key-up detection, the Accessibility API to snap pointing to real UI elements, and synthetic ⌘V to insert Draft text. The App Sandbox blocks all three, so Buddy ships unsandboxed with Hardened Runtime on, outside the App Store, like other tools in this category.

There is no paid Apple Developer account, so the build is not notarized. On first launch, macOS 15 requires System Settings → Privacy & Security → Open Anyway; the README documents this and the `xattr` alternative.

## Consequences

Permission grants are tied to the code signature. Development builds should be signed with a stable Personal Team identity, or grants silently reset between builds. An updated ad-hoc build requires reviewers to grant permissions again.
