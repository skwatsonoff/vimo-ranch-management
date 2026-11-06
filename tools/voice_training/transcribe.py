"""Writes down what a strong speech recogniser hears in each recording.

    rows = transcribe(folder, cache)   # [{id, lang, ref, asr}]

Uses Whisper large-v3 (faster-whisper, int8 on the CPU of a free GitHub
runner). Recordings already in [cache] (id -> text, kept in the lessons
document) are not heard again, so each run only listens to new ones.
"""
from __future__ import annotations

import json
import pathlib
import wave


def _load(path: pathlib.Path):
    import numpy as np

    with wave.open(str(path)) as w:
        pcm = w.readframes(w.getnframes())
    return np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768


def transcribe(folder: pathlib.Path, cache: dict[str, str], model_name: str = "large-v3") -> list[dict]:
    rows, model = [], None
    for meta_path in sorted(folder.glob("*/*.json")):
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        rid = meta.get("id") or meta_path.stem
        text = cache.get(rid)
        if text is None:
            if model is None:
                from faster_whisper import WhisperModel

                model = WhisperModel(model_name, device="cpu", compute_type="int8")
            language = "en" if meta.get("language") == "en" else "ta"
            segments, _ = model.transcribe(
                _load(meta_path.with_suffix(".wav")),
                language=language,
                beam_size=5,
                vad_filter=True,
                condition_on_previous_text=False,
            )
            text = " ".join(s.text.strip() for s in segments).strip()
            print(f"heard {len(rows) + 1}", flush=True)  # counts only: public log
        rows.append({"id": rid, "lang": meta.get("language", "ta"), "ref": meta.get("transcript", ""), "asr": text})
    return rows
