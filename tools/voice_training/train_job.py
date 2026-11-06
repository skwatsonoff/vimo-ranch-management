"""Runs one VIMO voice training job, start to finish.

    python train_job.py check          # prints a requested job id, or nothing
    python train_job.py run <job_id>   # trains, checks, publishes, reports

Each step writes the job's status in Firestore so the phone shows it live:
requested -> running -> evaluating -> packaging -> ready (or failed).
A new listening model is published only when its word error rate is lower
than the previous model's: a worse model never reaches the phone.

Needs Google credentials (GOOGLE_APPLICATION_CREDENTIALS), which the
workflow sets from the FIREBASE_SERVICE_ACCOUNT secret.
"""
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import time

from common import BUCKET, PROJECT, read_json

WORK = pathlib.Path(os.environ.get("VIMO_WORK", "work"))


def pick_requested(jobs: list[dict]) -> dict | None:
    """The oldest job still waiting, so requests are served in order."""
    waiting = [j for j in jobs if j.get("status") == "requested"]
    return min(waiting, key=lambda j: j.get("createdAt") or 0) if waiting else None


def previous_wer(jobs: list[dict], owner: str, current: str) -> float | None:
    """The best word error rate of this owner's earlier ready jobs."""
    done = [j.get("wer") for j in jobs if j.get("ownerUid") == owner and j.get("id") != current
            and j.get("status") == "ready" and isinstance(j.get("wer"), (int, float))]
    return min(done) if done else None


def should_publish(new_wer: float | None, old_wer: float | None) -> bool:
    if new_wer is None:
        return False
    return old_wer is None or new_wer < old_wer


def _firestore():
    from google.cloud import firestore

    return firestore.Client(project=PROJECT)


def _bucket():
    from google.cloud import storage

    return storage.Client(project=PROJECT).bucket(BUCKET)


def _jobs(db) -> list[dict]:
    out = []
    for snap in db.collection("voice_training_jobs").stream():
        d = snap.to_dict() or {}
        d["id"] = snap.id
        created = d.get("createdAt")
        d["createdAt"] = created.timestamp() if hasattr(created, "timestamp") else 0
        out.append(d)
    return out


def _set(db, job_id: str, **fields):
    from google.cloud import firestore

    fields["updatedAt"] = firestore.SERVER_TIMESTAMP
    db.collection("voice_training_jobs").document(job_id).set(fields, merge=True)


def download(bucket, owner: str, dest: pathlib.Path) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    n = 0
    for blob in bucket.list_blobs(prefix=f"training_data/{owner}/"):
        target = dest / blob.name.removeprefix(f"training_data/{owner}/")
        target.parent.mkdir(parents=True, exist_ok=True)
        blob.download_to_filename(target)
        n += 1
    return n


def publish(bucket, packs_dir: pathlib.Path) -> dict:
    """Uploads changed packs and the manifest; returns the manifest."""
    from build_pack_manifest import build

    old_blob = bucket.blob("language_packs/manifest.json")
    old = json.loads(old_blob.download_as_text()) if old_blob.exists() else {}
    manifest = build(packs_dir, old)
    old_ids = {(p["id"], p["sha256"]) for p in old.get("packs", [])}
    for p in manifest["packs"]:
        local = p.pop("localFile", None)
        if local and (p["id"], p["sha256"]) not in old_ids:
            bucket.blob(p["storagePath"]).upload_from_filename(local)
    old_blob.upload_from_string(json.dumps(manifest, ensure_ascii=False), content_type="application/json")
    return manifest


def run(job_id: str):
    db = _firestore()
    bucket = _bucket()
    jobs = _jobs(db)
    job = next((j for j in jobs if j["id"] == job_id), None)
    if not job:
        sys.exit(f"job {job_id} not found")
    owner = job["ownerUid"]
    log_url = os.environ.get("VIMO_LOG_URL", "")
    _set(db, job_id, status="running", logUrl=log_url, startedAt=time.time())
    try:
        data = WORK / "data"
        count = download(bucket, owner, data)
        lexicon = read_json(data / "lexicon.json", {})
        subprocess.run([sys.executable, "make_synthetic_text.py", str(data / "lexicon.json"), str(WORK / "synthetic.txt")], check=False)
        budget = os.environ.get("VIMO_MAX_MINUTES", "300")
        subprocess.run([sys.executable, "finetune_asr.py", "--data", str(data), "--out", str(WORK), "--max-minutes", budget], check=True)
        _set(db, job_id, status="evaluating")
        report = read_json(WORK / "train_report.json", {})
        new_wer = report.get("wer")
        old_wer = previous_wer(jobs, owner, job_id)
        _set(db, job_id, status="packaging", wer=new_wer, previousWer=old_wer, files=count)
        packs = WORK / "packs"
        packs.mkdir(parents=True, exist_ok=True)
        # The words pack (cow names, learned words) always helps.
        (packs / "lexicon-ta.json").write_text(json.dumps(lexicon, ensure_ascii=False), encoding="utf-8")
        if not should_publish(new_wer, old_wer):
            # Keep the old listening model: drop the new one before publishing.
            (packs / "asr-ta.tar.bz2").unlink(missing_ok=True)
        manifest = publish(bucket, packs)
        _set(db, job_id, status="ready", wer=new_wer, previousWer=old_wer,
             improved=should_publish(new_wer, old_wer),
             packVersions={p["id"]: p["version"] for p in manifest["packs"]})
    except Exception as error:  # report every failure to the phone
        _set(db, job_id, status="failed", error=str(error)[:500])
        raise


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "check":
        job = pick_requested(_jobs(_firestore()))
        print(job["id"] if job else "")
    elif len(sys.argv) >= 3 and sys.argv[1] == "run":
        run(sys.argv[2])
    else:
        sys.exit(__doc__)
