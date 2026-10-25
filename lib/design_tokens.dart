part of 'main.dart';

// =============================================================================
//  Design tokens: spacing, depth, glass blur and motion.
//
//  Colours live in [Ink]; corner radii, the type ladder and the golden-ratio
//  proportions (hero aspect, content column, sheen height) live in [Gold].
//  Everything here is the shared vocabulary new and polished screens use.
// =============================================================================

/// Spacing on the 4-point grid (8-point for anything larger than 16).
///
/// The earlier Fibonacci spacing steps (3, 5, 13, 21, 34, 55, 89) were each
/// within a point or two of a grid value and now resolve to it, so every gap
/// in the app lines up on one rhythm.
class Space {
  const Space._();

  static const double s2 = 2;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s56 = 56;
  static const double s88 = 88;

  /// Side margin of a phone screen's content (Apple's compact layout margin).
  static const double gutter = s20;

  /// Minimum interactive size (Apple: 44 × 44 pt).
  static const double target = 44;
}

/// Soft shadows for things that float. Content at rest has no shadow on the
/// light canvas beyond [card]'s barely-there lift; dark mode uses surface
/// tone steps instead, so these fade out there.
class Depth {
  const Depth._();

  /// A resting card on the lavender canvas: a wide, faint purple-grey lift.
  static List<BoxShadow> get card => Ink.dark
      ? const []
      : [
          BoxShadow(
            color: const Color(0xFF3B1D5D).withValues(alpha: .05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ];

  /// Floating chrome (Add button, menus): key + ambient shadow.
  static List<BoxShadow> get float => [
    BoxShadow(
      color: Colors.black.withValues(alpha: Ink.dark ? .40 : .10),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: Ink.dark ? .30 : .06),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];
}

/// Backdrop blur strengths for the functional glass layer.
class Blur {
  const Blur._();

  /// Small controls over content (chips, map buttons).
  static const double thin = 8;

  /// The regular Liquid Glass variant (tab bar, Add button).
  static const double regular = 14;

  /// Thick, frosted panels that hold text (sheets, alerts).
  static const double thick = 28;
}

/// Motion tokens. Physical motion uses springs described the way Apple does:
/// a damping ratio (1.0 = no overshoot) and a response in seconds (how
/// quickly the value gets there; not a duration). Springs start from the
/// current value and velocity, so every animation can be interrupted.
class Motion {
  const Motion._();

  /// Builds a spring from Apple's two designer parameters.
  static SpringDescription spring({
    double response = .35,
    double damping = 1.0,
  }) {
    final stiffness = math.pow(2 * math.pi / response, 2).toDouble();
    return SpringDescription(
      mass: 1,
      stiffness: stiffness,
      damping: 4 * math.pi * damping / response,
    );
  }

  /// The house spring: critically damped, settles without overshoot.
  static final SpringDescription standard = spring(response: .35);

  /// Snappy release for press states and small controls.
  static final SpringDescription snappy = spring(response: .25);

  /// A little bounce, only after a gesture that carried momentum (a flick,
  /// a drag release).
  static final SpringDescription momentum = spring(response: .4, damping: .8);

  // Durations for non-physical changes (fades, colour, cross-fades).
  static const Duration instant = Duration.zero;
  static const Duration quick = Duration(milliseconds: 120);
  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration countUp = Duration(milliseconds: 700);

  /// Ease-out that mirrors a critically damped spring for tweens.
  static const Curve settle = Cubic(.2, .9, .25, 1);
  static const Curve exit = Cubic(.4, 0, 1, 1);

  /// True when the person asked for less motion (system Reduce Motion, or
  /// the browser's prefers-reduced-motion).
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
