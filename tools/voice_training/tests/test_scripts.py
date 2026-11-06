import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from build_pack_manifest import build, parse_name  # noqa: E402
from common import normalise_text, public_url  # noqa: E402
from evaluate_wer import wer  # noqa: E402
from finetune_asr import load_dataset  # noqa: E402
from make_synthetic_text import sentences  # noqa: E402
from train_job import pick_requested, previous_wer, should_publish  # noqa: E402


def test_wer():
    assert wer(["லட்சுமி 5 லிட்டர்"], ["லட்சுமி 5 லிட்டர்"]) == 0
    assert wer(["a b c d"], ["a x c"]) == 0.5
    assert wer(["Maina 5 litre."], ["maina 5 litre"]) == 0


def test_normalise_keeps_tamil_and_decimals():
    assert normalise_text("மைனா, 2.5 லிட்டர்!") == "மைனா 2.5 லிட்டர்"


def test_synthetic_text_uses_cows_and_learned_words():
    lines = sentences({"cows": [{"name": "Maina", "tamil": "மைனா"}],
                       "learned": [{"meant": "மைனா அஞ்சு லிட்டர்"}]})
    assert any("மைனா" in s for s in lines)
    assert any(s.startswith("maina ku") for s in lines)
    assert "மைனா அஞ்சு லிட்டர்" in lines
    assert len(lines) == len(set(lines))


def test_manifest_versions_only_go_up(tmp_path):
    packs = tmp_path / "packs"
    packs.mkdir()
    (packs / "asr-ta.tar.bz2").write_bytes(b"model one")
    (packs / "lexicon-ta.json").write_text("{}")
    first = build(packs, {})
    assert {p["id"]: p["version"] for p in first["packs"]} == {"asr-ta": 1, "lexicon-ta": 1}
    assert first["bundles"]["ta"] == ["ta", "en", "ta-Latn"]
    again = build(packs, first)
    assert {p["id"]: p["version"] for p in again["packs"]} == {"asr-ta": 1, "lexicon-ta": 1}
    (packs / "asr-ta.tar.bz2").write_bytes(b"model two")
    newer = build(packs, again)
    asr = next(p for p in newer["packs"] if p["id"] == "asr-ta")
    assert asr["version"] == 2
    assert asr["sizeBytes"] == len(b"model two")
    assert asr["url"] == public_url("asr-ta-2.tar.bz2")
    assert asr["url"].startswith("https://github.com/") and asr["asset"] == "asr-ta-2.tar.bz2"
    # A pack not rebuilt is kept.
    (packs / "lexicon-ta.json").unlink()
    kept = build(packs, newer)
    assert any(p["id"] == "lexicon-ta" for p in kept["packs"])


def test_pack_names():
    assert parse_name(pathlib.Path("asr-ta.tar.bz2")) == ("asr-ta", "asr", "ta")
    assert parse_name(pathlib.Path("lexicon-ta-Latn.json")) == ("lexicon-ta-Latn", "lexicon", "ta-Latn")


def test_jobs_in_order_and_never_worse():
    jobs = [
        {"id": "a", "status": "ready", "ownerUid": "u", "wer": 0.3, "createdAt": 1},
        {"id": "b", "status": "requested", "ownerUid": "u", "createdAt": 5},
        {"id": "c", "status": "requested", "ownerUid": "v", "createdAt": 3},
    ]
    assert pick_requested(jobs)["id"] == "c"
    assert pick_requested([{"status": "ready"}]) is None
    assert previous_wer(jobs, "u", "b") == 0.3
    assert previous_wer(jobs, "v", "c") is None
    assert should_publish(0.2, 0.3)
    assert not should_publish(0.35, 0.3)
    assert should_publish(0.4, None)
    assert not should_publish(None, None)


def test_dataset_split_is_stable(tmp_path):
    for i in range(20):
        (tmp_path / f"r{i}.wav").write_bytes(b"RIFF")
        (tmp_path / f"r{i}.json").write_text(json.dumps({"id": f"r{i}", "transcript": f"மைனா {i} லிட்டர்", "language": "ta"}))
    train1, test1 = load_dataset(tmp_path)
    train2, test2 = load_dataset(tmp_path)
    assert test1 == test2 and len(test1) >= 1
    assert len(train1) + len(test1) == 20
