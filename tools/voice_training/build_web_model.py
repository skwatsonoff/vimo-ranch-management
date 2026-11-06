"""Turns a Whisper model from Hugging Face into files the phone's browser
can run with transformers.js (VIMO's own ear, no speech service needed).

    python build_web_model.py <hf model id> <openai base, e.g. openai/whisper-small> <out dir>

Writes <out dir>/config.json, generation_config.json, preprocessor_config.json,
tokenizer files and onnx/{encoder_model,decoder_model_merged}_quantized.onnx
(8-bit). Weights bigger than GitHub's 100 MB file limit are split into
"<file>_data", "<file>_data_1", ... chunks, the names transformers.js reads
when config.json says how many chunks there are.
"""
from __future__ import annotations

import json
import pathlib
import shutil
import sys
import tempfile

CHUNK = 90 * 1024 * 1024  # under GitHub's 100 MB limit per file


def _tensors(graph):
    """Every weight in [graph] and in its sub-graphs (the merged decoder
    keeps its two branches in an If node)."""
    for t in graph.initializer:
        yield t
    for node in graph.node:
        for attr in node.attribute:
            if attr.g is not None and attr.g.ByteSize():
                yield from _tensors(attr.g)
            for g in attr.graphs:
                yield from _tensors(g)


def split_external(path: pathlib.Path) -> int:
    """Moves the weights of the ONNX file at [path] into chunks of at most
    CHUNK bytes next to it. Returns the number of chunks (0: small enough)."""
    import onnx
    from onnx.external_data_helper import set_external_data

    if path.stat().st_size <= CHUNK:
        return 0
    model = onnx.load(str(path), load_external_data=True)
    chunks: list[bytearray] = [bytearray()]
    for tensor in _tensors(model.graph):
        if not tensor.HasField("raw_data") or len(tensor.raw_data) < 1024:
            continue
        data = tensor.raw_data
        if len(chunks[-1]) + len(data) > CHUNK and len(chunks[-1]) > 0:
            chunks.append(bytearray())
        index = len(chunks) - 1
        name = f"{path.name}_data" + ("" if index == 0 else f"_{index}")
        # Keep offsets aligned for the runtime.
        pad = (-len(chunks[-1])) % 64
        chunks[-1].extend(b"\0" * pad)
        set_external_data(tensor, location=name, offset=len(chunks[-1]), length=len(data))
        chunks[-1].extend(data)
        tensor.ClearField("raw_data")
        tensor.data_location = onnx.TensorProto.EXTERNAL
    for i, chunk in enumerate(chunks):
        (path.parent / (f"{path.name}_data" + ("" if i == 0 else f"_{i}"))).write_bytes(chunk)
    with open(path, "wb") as f:
        f.write(model.SerializeToString())
    return len(chunks)


def build(model_id: str, base_id: str, out: pathlib.Path) -> dict:
    from onnxruntime.quantization import QuantType, quantize_dynamic
    from optimum.exporters.onnx import main_export
    from transformers import GenerationConfig, WhisperProcessor

    out.mkdir(parents=True, exist_ok=True)
    (out / "onnx").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        main_export(model_id, output=tmp, task="automatic-speech-recognition-with-past")
        for name in ("encoder_model", "decoder_model_merged"):
            quantize_dynamic(
                f"{tmp}/{name}.onnx",
                str(out / "onnx" / f"{name}_quantized.onnx"),
                weight_type=QuantType.QUInt8,
                per_channel=False,
                reduce_range=False,
                extra_options={"EnableSubgraph": True},
            )
        for name in ("config.json",):
            shutil.copy(f"{tmp}/{name}", out / name)
    # The fine-tuned models keep an old generation config: the base model's
    # one knows the languages and tasks ("tamil", "transcribe").
    GenerationConfig.from_pretrained(base_id).save_pretrained(out)
    WhisperProcessor.from_pretrained(model_id).save_pretrained(out)
    chunks = {}
    for name in ("encoder_model_quantized.onnx", "decoder_model_merged_quantized.onnx"):
        n = split_external(out / "onnx" / name)
        if n:
            chunks[name] = n
    config = json.loads((out / "config.json").read_text())
    config["transformers.js_config"] = {"use_external_data_format": chunks} if chunks else {}
    (out / "config.json").write_text(json.dumps(config, indent=1))
    files = sorted(str(p.relative_to(out)) for p in out.rglob("*") if p.is_file())
    size = sum((out / f).stat().st_size for f in files)
    return {"model": model_id, "files": files, "bytes": size, "chunks": chunks}


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    info = build(sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3]))
    print(json.dumps({k: info[k] for k in ("model", "bytes", "chunks")}))
