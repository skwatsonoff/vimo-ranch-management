# VIMO voice training (cloud)

Plain words first. Training a speech model needs a strong computer. The
phone therefore only **collects recordings and asks** for a training run;
the training itself runs on free cloud machines:

- **GitHub Actions** (`.github/workflows/voice-training.yml`): automatic,
  CPU only, up to about 5 hours per run, continues from a saved checkpoint
  next time.
- **Google Colab** (`finetune_asr_colab.ipynb`): the same steps on a free
  GPU, much faster. Open it from the GitHub app or colab.research.google.com.

When a run finishes, the new model is published as a language pack and the
phone offers **Install new model**, but only if it gets fewer words wrong
than the model before. In the meantime "Improve VIMO" on the phone gives an
instant improvement without any training.

## The steps of one run

| Status the phone shows | What happens | Script |
| --- | --- | --- |
| requested | The owner tapped **Start training** (Firestore `voice_training_jobs`) | app |
| running | Recordings (`voice_training_audio`) and words (`voice_training_lexicon`) read from Firestore | `train_job.py` |
| running | Extra dairy sentences made from cow names and learned words | `make_synthetic_text.py` |
| running | Whisper tiny fine-tuned on CPU for at most `VIMO_MAX_MINUTES` | `finetune_asr.py` |
| evaluating | Word error rate on held-out recordings | `evaluate_wer.py` |
| packaging | ONNX + int8 export, packs and `manifest.json` (versions only go up, size and SHA-256) uploaded to the "voice-packs" release | `build_pack_manifest.py` |
| ready / failed | Job updated with WER, previous WER, pack versions, log link | `train_job.py` |

A model that is not better is **not published**; only the words (lexicon)
pack is updated.

## Run it by hand (no laptop)

GitHub app → this repository → **Actions** → **Train VIMO voice** → **Run
workflow**. Leave the job id empty to take the oldest request.

## Tests

```bash
python -m pytest -q tools/voice_training/tests
```

They run in `flutter-checks.yml` and before every training run.

## Data and licences

- Free plans only: recordings are Firestore documents
  (`voice_training_audio`, one WAV under 1 MB each, at most 25 seconds) and
  the owner's words one document (`voice_training_lexicon/<uid>`); packs are
  assets of the free "voice-packs" GitHub release. No Firebase Storage, no
  paid plan.
- By default only **the owner's own recordings** are used; Firestore rules
  let only that signed-in user add, read or delete them, with a speaker tag
  the owner chose, never a name in an id.
- Base model: **OpenAI Whisper tiny**, MIT licence.
- Optional public data for Colab, only with licences that allow it:
  **Mozilla Common Voice Tamil** (CC0 1.0) and **Google FLEURS** Tamil
  (CC BY 4.0, credit Google). Do not add datasets whose licence forbids
  commercial use.

## Honest status

- The scripts' logic (WER, manifest versions, job selection, dataset
  split, synthetic text) is unit tested. The actual fine-tuning and ONNX
  export need real recordings and have not yet run end to end.
- The phone's offline engine (`OfflineSpeechEngine` in
  `lib/voice_engine.dart`) is still a placeholder: it needs an on-device
  ONNX Whisper runtime built into the Android/iOS apps. Until then VIMO
  falls back to the phone's own speech service, and the published words
  pack and learned words still help.
