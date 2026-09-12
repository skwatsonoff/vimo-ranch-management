# VIMO glass interface

The interface uses an original Flutter glass treatment informed by Apple's
Liquid Glass guidance. It is not Apple's native rendering engine and does not
use Apple's proprietary refraction shaders or redistributed SF fonts.

## References reviewed

- [Meet Liquid Glass, WWDC25](https://developer.apple.com/videos/play/wwdc2025/219/):
  transcript sections on material layers, highlights, controls, hierarchy and accessibility.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
  and [Motion](https://developer.apple.com/design/human-interface-guidelines/motion).
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
  and [UI Design Dos and Don'ts](https://developer.apple.com/design/tips/).
- [iPadOS 26 feature guide, PDF](https://www.apple.com/nz/os/pdf/All_New_Features_iPadOS_26_Sept_2025_NZ_Final.pdf):
  design, controls and navigation section, page 2.

## Applied throughout the app

- Neutral, subtly colored canvas; restrained violet accents; charcoal text.
- Continuous corners, translucent fills, a directional outer rim, an inner
  reflected edge and soft shadows shared by cards, grouped lists and navigation.
- Buttons use the same material and touch feedback; fields have a painted
  translucent gradient and a visible focus outline. Field overlays don't add
  another full-screen blur pass inside every form.
- Settings groups, vendor/customer lists, social posts, task cards and the chat
  composer use the shared surface instead of flat white containers.
- Clear typography with fewer heavy weights. Existing photos remain unobscured.
- Short, cubic navigation transitions, keyboard-focusable bottom navigation,
  44-pixel action targets and English/Tamil text scaling.
- System reduced-motion settings stop the ambient animation and remove press
  scaling, sliding segment animations and staggered reveal motion. High contrast
  increases glass opacity and removes backdrop blur.
- The vendor pictogram is an original vector of an Indian step-through moped
  carrying two aluminium milk cans secured to its rack. The same geometry is
  used in navigation, purpose selection and the vendor stock overview.

## Verification

Run `flutter analyze lib test`, `flutter test`, then the Firestore emulator tests
described in README. Inspect preview screenshots on a phone viewport and desktop,
including Tamil settings, customer schedules, sales, reports and the social composer.
Only `build/web` from a release build without preview flags may be deployed.
