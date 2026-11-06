"""Runs one VIMO voice training job, start to finish.

    python train_job.py check          # prints a requested job id, or nothing
    python train_job.py run <job_id>   # trains, checks, publishes, reports

Each step writes the job's status in Firestore so the phone shows it live:
requested -> running -> evaluating -> packaging -> ready (or failed).
A new listening model is published only when its word error rate is lower
than the previous model's: a worse model never reaches the phone.

Needs Google credentials (GOOGLE_APPLICATION_CREDENTIALS, set by the
workflow from the FIREBASE_SERVICE_ACCOUNT secret) to read Firestore, and
GH_TOKEN (the workflow's own GitHub token) to publish packs to the
"voice-packs" release. Everything stays on free plans.
"""
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import time

from common import PROJECT, RELEASE_TAG, read_json

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


def download(db, owner: str, dest: pathlib.Path) -> int:
    """The owner's recordings (Firestore voice_training_audio) as WAV +
    JSON files, and their words (voice_training_lexicon) as lexicon.json."""
    dest.mkdir(parents=True, exist_ok=True)
    n = 0
    for snap in db.collection("voice_training_audio").where("ownerUid", "==", owner).stream():
        d = snap.to_dict() or {}
        meta = json.loads(d.get("sidecar") or "{}")
        lang = meta.get("language", "ta")
        folder = dest / lang
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{snap.id}.wav").write_bytes(bytes(d.get("wav") or b""))
        (folder / f"{snap.id}.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
        n += 1
    lex = db.collection("voice_training_lexicon").document(owner).get()
    if lex.exists:
        (dest / "lexicon.json").write_text((lex.to_dict() or {}).get("json", "{}"), encoding="utf-8")
    return n


def _gh(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(["gh", *args], check=check, capture_output=True, text=True)


def publish(packs_dir: pathlib.Path) -> dict:
    """Uploads changed packs and the manifest to the GitHub release."""
    from build_pack_manifest import build

    if _gh("release", "view", RELEASE_TAG, check=False).returncode != 0:
        _gh("release", "create", RELEASE_TAG, "--title", "VIMO voice packs",
            "--notes", "Language packs for VIMO offline voice. Written by the training workflow.")
    old_dir = WORK / "old_manifest"
    old_dir.mkdir(parents=True, exist_ok=True)
    _gh("release", "download", RELEASE_TAG, "-p", "manifest.json", "-D", str(old_dir), "--clobber", check=False)
    old = read_json(old_dir / "manifest.json", {})
    manifest = build(packs_dir, old)
    old_ids = {(p["id"], p["sha256"]) for p in old.get("packs", [])}
    upload_dir = WORK / "upload"
    upload_dir.mkdir(parents=True, exist_ok=True)
    for p in manifest["packs"]:
        local = p.pop("localFile", None)
        if local and (p["id"], p["sha256"]) not in old_ids:
            target = upload_dir / p["asset"]
            target.write_bytes(pathlib.Path(local).read_bytes())
            _gh("release", "upload", RELEASE_TAG, str(target), "--clobber")
    out = upload_dir / "manifest.json"
    out.write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
    _gh("release", "upload", RELEASE_TAG, str(out), "--clobber")
    return manifest


def learn_from_recordings(db, owner: str, data: pathlib.Path) -> int:
    """VIMO's understanding, taught by the owner's recordings: cow names as
    the owner says them, written to voice_training_lessons/<owner> for the
    phone. Returns how many spellings were learned."""
    from google.cloud import firestore

    from learn_lessons import learn
    from transcribe import transcribe

    ref = db.collection("voice_training_lessons").document(owner)
    old = ref.get()
    cache = {}
    if old.exists:
        cache = json.loads((old.to_dict() or {}).get("json") or "{}").get("heard", {})
    rows = transcribe(data, cache)
    lexicon = read_json(data / "lexicon.json", {})
    cows = [c for c in lexicon.get("cows", []) if c.get("name")]
    lessons = learn(rows, cows)
    lessons["recordings"] = len(rows)
    lessons["createdAt"] = time.time()
    # What was heard, so the next run only listens to new recordings.
    lessons["heard"] = {r["id"]: r["asr"] for r in rows}
    ref.set({"json": json.dumps(lessons, ensure_ascii=False), "updatedAt": firestore.SERVER_TIMESTAMP})
    learned = sum(len(v) for v in lessons["aliases"].values())
    print(f"lessons: {learned} spellings for {len(lessons['aliases'])} cows from {len(rows)} recordings")
    return learned


def run(job_id: str):
    db = _firestore()
    jobs = _jobs(db)
    job = next((j for j in jobs if j["id"] == job_id), None)
    if not job:
        sys.exit(f"job {job_id} not found")
    owner = job["ownerUid"]
    log_url = os.environ.get("VIMO_LOG_URL", "")
    _set(db, job_id, status="running", logUrl=log_url, startedAt=time.time())
    try:
        data = WORK / "data"
        count = download(db, owner, data)
        learned = learn_from_recordings(db, owner, data)
        # Taps on "Start training" that were waiting are answered by this run.
        for other in jobs:
            if other["id"] != job_id and other.get("ownerUid") == owner and other.get("status") == "requested":
                _set(db, other["id"], status="ready", lessons=learned, files=count, note=f"Answered by {job_id}")
        if os.environ.get("VIMO_FINETUNE") != "1":
            # VIMO's own listening model waits for the offline engine on
            # the phone; until then the lessons are what helps.
            _set(db, job_id, status="ready", lessons=learned, files=count)
            return
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
        if not os.environ.get("GH_TOKEN"):
            # Colab without a GitHub token: trained and checked; the GitHub
            # workflow publishes the packs on its next run.
            _set(db, job_id, status="requested", wer=new_wer, previousWer=old_wer,
                 note="Trained in Colab; publishing on the next workflow run")
            return
        manifest = publish(packs)
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
