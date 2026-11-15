# Spike findings

Two throwaway experiments, run on 2026-11-15 on macOS 15 before building, to test the assumptions the design depends on. The spike code was not kept.

## S1: Capture without Buddy's windows

**Question:** Does ScreenCaptureKit leave Buddy's windows out of a capture while keeping the content underneath?

**Method:** Showed a solid magenta panel over text, then captured the display twice: once with no exclusion (control) and once with an `SCContentFilter` excluding the process's own application.

**Result: passed.** The control capture shows the magenta panel. The excluded capture has no magenta, and the text underneath the panel is fully readable. Nothing is missing where the panel was.

**Note:** Capture needs the Screen Recording permission, and the grant only takes effect after the app relaunches.

## S2: Groq streaming with an image

**Question:** Does Groq stream `qwen/qwen3.8-27b` responses when the request includes a screenshot, and does the model follow the `POINT: x,y | label` format?

**Method:** Sent a 1600 × 900 JPEG of an Xcode window with the question "Where is the Run button in Xcode?" and streaming on.

**Result: passed.**

| Check | Result |
|---|---|
| Streams with an image | Yes, 42 chunks |
| Time to first token | 0.82 s (complete at 0.91 s) |
| Spoken-style answer | Yes, one sentence |
| `POINT` line | `POINT: 172,44 \| Run button` |
| Pointing (1 sample) | Actual about (189, 47): 17 px left, about 20 pt on screen |

The one pointing sample was a near-miss, landing between the sidebar toggle and the Run button. That is the case snapping is meant to correct. Pointing accuracy is measured properly in the Point feature, on several screenshots.
