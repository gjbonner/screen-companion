# Groq's Qwen preview model behind a provider protocol, no automatic retries

Ask and Draft use `qwen/qwen3.8-27b` on Groq: it is free to start, accepts images, and streamed a first token in under a second in testing. Groq lists it as a preview model that may be withdrawn at short notice, so the model sits behind the `AnswerProvider` and `DictationCleaner` protocols. Switching providers means adding one type.

Groq does not combine streaming with structured outputs, so answers stream as plain text with an optional final line `POINT: x,y | label` that Buddy parses itself.

Requests are never retried automatically. A failure, including a rate limit, ends the request with a notice, and the user retries by holding again. This protects the free-tier quota and keeps behavior predictable.
