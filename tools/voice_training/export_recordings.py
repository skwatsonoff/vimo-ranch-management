"""Copies every Train VIMO recording out of Firestore for offline study.

    python export_recordings.py <folder>

Writes <folder>/<owner>/<lang>/<id>.wav + .json, each owner's lexicon.json,
and <folder>/summary.json (counts and minutes per owner and language, and
the training jobs). Prints only counts: this repository is public, so its
logs are too. The workflow encrypts the folder before keeping it.
"""
from __future__ import annotations

import json
import pathlib
import sys

from train_job import _firestore, _jobs, download


def main(dest: pathlib.Path) -> None:
    db = _firestore()
    owners = sorted({(s.to_dict() or {}).get("ownerUid", "") for s in db.collection("voice_training_audio").select(["ownerUid"]).stream()} - {""})
    summary: dict = {"owners": {}, "jobs": []}
    for i, owner in enumerate(owners):
        folder = dest / f"owner{i + 1}"
        count = download(db, owner, folder)
        minutes: dict[str, float] = {}
        for meta in folder.glob("*/*.json"):
            m = json.loads(meta.read_text(encoding="utf-8"))
            lang = m.get("language", "?")
            minutes[lang] = minutes.get(lang, 0) + (m.get("durationMs") or 0) / 60000
        summary["owners"][folder.name] = {"uid": owner, "recordings": count, "minutes": {k: round(v, 2) for k, v in minutes.items()}}
        print(f"{folder.name}: {count} recordings, minutes {json.dumps(summary['owners'][folder.name]['minutes'])}")
    for job in _jobs(db):
        summary["jobs"].append({k: job.get(k) for k in ("id", "ownerUid", "status", "createdAt", "wer", "error")})
    print(f"training jobs: {len(summary['jobs'])}, statuses: {sorted({str(j['status']) for j in summary['jobs']})}")
    (dest / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=1, default=str), encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(pathlib.Path(sys.argv[1]))
