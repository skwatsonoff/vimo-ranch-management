"""Loads VIMO's active speech model from the owner's private Google Drive.

The owner's OAuth refresh token (scope drive.file, for the folder the VIMO
bridge created) is a host secret (VIMO_DRIVE_REFRESH_TOKEN, with
VIMO_OAUTH_CLIENT_ID / VIMO_OAUTH_CLIENT_SECRET). The model snapshot is
downloaded to a temporary directory, checked against the sha256 in
models/asr-manifest.json, loaded into memory, and the directory is removed.
Nothing persists on the host. Any check failing means the runner does not
start (the app then shows "voice recognition is not set up").
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import tempfile

import numpy as np


class FasterWhisperTranscriber:  # pragma: no cover - needs the model
    def __init__(self, model_dir: str):
        from faster_whisper import WhisperModel
        self.model = WhisperModel(model_dir, device="cpu", compute_type="int8")

    def transcribe(self, audio: np.ndarray, language: str, hints: list[str]) -> str:
        prompt = ", ".join(hints[:40]) or None
        segments, _ = self.model.transcribe(audio, language=language, beam_size=1,
                                            vad_filter=False, initial_prompt=prompt,
                                            condition_on_previous_text=False)
        return " ".join(s.text.strip() for s in segments)


def verify_files(directory: str, manifest: dict) -> None:
    for name, digest in manifest["files"].items():
        h = hashlib.sha256()
        with open(os.path.join(directory, name), "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        if h.hexdigest() != digest:
            raise RuntimeError(f"checksum mismatch: {name}")


def load_model_from_drive():  # pragma: no cover - needs Drive
    from google.oauth2.credentials import Credentials
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaIoBaseDownload

    creds = Credentials(None, refresh_token=os.environ["VIMO_DRIVE_REFRESH_TOKEN"],
                        token_uri="https://oauth2.googleapis.com/token",
                        client_id=os.environ["VIMO_OAUTH_CLIENT_ID"],
                        client_secret=os.environ["VIMO_OAUTH_CLIENT_SECRET"],
                        scopes=["https://www.googleapis.com/auth/drive.file"])
    drive = build("drive", "v3", credentials=creds, cache_discovery=False)
    folder = os.environ["VIMO_MODEL_FOLDER_ID"]

    def find(name: str, parent: str) -> str:
        q = f"name = '{name}' and '{parent}' in parents and trashed = false"
        files = drive.files().list(q=q, fields="files(id)").execute()["files"]
        if len(files) != 1:
            raise RuntimeError(f"missing {name}")
        return files[0]["id"]

    def download(file_id: str, path: str) -> None:
        with open(path, "wb") as out:
            request = drive.files().get_media(fileId=file_id)
            done = False
            downloader = MediaIoBaseDownload(out, request, chunksize=8 << 20)
            while not done:
                _, done = downloader.next_chunk()

    scratch = tempfile.mkdtemp(prefix="vimo-asr-")
    try:
        manifest_path = os.path.join(scratch, "asr-manifest.json")
        download(find("asr-manifest.json", folder), manifest_path)
        with open(manifest_path) as f:
            manifest = json.load(f)
        if manifest.get("schema") != "vimo.asr-manifest.v1":
            raise RuntimeError("manifest")
        snapshot = find(manifest["snapshot"], folder)
        for name in manifest["files"]:
            download(find(name, snapshot), os.path.join(scratch, name))
        verify_files(scratch, manifest)
        return FasterWhisperTranscriber(scratch)
    finally:
        # The model is in memory now (CTranslate2 loads it fully).
        shutil.rmtree(scratch, ignore_errors=True)
