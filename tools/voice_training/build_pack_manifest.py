"""Builds language_packs/manifest.json: every pack file with its version,
size and SHA-256, so the phone can check what it downloads.

Versions only go up: a pack whose file changed gets version + 1; an
unchanged file keeps its version (phones then download nothing).

    python build_pack_manifest.py packs_dir old_manifest.json new_manifest.json
"""
from __future__ import annotations

import json
import pathlib
import sys

from common import BUNDLES, public_url, read_json, sha256_of

KINDS = {"asr", "nlu", "tts", "strings", "lexicon"}


def parse_name(path: pathlib.Path) -> tuple[str, str, str]:
    """"asr-ta.tar.bz2" -> (id "asr-ta", kind "asr", language "ta")."""
    stem = path.name.split(".")[0]
    kind, _, language = stem.partition("-")
    if kind not in KINDS or not language:
        raise ValueError(f"pack file {path.name} must be <kind>-<language>.<ext>")
    return stem, kind, language


def build(packs_dir: pathlib.Path, old: dict) -> dict:
    previous = {p["id"]: p for p in old.get("packs", [])}
    packs = []
    for path in sorted(packs_dir.iterdir()):
        if path.is_dir() or path.name == "manifest.json":
            continue
        pack_id, kind, language = parse_name(path)
        digest = sha256_of(path)
        before = previous.get(pack_id)
        version = before["version"] if before and before["sha256"] == digest else (before["version"] + 1 if before else 1)
        asset = f"{pack_id}-{version}{''.join(path.suffixes)}"
        packs.append({
            "id": pack_id,
            "language": language,
            "kind": kind,
            "version": version,
            "url": public_url(asset),
            "asset": asset,
            "localFile": str(path),
            "sizeBytes": path.stat().st_size,
            "sha256": digest,
        })
    # Packs not rebuilt this time stay as they were.
    built = {p["id"] for p in packs}
    packs.extend(p for pid, p in previous.items() if pid not in built)
    return {"schema": 1, "bundles": BUNDLES, "packs": sorted(packs, key=lambda p: p["id"])}


if __name__ == "__main__":
    manifest = build(pathlib.Path(sys.argv[1]), read_json(pathlib.Path(sys.argv[2]), {}))
    pathlib.Path(sys.argv[3]).write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{len(manifest['packs'])} packs")
