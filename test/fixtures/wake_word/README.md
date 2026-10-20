# Synthetic wake regression audio

All WAV files are project-generated mono PCM16 at 16 kHz. They contain no user
recordings. Keep these fixtures outside the production asset bundle.

- `normal.wav`, `alternate_voice.wav`: macOS `say`, Mandarin Tingting and Eddy,
  rate 180, text `小美小美`.
- `single_call.wav`: Tingting, text `小美` (must not activate).
- `paused.wav`: two trimmed copies of the single call with 1.2 s silence between.
- `with_command.wav`: Alibaba `longanlingxin_v3.1`, text
  `小美小美，请介绍一下你自己。`, resampled from 24 kHz using `scipy.signal.resample_poly`.
- `similar_words.wav`: the same Alibaba voice, text
  `小米小米，今天天气怎么样？每个人都有美好的梦想。` (must not activate).
- `unrelated.wav`: Tingting, text
  `今天的天气很好，我们下午出去走一走。每个人都有美好的梦想，打开电脑看看今天的工作安排。`
  (must not activate).

The scripts trim outer silence while keeping 100 ms context, then vary leading
silence and amplitude. These samples verify regressions; field accuracy still
requires multiple speakers, distances and real background noise.
