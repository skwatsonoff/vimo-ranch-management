"""Shared helpers for VIMO's cloud voice training.

Plain words: these scripts run on a free GitHub Actions machine (or Google
Colab). They read the owner's recordings from Firestore (free plan), train
a small speech model, check it, and publish it as a language pack (a free
GitHub release) that the phone downloads. Nothing here runs on the phone.
"""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import re
import unicodedata

PROJECT = os.environ.get("VIMO_PROJECT", "my-ranch-sync")

# Packs are published as assets of one GitHub release (free, public).
REPO = os.environ.get("GITHUB_REPOSITORY", "skwatsonoff/vimo-ranch-management")
RELEASE_TAG = os.environ.get("VIMO_PACKS_TAG", "voice-packs")

# App language -> pack languages (keep equal to the app's bundles).
BUNDLES = {"ta": ["ta", "en", "ta-Latn"]}


def sha256_of(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def normalise_text(text: str) -> str:
    """Text as the model learns it: NFC, lower case, no punctuation."""
    text = unicodedata.normalize("NFC", text).lower()
    text = re.sub(r"[^\w\s஀-௿.]", " ", text)
    text = re.sub(r"(?<!\d)\.|\.(?!\d)", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def public_url(asset: str, repo: str = REPO, tag: str = RELEASE_TAG) -> str:
    """Download address of a release asset (what the phone fetches)."""
    return f"https://github.com/{repo}/releases/download/{tag}/{asset}"


def read_json(path: pathlib.Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default
