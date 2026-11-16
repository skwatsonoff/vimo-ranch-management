"""VIMO's private speech-to-text runner.

* Loads VIMO's speech model from the owner's private Google Drive at start
  (services/vimo-asr/drive_model.py), verifies its checksum against the
  Drive manifest, and keeps it in memory / temporary scratch only.
* Each request is one short sentence (<= 15 s, 16 kHz mono WAV) from a
  signed-in ranch member. The Firebase ID token is verified here, and ranch
  membership is read with the caller's own token (Firestore rules decide).
* Audio is decoded in memory and dropped after the reply. Nothing is
  written to disk, logged or cached; replies carry Cache-Control: no-store.
* One request at a time per process, per-person limits, a hard size limit.

Run (after the owner approves a zero-billing host):
    VIMO_FIREBASE_PROJECT=my-ranch-sync uvicorn app:app --host 0.0.0.0 --port 8080
"""
from __future__ import annotations

import io
import os
import threading
import time
import wave
from dataclasses import dataclass
from typing import Callable, Optional, Protocol

import numpy as np
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse

MAX_SECONDS = 15
RATE = 16000
MAX_BYTES = 44 + RATE * 2 * MAX_SECONDS
PER_PERSON_PER_MINUTE = 20
SCHEMA = "vimo.asr.v1"
NO_STORE = {"Cache-Control": "no-store", "Pragma": "no-cache"}


class Transcriber(Protocol):
    def transcribe(self, audio: np.ndarray, language: str, hints: list[str]) -> str: ...


@dataclass
class Caller:
    uid: str
    ranch: str


def decode_wav(body: bytes) -> np.ndarray:
    """16 kHz mono 16-bit WAV -> float32 in [-1, 1]. Raises ValueError."""
    if len(body) < 44 or len(body) > MAX_BYTES or body[:4] != b"RIFF" or body[8:12] != b"WAVE":
        raise ValueError("wav")
    with wave.open(io.BytesIO(body)) as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2 or w.getframerate() != RATE:
            raise ValueError("format")
        frames = w.readframes(min(w.getnframes(), RATE * MAX_SECONDS))
    return np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768.0


class RateLimiter:
    def __init__(self, per_minute: int, clock: Callable[[], float] = time.monotonic):
        self.per_minute = per_minute
        self.clock = clock
        self.seen: dict[str, list[float]] = {}
        self.lock = threading.Lock()

    def allow(self, key: str) -> bool:
        now = self.clock()
        with self.lock:
            recent = [t for t in self.seen.get(key, []) if now - t < 60]
            if len(recent) >= self.per_minute:
                self.seen[key] = recent
                return False
            recent.append(now)
            self.seen[key] = recent
            return True


def firebase_verifier(project: str) -> Callable[[str, str], Optional[Caller]]:
    """Verifies the ID token signature/audience, then reads membership with
    the caller's own token so Firestore security rules decide."""
    import requests
    from google.auth.transport import requests as google_requests
    from google.oauth2 import id_token

    session = google_requests.Request()

    def verify(token: str, ranch: str) -> Optional[Caller]:
        try:
            claims = id_token.verify_firebase_token(token, session, audience=project)
        except Exception:
            return None
        uid = claims.get("sub") if claims else None
        if not uid:
            return None
        url = (f"https://firestore.googleapis.com/v1/projects/{project}/databases/(default)"
               f"/documents/ranches/{ranch}/members/{uid}")
        reply = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=8)
        if reply.status_code != 200:
            return None
        fields = reply.json().get("fields", {})
        if fields.get("active", {}).get("booleanValue") is False:
            return None
        if fields.get("status", {}).get("stringValue", "active") != "active":
            return None
        return Caller(uid=uid, ranch=ranch)

    return verify


def create_app(transcriber: Transcriber, verify: Callable[[str, str], Optional[Caller]],
               limiter: Optional[RateLimiter] = None) -> FastAPI:
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
    busy = threading.Lock()
    limits = limiter or RateLimiter(PER_PERSON_PER_MINUTE)

    def fail(status: int, code: str) -> JSONResponse:
        return JSONResponse({"error": code}, status_code=status, headers=NO_STORE)

    @app.get("/healthz")
    def health():
        return JSONResponse({"ok": True}, headers=NO_STORE)

    @app.post("/v1/transcribe")
    async def transcribe(request: Request,
                         authorization: str = Header(default=""),
                         x_vimo_ranch: str = Header(default=""),
                         x_vimo_locale: str = Header(default="ta-IN"),
                         x_vimo_hints: str = Header(default="")):
        if not authorization.startswith("Bearer ") or not x_vimo_ranch or len(x_vimo_ranch) > 80:
            return fail(401, "access")
        caller = verify(authorization[7:], x_vimo_ranch)
        if caller is None:
            return fail(403, "access")
        if not limits.allow(caller.uid):
            return fail(429, "quota")
        body = await request.body()
        try:
            audio = decode_wav(body)
        except ValueError:
            return fail(400, "input")
        finally:
            del body
        hints: list[str] = []
        if x_vimo_hints:
            import base64
            try:
                hints = [h for h in base64.b64decode(x_vimo_hints).decode("utf-8").split("\n") if h][:60]
            except Exception:
                hints = []
        language = "ta" if x_vimo_locale.lower().startswith("ta") else "en"
        if not busy.acquire(timeout=20):
            return fail(429, "busy")
        try:
            text = transcriber.transcribe(audio, language, hints)
        except Exception:
            return fail(503, "unavailable")
        finally:
            busy.release()
            del audio
        return JSONResponse({"schema": SCHEMA, "text": (text or "").strip()[:400]}, headers=NO_STORE)

    return app


def _production_app() -> FastAPI:  # pragma: no cover - needs the model and Drive
    from drive_model import load_model_from_drive
    project = os.environ["VIMO_FIREBASE_PROJECT"]
    transcriber = load_model_from_drive()
    return create_app(transcriber, firebase_verifier(project))


app = _production_app() if os.environ.get("VIMO_FIREBASE_PROJECT") else None
