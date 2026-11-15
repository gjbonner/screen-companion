# Point by the model's label, with its guess as a tie-breaker

The model returns a label and an approximate point in screenshot pixels. Buddy looks for the label on screen in two ways, in parallel: as text in the screenshot, with on-device text recognition (Vision), and as an element name in the window under the guess, with the Accessibility API. A match counts anywhere on the captured display; when the label appears more than once, the match nearest the guess wins. If nothing matches, Buddy doesn't point: the spoken answer still says where the element is, and a confident highlight on the wrong element would be worse than none. The lookup is local, so it costs no extra model calls.

The model is told to use the element's exact visible text as the label, so text recognition can find it, and for icons without text the name an app would give it ("Run", "Settings"), which Accessibility usually exposes. Matching also treats common icon words as synonyms (play, run and start; gear and settings; trash and delete), so "play button" still finds Xcode's Run.

Icons without text inside web pages in Chrome can't be found this way, because Chrome hides page elements from Accessibility and there's no text to recognize. For those Buddy doesn't point; only a model that locates elements accurately on its own would fix that.

## Why the label leads

Measured with `qwen/qwen3.8-27b`: the model named the right element every time ("Run button", "README") but its point was 60 to 400 pt away, scattered in both directions, worst on small icons. Snapping only around the guess either found nothing or confidently highlighted the wrong neighbour. Text recognition finds visible text exactly, including in browsers and Electron apps, where Chrome hides page elements from Accessibility.

The cost: if the model names the wrong element, Buddy points at it precisely. A model trained to locate UI, such as Claude for production, would make the guess itself reliable; the label lookup still corrects small misses.

## Considered Options

- Snapping to the element nearest the guess (the first version): fails whenever the guess is more than a few points off, which was most of the time.
- Falling back to the guess when the label isn't found (a ring, or an element right at it): points at the wrong place as often as the guess is wrong, so it was dropped.
- Sending the Accessibility tree to the model and letting it pick an element by ID: more accurate where it works, but a web page exposes thousands of elements, costing several thousand tokens per request on a free tier of 8K tokens per minute. Walking the tree is slow, and canvas and Electron apps expose little.
