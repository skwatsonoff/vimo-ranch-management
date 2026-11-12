"""Fine-tunes a small Whisper model on the owner's recordings, on CPU, and
exports it for phones (ONNX, int8).

Plain words: Whisper "tiny" already knows some Tamil and English. Training
it a little on the ranch's own voices, cow names and dairy words makes it
much better for VIMO. A CPU is slow, so each run trains for at most
--max-minutes and saves a checkpoint; the next run continues from it.
Google Colab (finetune_asr_colab.ipynb) does the same on a free GPU, faster.

    python finetune_asr.py --data data/ --out work/ --max-minutes 300
    python finetune_asr.py --data data/ --out work/ --dry-run   # no training
"""
from __future__ import annotations

import argparse
import json
import pathlib
import random
import tarfile
import time

from common import normalise_text

BASE_MODEL = "openai/whisper-tiny"


def load_dataset(data: pathlib.Path, holdout: float = 0.1, seed: int = 7):
    """Pairs of (wav path, transcript, language) split into train / test.
    The split is stable for a recording id, so a later run tests on the
    same held-out sentences."""
    rows = []
    for sidecar in sorted(data.rglob("*.json")):
        wav = sidecar.with_suffix(".wav")
        if not wav.exists():
            continue
        meta = json.loads(sidecar.read_text(encoding="utf-8"))
        text = normalise_text(meta.get("transcript", ""))
        if text:
            rows.append({"id": meta.get("id", wav.stem), "audio": str(wav), "text": text, "language": meta.get("language", "ta")})
    # Repeated readings of one prompt stay on the same side of the split.
    prompts = sorted({row["text"] for row in rows})
    random.Random(seed).shuffle(prompts)
    count = max(0, min(len(prompts) - 1, max(1, round(len(prompts) * holdout))))
    test_prompts = set(prompts[:count])
    return (
        [row for row in rows if row["text"] not in test_prompts],
        [row for row in rows if row["text"] in test_prompts],
    )


def whisper_language(lang: str) -> str:
    return "english" if lang == "en" else "tamil"


def train(train_rows, out: pathlib.Path, max_minutes: float):
    import numpy as np
    import soundfile as sf
    import torch
    from transformers import WhisperForConditionalGeneration, WhisperProcessor

    ckpt = out / "checkpoint"
    source = str(ckpt) if (ckpt / "config.json").exists() else BASE_MODEL
    processor = WhisperProcessor.from_pretrained(source)
    model = WhisperForConditionalGeneration.from_pretrained(source)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model.to(device).train()
    optim = torch.optim.AdamW(model.parameters(), lr=1e-5)
    deadline = time.time() + max_minutes * 60
    steps = 0
    while time.time() < deadline and train_rows:
        random.shuffle(train_rows)
        for row in train_rows:
            if time.time() >= deadline:
                break
            audio, rate = sf.read(row["audio"], dtype="float32")
            if rate != 16000:
                continue
            features = processor.feature_extractor(audio, sampling_rate=16000, return_tensors="pt").input_features
            processor.tokenizer.set_prefix_tokens(language=whisper_language(row["language"]), task="transcribe")
            labels = processor.tokenizer(row["text"], return_tensors="pt").input_ids
            loss = model(input_features=features.to(device), labels=labels.to(device)).loss
            loss.backward()
            optim.step()
            optim.zero_grad()
            steps += 1
            if steps % 200 == 0:
                model.save_pretrained(ckpt)
                processor.save_pretrained(ckpt)
    model.save_pretrained(ckpt)
    processor.save_pretrained(ckpt)
    return ckpt, steps


def transcribe(model_dir: str | pathlib.Path, rows) -> list[str]:
    import soundfile as sf
    import torch
    from transformers import WhisperForConditionalGeneration, WhisperProcessor

    processor = WhisperProcessor.from_pretrained(model_dir)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = WhisperForConditionalGeneration.from_pretrained(model_dir).to(device).eval()
    out = []
    for row in rows:
        audio, _ = sf.read(row["audio"], dtype="float32")
        features = processor.feature_extractor(audio, sampling_rate=16000, return_tensors="pt").input_features
        with torch.no_grad():
            ids = model.generate(features.to(device), language=whisper_language(row["language"]), task="transcribe", max_new_tokens=64)
        out.append(processor.batch_decode(ids, skip_special_tokens=True)[0])
    return out


def export_int8(model_dir: pathlib.Path, out: pathlib.Path) -> pathlib.Path:
    """ONNX + int8 for phones, packed as asr-ta.tar.bz2."""
    from onnxruntime.quantization import QuantType, quantize_dynamic
    from optimum.onnxruntime import ORTModelForSpeechSeq2Seq

    onnx_dir = out / "onnx"
    ORTModelForSpeechSeq2Seq.from_pretrained(model_dir, export=True).save_pretrained(onnx_dir)
    pack_dir = out / "pack"
    pack_dir.mkdir(parents=True, exist_ok=True)
    for f in onnx_dir.glob("*.onnx"):
        quantize_dynamic(str(f), str(pack_dir / f.name.replace(".onnx", ".int8.onnx")), weight_type=QuantType.QInt8)
    for f in onnx_dir.glob("*.json"):
        (pack_dir / f.name).write_bytes(f.read_bytes())
    archive = out / "packs" / "asr-ta.tar.bz2"
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, "w:bz2") as tar:
        for f in sorted(pack_dir.iterdir()):
            tar.add(f, arcname=f.name)
    return archive


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--data", type=pathlib.Path, required=True)
    p.add_argument("--out", type=pathlib.Path, required=True)
    p.add_argument("--max-minutes", type=float, default=300)
    p.add_argument("--dry-run", action="store_true", help="split and report only")
    p.add_argument("--evaluate-base", action="store_true",
                   help="export only if held-out WER improves on Whisper tiny")
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    train_rows, test_rows = load_dataset(a.data)
    report = {"train": len(train_rows), "test": len(test_rows), "base": BASE_MODEL}
    if a.dry_run or not train_rows or not test_rows:
        report["skipped"] = "dry run" if a.dry_run else "need more distinct recordings"
        (a.out / "train_report.json").write_text(json.dumps(report, indent=1))
        print(json.dumps(report))
        return
    from evaluate_wer import wer

    ckpt, steps = train(train_rows, a.out, a.max_minutes)
    hyps = transcribe(ckpt, test_rows)
    report.update({"steps": steps, "wer": wer([r["text"] for r in test_rows], hyps)})
    if a.evaluate_base:
        base_hyps = transcribe(BASE_MODEL, test_rows)
        report["base_wer"] = wer([r["text"] for r in test_rows], base_hyps)
    if not a.evaluate_base or report["wer"] < report["base_wer"]:
        report["pack"] = str(export_int8(ckpt, a.out))
    (a.out / "train_report.json").write_text(json.dumps(report, indent=1, ensure_ascii=False))
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
