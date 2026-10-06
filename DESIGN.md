# VIMO interface — Apple Human Interface Guidelines

The interface follows Apple's Human Interface Guidelines (developer.apple.com/design,
reviewed October 2026): foundations (color, Dark Mode, typography, layout, materials,
motion, accessibility), components (tab bars, toolbars, buttons, lists, sheets, alerts,
segmented controls, toggles, text fields, progress indicators) and patterns (feedback,
modality, loading, entering data, gestures). It is built in Flutter and does not use
Apple's proprietary rendering engine; system fonts are not embedded.

## Foundations

- **Color.** `Ink` holds iOS semantic colours in light and dark variants: label,
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
- **Materials.** Content uses solid inset-grouped cells (`Glass`). Liquid Glass
  (`LiquidGlass`: blur, translucency, hairline rim) is reserved for the functional layer:
  the floating tab bar and controls floating over maps. Increase Contrast makes it opaque.
- **Motion.** Pages push with the iPhone slide and support the interactive edge swipe
  back. Lists do not animate in. Reduce Motion replaces slides with fades and removes
  scaling. Press states dim and dip slightly.
- **Accessibility.** 44 pt minimum targets, semantic labels on custom controls,
  selection haptics on tab and segment changes.

## Components

- **Tab bar:** floating capsule, monochrome symbols and one-word labels, tint on the
  selected tab.
- **Navigation bar:** centred 17 pt semibold title, chevron back button without text,
  bar tint when content scrolls under.
- **Buttons:** prominent (tint-filled capsule) for the main action, gray (system fill)
  for secondary actions, plain tinted text, borderless symbol buttons in bars. Busy
  buttons show the activity indicator.
- **Segmented controls:** system-fill track with a sliding tinted thumb.
- **Text fields:** filled rounded fields with the field name inside, tint outline on focus.
- **Alerts:** `AppleAlert` — centred title and message, full-width buttons separated
  by hairlines; bold default action, red destructive action.
- **Sheets:** `showAppleSheet` — rounded top, grabber, swipe to dismiss.
- **Switches** use the iOS style. **Spinners** are the iOS activity indicator.
- **Symbols:** Cupertino (SF Symbols style) icons; domain artwork (cows, milk cycle)
  stays custom.

## Verification

Run `flutter analyze`, `flutter test`, the Firestore emulator checks described in
README, and `flutter build web --release`. Check phone-width screens in light and dark
appearance, with large text and in Tamil.
