# VIMO — UI audit (Phase 1)

Reviewed on 2026-10-25 from the code on `main` (852de91) and a release web
build in preview mode (`VIMO_PREVIEW_MODE=true`, demo cows), at 390×844
(phone) and 1440×900 (desktop), light and dark. Lenses: apple-look (Apple
HIG, cited as `file.md › Heading`), apple-motion, design-taste-frontend (app
screen rules) and awesome-design-md `apple.md` (spacing, type, depth).

## Summary

**Rating: Good.** The app already has a real design system (`Gold` phi
ladder, `Ink` semantic colours, squircles, Liquid Glass only on the tab bar,
Add button and sheets, Reduce Motion / Increase Contrast fallbacks, 44 pt
targets). Its thesis is "the ranch's day in one place", and what people will
remember is the ranked cows (gold / purple / green) and the hand-drawn ranch
hero. The gaps are: the home screen does not answer the dairy's first
question (how much milk today), the brand colour is a generic electric
violet instead of the VIMO Milk purples, several states give no way forward,
and the frequent daily flows (milk entry) take more taps than they need.

Severity tags: **Critical** (accessibility / blocks people), **High**
(friction, readability, off-brand), **Medium**, **Low**.

---

## Critical

1. **Tamil users cannot add an "Others" expense from Add Entry.**
   - *What:* `AddEntryScreen` passes 3 English segment labels (Milk, Stock
     Use, Others) but only 2 Tamil labels/icons, so in Tamil the expense
     form (mode 2) is unreachable.
   - *Why:* an existing option disappears depending on language
     (`writing.md` — one function, same name everywhere; and the brief: never
     remove an option).
   - *Fix:* add the third Tamil label (`மற்றவை`) and icon so both languages
     show all three modes.

2. **Signed-out / expired-session states are dead ends.**
   - *What:* Social shows "Sign in to connect with the community." and
     Profile / Chat show "Please sign in again" as bare centred text with no
     button.
   - *Why:* `feedback.md`: feedback should be actionable; `loading.md`:
     never make people wonder what to do. design-taste app rules: every
     empty or error state names the next action.
   - *Fix:* one shared `StatePanel` (icon, title, message, prominent action)
     with a **Sign in** button that returns to the sign-in screen.

## Improvements

3. **High — Home has no milk figure.**
   - *What:* the dashboard shows counts (cows, sales, calves, stock,
     pregnant, month result) but not litres collected today, the number a
     dairy checks first.
   - *Why:* `design-principles.md › Purpose`; design-taste app rules: "the
     screen's one question is answered by its biggest block".
   - *Fix:* a "Today's milk" card under the hero: litres today counted up
     on change, morning / afternoon / evening split, sold and still
     available, tap opens Milk Details; a one-tap "Add milk" action inside.

4. **High — Brand colour is a generic violet.**
   - *What:* tint `#5B2EE0` / `#7C4DFF` and a neutral iOS grey canvas
     `#F2F2F7`; nothing ties the app to the VIMO Milk palette (deep purple
     `#3B1D5D`, royal purple `#5A2CA0`, orange `#FF7A00`, warm cream
     `#FFF3E0`).
   - *Why:* `branding.md`: express identity through colour, keep it on
     primary actions and status; `color.md`: one colour, one meaning.
   - *Fix:* tint → royal purple `#5A2CA0` (white on it 8.9:1; as text on the
     canvas 8.2:1), deep purple `#3B1D5D` for display text and the hero
     wash, soft lavender canvas `#F5F2FA` (light) and purple-black
     `#0D0A12` (dark), orange `#FF7A00` reserved for one meaning: *today /
     milk* highlights (never body text: 2.6:1 on white, so its text tone is
     `#B35300`, 5.0:1), cream `#FFF3E0` for warm notices.

5. **High — Desktop layout floats the Add button far from the content.**
   - *What:* at 1440 px the content column is 432 px wide in the centre but
     the Add button sits at the window's right edge, ~500 px away.
   - *Why:* `layout.md`: keep controls near the content they affect;
     design-taste app rules: one frame, controls belong to it.
   - *Fix:* on wide windows, anchor the floating Add button to the content
     column's trailing edge.

6. **High — Birthday hero glares in Dark Mode.**
   - *What:* the lavender line-art hero stays light in dark appearance (a
     large near-white panel on black); the "Happy Birthday!" pill text sits
     on pale yellow at low contrast.
   - *Why:* `dark-mode.md`: soften whites, avoid abrupt brightness;
     apple-motion §14: avoid abrupt brightness jumps.
   - *Fix:* dim the artwork in dark mode (darken + desaturate overlay) and
     use dark ink on the gold pill.

7. **High — Daily milk entry takes too many taps.**
   - *What:* every entry starts at "Morning" whatever the time; after Save
     the page closes, so logging 10 cows is 10 × (Add → Milk → pick cow →
     type → Save); there is no confirmation of what was saved.
   - *Why:* `entering-data.md`: prefill sensible defaults, offer choices
     over typing; `feedback.md`: confirm completion in the interface.
   - *Fix:* session defaults from the clock; the cow's last quantity for
     that session offered as a one-tap chip; **Save & next cow** moves to
     the next cow without leaving; a success snack with the litres and the
     cow; success sound + haptic.

