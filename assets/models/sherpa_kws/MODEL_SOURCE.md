# Keyword spotting model

- Model: `sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01`
- Source: <https://github.com/k2-fsa/sherpa-onnx/releases/tag/kws-models>
- License declared by the model package: Apache License 2.0
- Training corpus declared by the model package: WenetSpeech L
- Runtime: sherpa-onnx 1.13.8

Only the INT8 encoder, decoder, joiner and token table required for inference
are bundled. `keywords.txt` is project-owned configuration for the default wake
phrase `小美小美` (two consecutive calls, with or without a short pause).
The single-call keyword is intentionally excluded to reduce accidental activation.
The on-device cache version changes with this keyword configuration so existing
installations load the updated phrase.

Downloaded archive SHA-256:
`b2f7c89690dc8ce4c6ed6afeab7cd800c36ad1421fb6b6302b4a4b194cf7f35f`
