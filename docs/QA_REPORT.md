# VIMO — QA report (branch `ui-polish`)

## Environment

- Flutter 3.47.8 (stable, 2026-10-22), Dart 3.13.7, installed inside the
  project at `tmp/flutter` (git-ignored, analyzer-excluded). Linux cloud
  container; no Android/iOS toolchain, so the web build is the one built and
  clicked through (Chromium via Playwright, preview build with demo cows:
  `--dart-define=VIMO_PREVIEW_MODE=true`).

## Results

| Check | Baseline (`main` 852de91) | Now (`ui-polish`) |
| --- | --- | --- |
| `flutter analyze` errors / warnings | 0 / 0 | 0 / 0 |
| `flutter analyze` infos | 13 | 10 (all in files' untouched code or test scripts) |
| `flutter test` | 143 passed | **158 passed**, 0 failed (15 new in `test/polish_test.dart`) |
| `flutter build web --release` | — | passes |
| Browser console errors (Playwright) | 0 | 0 (only `ERR_INTERNET_DISCONNECTED` while deliberately offline) |

## Tested

- **Phone 390×844 and desktop 1440×900, light and dark** (Playwright,
  screenshots in `tmp/qa/after/`): first-run purpose screen → Home → Add
  milk → Save & Next Cow → Save Milk Entry → Home totals → Add Entry
  (Others) → Sell → Cows & Calves (ranking) → Social / Chat / Profile.
- **Offline**: network cut in the browser, milk entry saved, Home updated
  (5 L), back online without errors.
- **Tamil**: Add Entry shows all three choices; Home and the milk card at
  320 pt wide with 1.4–1.6× text (widget tests).
- **Large text / long values**: 1,234.5 L in the milk card at 1.6× text.
- **Reduce Motion**: numbers jump, entrances and pops are skipped (widget
  test for count-up; code paths gated by `Motion.reduced`).
- **Empty / loading / error states**: pregnant cows empty state with action,
  signed-out panels with Sign In, offline panel, skeleton rows.
- **Accessibility**: Home tiles and Add milk are activatable by screen
  reader (semantics `onTap`), snack bars carry a symbol, not colour alone.
- web-design-guidelines pass on the web shell: theme-color matches the new
  canvas, `color-scheme` set, loading label ends with "…".

## Found and fixed

1. Tamil Add Entry hid the "Others" expense choice (only 2 of 3 labels).
2. Signed-out Social / Chat / Profile were dead ends (bare text).
3. Today's milk card overflowed by 85 px in Tamil at 320 pt with large text.
4. Hero card overflowed by 78 px in Tamil on a small phone with large text.
5. Home tiles and the new Add milk button were not activatable by screen
   readers (found while driving the app through its semantics tree).
6. Money fields used a dollar symbol in a rupee app.
7. Dark Mode hero glared (light artwork, lavender wash) and the gold
   birthday pill lost contrast.
8. Desktop Add button sat at the far window edge, away from the content.
9. An existing test tapped the Reports tile off-screen after the new card
   moved it; it now scrolls to it first.

## Still open / not testable here

- **Cloud sync against real Firestore** was not exercised: the preview
  build has no signed-in ranch. Sync code was not changed (pull to refresh
  only calls the existing `AutoSyncService.run(reason: 'manual')`).
- **Native iOS / Android builds** were not built (no toolchains in the
  container). Sound session behaviour (Silent switch, ambient mixing) is
  by configuration and needs a check on a real phone.
- **Frame timing** was not profiled on a device; animations use
  transform/opacity only, one short controller per card, and are disabled
  on low-end devices ("fast" effects mode) and under Reduce Motion.
- **Sounds** were rendered by `tools/render_ui_sounds.py` because the
  earshot toolkit is on the laptop, not in this container. Listen and
  replace if wanted (see `assets/sounds/`).
