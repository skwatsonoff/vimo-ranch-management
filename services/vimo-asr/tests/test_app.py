import io
import json
import wave

import numpy as np
from fastapi.testclient import TestClient

import app as runner


def wav(seconds=1.0, rate=16000, channels=1):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes((np.sin(np.arange(int(rate * seconds)) / 9) * 8000).astype("<i2").tobytes())
    return buf.getvalue()


class FakeModel:
    def __init__(self):
        self.calls = []

    def transcribe(self, audio, language, hints):
        self.calls.append((len(audio), language, hints))
        return " கண்மணி அஞ்சு லிட்டர் "


def verify(token, ranch):
    return runner.Caller("uid-1", ranch) if token == "good" and ranch == "ranch_1" else None


def client(limit=20):
    model = FakeModel()
    app = runner.create_app(model, verify, runner.RateLimiter(limit))
    return TestClient(app), model


H = {"Authorization": "Bearer good", "X-Vimo-Ranch": "ranch_1", "X-Vimo-Locale": "ta-IN", "Content-Type": "audio/wav"}


def test_transcribes_a_member_sentence_without_storing():
    c, model = client()
    r = c.post("/v1/transcribe", content=wav(), headers=H)
    assert r.status_code == 200
    assert r.json() == {"schema": "vimo.asr.v1", "text": "கண்மணி அஞ்சு லிட்டர்"}
    assert r.headers["cache-control"] == "no-store"
    assert model.calls[0][1] == "ta"


def test_refuses_without_valid_token_or_membership():
    c, model = client()
    assert c.post("/v1/transcribe", content=wav(), headers={**H, "Authorization": ""}).status_code == 401
    assert c.post("/v1/transcribe", content=wav(), headers={**H, "Authorization": "Bearer bad"}).status_code == 403
    assert c.post("/v1/transcribe", content=wav(), headers={**H, "X-Vimo-Ranch": "other"}).status_code == 403
    assert model.calls == []


def test_rejects_long_or_wrong_audio():
    c, model = client()
    assert c.post("/v1/transcribe", content=wav(16), headers=H).status_code == 400
    assert c.post("/v1/transcribe", content=wav(rate=44100), headers=H).status_code == 400
    assert c.post("/v1/transcribe", content=wav(channels=2), headers=H).status_code == 400
    assert c.post("/v1/transcribe", content=b"nope", headers=H).status_code == 400
    assert model.calls == []


def test_per_person_limit():
    c, model = client(limit=2)
    assert [c.post("/v1/transcribe", content=wav(), headers=H).status_code for _ in range(3)] == [200, 200, 429]


def test_model_failure_is_unavailable_and_says_nothing_more():
    class Broken:
        def transcribe(self, *a):
            raise RuntimeError("secret detail கண்மணி")
    c = TestClient(runner.create_app(Broken(), verify))
    r = c.post("/v1/transcribe", content=wav(), headers=H)
    assert r.status_code == 503 and r.json() == {"error": "unavailable"}


def test_manifest_checksum(tmp_path):
    from drive_model import verify_files
    (tmp_path / "model.bin").write_bytes(b"weights")
    import hashlib
    good = {"files": {"model.bin": hashlib.sha256(b"weights").hexdigest()}}
    verify_files(str(tmp_path), good)
    bad = {"files": {"model.bin": "0" * 64}}
    try:
        verify_files(str(tmp_path), bad)
        assert False
    except RuntimeError:
        pass
