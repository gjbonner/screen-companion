# Point with the model's guess, then snap to the real element

The model returns an approximate point in screenshot pixels. Buddy maps it to screen coordinates, asks the Accessibility API which element is there, and highlights that element's exact frame if it is plausibly sized and close to the guess. Otherwise it draws a ring at the guess. The lookup is local and takes milliseconds, so it runs every time.

## Considered Options

Sending the Accessibility tree to the model and letting it pick an element by ID is more accurate when it works. But a web page exposes thousands of elements, which costs several thousand tokens per request on a free tier of 8K tokens per minute. Walking the tree is slow, and canvas and Electron apps expose little. This remains the escalation path if measured guesses are often far off rather than merely imprecise.
