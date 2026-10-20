"""Compare bundled KWS profiles with synthetic PCM, pauses and silence phases."""

import argparse
import json
import time
import wave
from pathlib import Path

import numpy as np
import sherpa_onnx

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "assets/models/sherpa_kws"
FIXTURES = ROOT / "test/fixtures/wake_word"
NEGATIVES = {"single_call", "similar_words", "unrelated"}
PROFILES = {"previous": (4, 1.0, 0.5), "updated": (8, 1.5, 0.25)}


def waveform(path: Path) -> np.ndarray:
    with wave.open(str(path)) as audio:
        if (audio.getframerate(), audio.getsampwidth(), audio.getnchannels()) != (
            16000,
            2,
            1,
        ):
            raise ValueError(f"Expected mono PCM16/16kHz: {path.name}")
        samples = (
            np.frombuffer(audio.readframes(audio.getnframes()), dtype="<i2").astype(
                np.float32
            )
            / 32768
        )
    audible = np.flatnonzero(np.abs(samples) > 0.003)
    if not audible.size:
        raise ValueError(f"Fixture has no speech: {path.name}")
    return samples[max(0, audible[0] - 1600) : min(len(samples), audible[-1] + 1600)]


def detects(spotter: sherpa_onnx.KeywordSpotter, audio: np.ndarray) -> bool:
    stream = spotter.create_stream()
    for offset in range(0, len(audio), 640):
        stream.accept_waveform(16000, audio[offset : offset + 640])
        while spotter.is_ready(stream):
            spotter.decode_stream(stream)
            if spotter.get_result(stream):
                return True
    return False


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--quick", action="store_true")
    args = parser.parse_args()
    leads = (
        [0, 0.8, 1.3, 1.35, 1.4, 2.9, 3.0]
        if args.quick
        else [i * 0.05 for i in range(65)]
    )
    gains = [1, 0.15]
    report = {
        "runtime": sherpa_onnx.__version__,
        "synthetic_only": True,
        "profiles": {},
    }
    started = time.monotonic()
    for name, (paths, score, threshold) in PROFILES.items():
        spotter = sherpa_onnx.KeywordSpotter(
            tokens=str(MODELS / "tokens.txt"),
            encoder=str(MODELS / "encoder.int8.onnx"),
            decoder=str(MODELS / "decoder.int8.onnx"),
            joiner=str(MODELS / "joiner.int8.onnx"),
            keywords_file=str(MODELS / "keywords.txt"),
            keywords_score=score,
            keywords_threshold=threshold,
            max_active_paths=paths,
            num_trailing_blanks=1,
            num_threads=1,
        )
        results = {}
        for path in sorted(FIXTURES.glob("*.wav")):
            original = waveform(path)
            hits = 0
            misses = []
            for gain in gains:
                for lead in leads:
                    audio = np.concatenate(
                        [
                            np.zeros(round(lead * 16000), dtype=np.float32),
                            original * gain,
                            np.zeros(16000, dtype=np.float32),
                        ]
                    )
                    hit = detects(spotter, audio)
                    hits += hit
                    if not hit and path.stem not in NEGATIVES:
                        misses.append({"lead": round(lead, 2), "gain": gain})
            total = len(leads) * len(gains)
            results[path.stem] = {
                "detections": hits,
                "trials": total,
                "negative": path.stem in NEGATIVES,
                "misses": misses,
            }
            print(
                f"{name}: {path.stem}: {hits}/{total}"
                + (" (negative)" if path.stem in NEGATIVES else ""),
                flush=True,
            )
        report["profiles"][name] = results
    report["elapsed_seconds"] = round(time.monotonic() - started, 2)
    if args.output:
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    old, new = (report["profiles"][key] for key in PROFILES)
    if any(new[key]["detections"] for key in NEGATIVES):
        raise SystemExit("Synthetic negative controls triggered")
    if any(
        new[key]["detections"] < old[key]["detections"]
        for key in new
        if key not in NEGATIVES
    ):
        raise SystemExit("Detection regressed on a positive fixture")
    positives = [result for result in new.values() if not result["negative"]]
    if sum(result["detections"] for result in positives) < 0.95 * sum(
        result["trials"] for result in positives
    ):
        raise SystemExit("Synthetic positive detection fell below 95 percent")
    print(
        f"Comparison passed in {report['elapsed_seconds']}s. This does not measure acoustic field accuracy."
    )


if __name__ == "__main__":
    main()
