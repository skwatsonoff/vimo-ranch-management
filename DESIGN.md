# VIMO interface — Apple Human Interface Guidelines

The interface follows Apple's Human Interface Guidelines (developer.apple.com/design,
reviewed October 2026): foundations (color, Dark Mode, typography, layout, materials,
motion, accessibility), components (tab bars, toolbars, buttons, lists, sheets, alerts,
segmented controls, toggles, text fields, progress indicators) and patterns (feedback,
modality, loading, entering data, gestures). It is built in Flutter and does not use
Apple's proprietary rendering engine; system fonts are not embedded.

## Foundations

- **Tokens.** `lib/design_tokens.dart`: `Space` (4-point grid), `Depth`
  (shadows), `Blur` (glass strengths), `Motion` (springs as damping ratio +
  response, durations, curves). Radii, type ladder and proportions stay on
  the phi ladder in `Gold`.
- **Color.** VIMO Milk palette: royal purple `#5A2CA0` is the tint, deep
  purple `#3B1D5D` display text, orange `#FF7A00` only for today/milk
  highlights, cream `#FFF3E0` warm surfaces, lavender canvas `#F5F2FA`
  (dark `#0D0A12`). `Ink` holds iOS semantic colours in light and dark variants: label,
  secondary and tertiary label, grouped backgrounds (canvas, cell, elevated sheet cell),
  tertiary fill, separator and the system tints (red, orange, green, blue). The brand
  violet is the app tint: `violetDeep` for tinted text and symbols, `tint` for fills
  behind white labels. Text meets 4.5:1 contrast in both appearances.
- **Dark Mode.** The app follows the system appearance (no in-app switch, as Apple
  recommends). `VimoApp` rebuilds every element when the appearance changes. Sheets
  and alerts use elevated surfaces (`ElevatedSurface`) so cells stay distinct in dark.
- **Typography.** Apple text styles on the iOS scale (Large Title 34 … Caption 2 11).
  No text is smaller than 11 pt. Apple platforms use San Francisco; web and Android
  use Inter (SIL OFL, bundled and subset) with SF-like tracking. Dynamic Type scaling
  is respected.
- **Materials.** Content uses solid inset-grouped cells (`Glass`), never glass.
  Liquid Glass (`LiquidGlass`) is reserved for the functional layer: the floating
  tab bar, the floating Add button (the only tinted glass, as the primary action)
  and controls over maps. Its layers: a blurred, saturation-boosted backdrop, a
  translucent fill (`Ink.glass`), a specular rim with an inner lens edge, a soft
  two-part shadow, and, on touch, light that spreads from the finger beneath the
  symbols. Tab pages run edge to edge (`Shell(edgeToEdge: true)`) so content
  scrolls beneath the tab bar and shows through it; their lists pad by the bar
  height the shell reports through `MediaQuery` (`floatingBarClearance`).
  Under the title bar a scroll edge effect dissolves content instead of a
  divider. Sheets (`showAppleSheet`) sit on a thick frosted panel inset from the
  screen edges. Increase Contrast and Reduce Transparency (browsers that report
  it) make every glass surface opaque.
- **What this is not.** Flutter draws all of this itself, on the web and on iOS
  alike. It follows Apple's material guidance but is not the system's native
  Liquid Glass: there is no real lensing (refraction) of the content behind, and
  it does not adapt its tint to the brightness behind it. Native glass would
  need SwiftUI/UIKit views (`glassEffect`, iOS 26 SDK, Xcode 26) embedded as
  platform views on the iOS build only; the production app is the Firebase
  Hosting PWA, where browsers can only approximate the material.
- **Motion.** Pages push with the iPhone slide and support the interactive edge
  swipe back. Tabs switch instantly, as on iOS. The tab bar's selection lens
  moves on an interruptible spring (`glassSpring`), stretches slightly with its
  speed, lifts while held, and can be scrubbed by sliding a finger along the bar
  (with selection haptics). Glass flexes slightly under a finger. Sheets rise on
  a quick settling ease-out and can be dragged away at any point. The Add button
  scales and fades between tabs without Material's spin. Cards fade up from
  97% as they appear, screen blocks settle in with a 40 ms stagger, tabs
  fade and rise into place and the chosen tab symbol springs. Figures count
  to new values. Presses run on springs (snappy in, critically damped out). Reduce Motion removes the spring, stretch, lift and flex (the touch light
  stays), replaces slides with fades and shortens sheets. Press states on
  solid controls dim and dip slightly.
- **Sound.** `UiSound` (`lib/ui_sound.dart`) plays a quiet set from
  `assets/sounds/`: tap (presses, selections), toggle on/off, success,
  error, whoosh (page push/pop), notification. Preloaded, ambient session
  on iOS, sonification on Android, held during voice notes, switch in App
  Settings → Sounds.
- **Accessibility.** 44 pt minimum targets, semantic labels on custom controls,
  selection haptics on tab and segment changes.

## Components

- **Tab bar:** floating Liquid Glass capsule, monochrome symbols and one-word
  labels, tint on the selected tab, spring lens that can be scrubbed.
- **Navigation bar:** centred 17 pt semibold title, chevron back button without text,
  bar tint when content scrolls under.
- **Buttons:** prominent (tint-filled capsule) for the main action, gray (system fill)
  for secondary actions, plain tinted text, borderless symbol buttons in bars. Busy
  buttons show the activity indicator.
- **Segmented controls:** system-fill track with a sliding tinted thumb.
- **Text fields:** filled rounded fields with the field name inside, tint outline on focus.
- **Alerts:** `AppleAlert` — centred title and message, full-width buttons separated
  by hairlines; bold default action, red destructive action.
- **Sheets:** `showAppleSheet` — inset frosted glass panel with continuous
  corners, grabber, swipe to dismiss.
- **Switches** use the iOS style. **Spinners** are the iOS activity indicator.
- **Symbols:** Cupertino (SF Symbols style) icons; domain artwork (cows, milk cycle)
  stays custom.

## Verification

Run `flutter analyze`, `flutter test`, the Firestore emulator checks described in
README, and `flutter build web --release`. Check phone-width screens in light and dark
appearance, with large text and in Tamil.
