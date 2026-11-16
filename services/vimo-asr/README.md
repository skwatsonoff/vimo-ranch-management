# VIMO private speech-to-text runner

Turns one short sentence of audio (≤ 15 s, 16 kHz mono WAV) into text for a
signed-in ranch member. Used by the iPhone web app's capture path
(`lib/voice_asr_remote.dart`).

* **Auth:** Firebase ID token verified here; ranch membership read with the
  caller's own token, so Firestore rules decide.
* **Privacy:** audio is decoded in memory and dropped after the reply. No
  disk writes, no content logs, `Cache-Control: no-store`.
* **Model:** loaded at start from the owner's private Drive
  (`drive_model.py`), checked against `asr-manifest.json` sha256, held in
  memory; the temporary download is removed. Any failed check = not started.
* **Limits:** one transcription at a time, 20 per person per minute.

## Status: code ready, host NOT chosen

A host must be explicitly approved by the owner and verified as
**zero-billing** (no card, no paid fallback, no automatic upgrade). Until
then the app shows “Voice recognition is not set up yet” with Manual Entry.
The decision needed is listed in `docs/VIMO_VOICE_HANDOFF.md`.

## Model candidates (verify licence before use)

| Model | Size | Licence (to re-verify) | Notes |
| --- | --- | --- | --- |
| `openai/whisper-small` (multilingual, CTranslate2 int8) | ~250 MB | MIT | Baseline Tamil; measure WER first |
| `vasista22/whisper-tamil-small` (IIT Madras SPRING Lab fine-tune) | ~250 MB | check model card | Previously used by VIMO in the browser |

Record the chosen model's licence, version, source and any modification in
`asr-manifest.json` in Drive.

## Run tests

```
pip install -r requirements.txt
python -m pytest -q tests
```