8. **Medium — Stat tiles spend half their height on decoration.**
   - *What:* each tile is 142 pt for one number: a 44 pt icon in a tinted
     square, a 7% watermark illustration, then label and value.
   - *Why:* design-taste app rules ban "icons in tinted squares" as a
     template tell; `layout.md` › visual hierarchy.
   - *Fix:* keep the tiles (people know them) but tighten: smaller symbol
     without the tinted plate shadow, value at Title 1 size, tiles 124 pt.

9. **Medium — Headline weights and tracking are inconsistent.**
   - *What:* 36 places use w800/w900; headings mix w700 and w800.
   - *Why:* `apple.md` (awesome-design-md): headlines at 600–700, tracking
     tightens as size grows; `typography.md` › Best practices.
   - *Fix:* theme text styles own weight/tracking; display numbers w700
     with -0.8 tracking; no w900 in UI text.

10. **Medium — Loading states are spinners or blank.**
    - *What:* Social/Chat/market lists show nothing or a spinner while
      Firestore answers.
    - *Why:* `loading.md` › Best practices: "Show something as soon as
      possible … placeholder text, graphics, or animations".
    - *Fix:* a `Shimmer` skeleton widget for list loading (static under
      Reduce Motion).

11. **Medium — Press feedback uses fixed easing; release is not a spring.**
    - *What:* `Pressable` dims instantly but scales back on a 160 ms
      ease-out.
    - *Why:* apple-motion §1, §4: respond on pointer-down, release on a
      critically damped spring that can be interrupted.
    - *Fix:* drive press scale with a `SpringSimulation` (damping 1.0,
      response ~0.3 s) from the current value.

12. **Medium — Numbers snap or slide instead of counting.**
    - *What:* `FlowText` slides a new value in; milk totals jump.
    - *Fix:* `CountUpText` for litres and money (critically damped tween
      from the previous value, instant under Reduce Motion).

13. **Medium — No pull to refresh on Home.**
    - *What:* sync status is only visible in the hero chip; there is no
      gesture to ask for a sync.
    - *Fix:* `RefreshIndicator.adaptive` on Home that triggers
      `AutoSyncService` sync and reports the result.

14. **Medium — Empty states do not offer the next step.**
    - *What:* "No pregnant cows — Record a pregnancy injection from a cow
      profile…" with no button; message 13 pt grey, centred.
    - *Why:* `writing.md`: empty screens invite the next action.
    - *Fix:* `EmptyNote` gains an optional action button.

15. **Medium — No UI sounds; feedback is visual + occasional haptic.**
    - *Why:* `motion.md` › Best practices: "supplement visual feedback by
      also using alternatives like haptics and audio"; apple-motion §13
      (causality, harmony, utility).
    - *Fix:* a quiet sound set for tap, toggle, success, error, page
      transition and notification, preloaded, with a Settings switch.

16. **Low — Reduce Transparency only follows the browser on the web.**
    - *What:* native builds fall back to opaque glass only under Increase
      Contrast; low-end devices still blur.
    - *Why:* `liquid-glass.md › Flutter`: "treat high contrast as the cue to
      fall back to opaque surfaces, or offer an in-app setting".
    - *Fix:* opaque glass also when `DevicePerformance` reports a low-end
      device; an in-app "Reduce transparency" switch in Settings.

17. **Low — Snack bar is a fixed 3.2 s, no action.**
    - *Fix:* optional action (e.g. "Edit" after a save) and a longer time
      when it carries an action; haptic on error.

## Craft notes

- **Point of view (keep):** the ranked cow cards (gold, purple, green
  textures with rosettes), the line-art ranch hero and the milk-cycle
  vendor icon are specific to this product. They are the signature; new
  work stays quiet around them.
- **Remove one accessory:** the 7% watermark illustrations on stat tiles
  add noise without meaning — reduce, keep the tile clean.
- **Glass vs. content:** the brief asks for frosted cards. Apple's rule
  (`liquid-glass.md › Where the material belongs`) keeps glass off content,
  and blurring every list card would cost frames on low-end phones. The
  resolution: the lavender canvas gives cards a soft frosted-white feel
  (solid, 100% legible), real glass stays on the floating layer (tab bar,
  Add button, sheets, alerts) where it carries meaning.

## What works (keep)

- Liquid Glass only in the functional layer, with specular rim, touch light,
  interruptible spring lens on the tab bar, scrubbing with selection
  haptics.
- iOS push transitions with edge swipe back; cross-fade under Reduce Motion.
- Semantic `Ink` colours for light and dark with 4.5:1 text tones.
- 44 pt minimum targets via `liquidActionStyle` / `plainIconStyle`.
- Smart auto-fill already present: last milk quantity per customer on Sell,
  expense names by frequency (`frequentNameSuggestions`).
- Confirmation only on irreversible actions (death record, restore backup).

## Platform notes

- Flutter has no native Reduce Transparency signal on iOS/Android; the web
  build reads `prefers-reduced-transparency`. An in-app switch closes the
  gap.
- Sounds: on iOS the `ambient` audio session respects the silent switch; on
  Android the `sonification` usage follows the system sound settings; the
  web plays only after the first user gesture.
