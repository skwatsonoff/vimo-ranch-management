# VIMO language packs and offline voice

Everything here uses free plans only (Firestore Spark, GitHub).

Plain words first: a **language pack** is one file VIMO downloads so that its
voice keeps working without the internet. Choosing a language in Settings
downloads what that language needs:

| App language | Packs downloaded |
| --- | --- |
| Tamil | Tamil + English + Tanglish (Tamil spoken with English words) |
| Any other language | That language + English |
| English | English |

Until packs are published and downloaded, VIMO works exactly as before: the
phone's own (online) speech service listens.

## Where things are

| What | Where |
| --- | --- |
| Pack list, download, checks | `lib/language_packs.dart` (pure Dart, works on web and phones) |
| Phone storage | `lib/language_pack_store_io.dart`: files in the app's support folder, `language_packs/<id>/pack.bin`; versions in Hive box `language_packs` |
| Browser storage | `lib/language_pack_store_web.dart`: small packs only (words, understanding, app text) in Hive; a browser has no offline speech recogniser, so recognition and voice packs are not downloaded on the web |
| Screen | Settings → **Download for offline voice** (`lib/language_pack_screen.dart`) |
| The one URL the owner edits | `languagePackManifestUrl` at the top of `lib/language_packs.dart` |
| Tests | `test/language_packs_test.dart` |

## The manifest

`manifest.json` and the pack files are assets of this repository's
**"voice-packs" GitHub release** (free, public, read-only for the app). The cloud training workflow writes it with
`tools/voice_training/build_pack_manifest.py`.

```json
{
  "schema": 1,
  "bundles": { "ta": ["ta", "en", "ta-Latn"] },
  "packs": [
    {
      "id": "asr-ta",
      "language": "ta",
      "kind": "asr",
      "version": 3,
      "url": "https://github.com/skwatsonoff/vimo-ranch-management/releases/download/voice-packs/asr-ta-3.tar.bz2",
      "sizeBytes": 48123456,
      "sha256": "9f2c…"
    }
  ]
}
```

- `kind`: `asr` (listening), `nlu` (understanding), `tts` (speaking voice),
  `strings` (app text), `lexicon` (words: dairy and village words, cow names,
  the owner's learned words).
- `language`: `ta`, `en`, `ta-Latn` (Tanglish), `hi`, `te`, `kn`, `ml`, …
- A language with no `bundles` entry gets itself plus English.

## How a download is kept safe

1. Only packs whose installed version is lower than the manifest's are
   fetched; a second install downloads nothing.
2. Bytes go to `<version>.part`. An interrupted download continues with an
   HTTP `Range` request from the bytes already saved.
3. The size and SHA-256 of the whole file are checked. A file that fails is
   deleted, never used.
4. Only then is it renamed to `pack.bin` and its version recorded.
5. Removing a language never removes English, nor a pack another installed
   language needs.
6. **Wi-Fi only** is on by default. Cancel keeps the partial file so Retry
   continues. A full phone shows "Not enough free space" (the phone reports
   it while writing; no extra plugin measures free space ahead of time).

## Self-test results that still fail

The phone's self-test (Settings → Voice test & report) runs
`assets/voice/voice_corpus.json`. Current failures are listed in the
section *Corpus failures* below, refreshed whenever the corpus changes.

### Corpus failures

`assets/voice/voice_corpus.json` (315 sentences in Tamil script, Tanglish,
English and a few Hindi; built by `tools/voice_corpus/build_corpus.py`):
**315 / 315 pass**. The owner's labelled sample sentences
(`test/data/voice_intent_samples.jsonl`, 7,464 sentences, 20 intents) pass
at **99.0%** (`test/voice_intents_test.dart`).

Honest limits: both sets are written text, not real recordings, and the
rules were tuned on them. Real speech brings recogniser mistakes; those are
what the live mic test, "Improve VIMO" and the voice report are for. Known
weak spots in the owner's samples:

- Small talk labelled "unknown" in the samples ("ok", "சரி") is read as a
  yes, because during a confirmation that is what it means.
- A few sickness sentences with uncommon words (about 5% of symptom
  samples) are not recognised as sickness.
- Expenses phrased only as "vet fee expense yesterday" (no amount) can be
  read as a doctor visit.

## Learning from the owner's recordings

"Start training" (Settings → Train VIMO) runs `.github/workflows/voice-training.yml`
on GitHub's free runner. It listens to every Train VIMO recording with
Whisper large-v3 (`tools/voice_training/transcribe.py`), lines each up with
the sentence that was read, and learns how each cow's name is said
(`learn_lessons.py`: "Shomperi" heard as "strawberry", "Maina" as "Miner").
The lessons go to `voice_training_lessons/<uid>` (only the owner can read
it; only the workflow writes it). The phone reads them each time voice milk
opens and uses them as extra names for the cows, never as recogniser hints.
Recordings already heard are cached in that document, so each run only
listens to new ones. One run answers every "Start training" tap waiting.

The same study found how recognisers write everyday dairy words
("சினை உருதியானது", "நொந்துது", "லேட்டர்", "நேர்த்து மாலை"); those
fixes are in `lib/voice_heard_fixes.dart` for everyone.

First study (224 recordings, three speakers): sentences understood the
same as what was read went from **58.9%** to **92.0%**; the 7,464 sample
sentences stay at **99.0%**. What is left is mostly the recogniser
mishearing numbers ("1000" for "aaru").

## VIMO's own ear (speech to text in the browser)

Apple's browser speech service has no Tamil, and a Home Screen web app may
not use the service at all. There VIMO listens itself, on the phone
(`web/vimo_ear.js`, `lib/voice_ear*.dart`):

| Language | Model | Download | On the owner's 224 recordings |
| --- | --- | --- | --- |
| Tamil + English | `whisper-tamil-small` (vasista22, IIT Madras, Apache-2.0), 8-bit ONNX via transformers.js | ~290 MB once | Tamil words 74%, Tanglish 70%, cow names 84% |
| English | Cactus "Whistle" (Apache-2.0), WASM in a worker, told the cows' names | ~18 MB once | about 0.5 s a sentence |
| Others | `onnx-community/whisper-base` (multilingual) | ~80 MB once | Tamil words 40%, cow names 53% (why Tamil gets its own model) |

- Used on iPhones for Tamil and English, in the Home Screen app for every
  language, and wherever the browser's service refuses (`service-not-allowed`,
  `language-not-supported`). Elsewhere the browser's own service is kept.
- The first time, a card offers the download (size shown); files stay in the
  browser's cache, so listening then needs no internet.
- The ear finds speech itself (a noise floor that follows the room), and
  sends each finished sentence; replies are not heard because listening
  pauses while VIMO speaks.
- Tamil models are built and scored by `.github/workflows/voice-model-build.yml`
  and served from the `voice-models` branch (raw.githubusercontent.com allows
  browser downloads; free). If the Tamil model is missing, the multilingual one
  is used.
- Whisper always listens to a 30-second window, so on a phone a Tamil
  sentence takes a few seconds; the screen says "புரிந்துகொள்கிறேன்…"
  meanwhile. The voice report logs the real time per sentence (`lastMs`).
- Not used, after testing: Cactus Needle3 (tool calling) recorded "300
  rupees petrol" as 300 litres of milk and knows no Tamil.
