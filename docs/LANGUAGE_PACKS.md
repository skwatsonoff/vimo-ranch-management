# VIMO language packs and offline voice

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

`language_packs/manifest.json` in Firebase Storage (public read, no client
writes). The cloud training workflow writes it with
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
      "url": "https://firebasestorage.googleapis.com/v0/b/my-ranch-sync.firebasestorage.app/o/language_packs%2Fasr-ta-3.tar.bz2?alt=media",
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

None at the moment; see the Phase 5 notes in `VIMO_MASTER_HANDOFF.md`.
