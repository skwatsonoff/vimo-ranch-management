part of 'main.dart';

/// The standard outline painter keeps the field fill behind editable content.
/// InputDecoration owns the fill, avoiding a second painted overlay.
class GlassInputBorder extends OutlineInputBorder {
  const GlassInputBorder({
    super.borderSide = const BorderSide(color: Color(0xCFFFFFFF)),
    super.borderRadius = const BorderRadius.all(Radius.circular(20)),
    super.gapPadding = 5,
  });

  @override
  GlassInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) => GlassInputBorder(
    borderSide: borderSide ?? this.borderSide,
    borderRadius: borderRadius ?? this.borderRadius,
    gapPadding: gapPadding ?? this.gapPadding,
  );

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
  }
}

Widget _glassButtonLayer(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child, {
  bool primary = false,
}) {
  final disabled = states.contains(WidgetState.disabled);
  final pressed = states.contains(WidgetState.pressed);
  final highContrast = MediaQuery.highContrastOf(context);
  return AnimatedScale(
    scale: pressed && !MediaQuery.disableAnimationsOf(context) ? .98 : 1,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160),
    curve: Curves.easeOutCubic,
    child: Glass(
      tint: primary ? Ink.violetDeep : null,
      radius: 24,
      blur: highContrast ? 0 : 12,
      elevation: disabled ? .15 : .45,
      specular: primary ? .7 : 1.1,
      padding: EdgeInsets.zero,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: primary
            ? [
                disabled ? const Color(0xFF9793B2) : const Color(0xFF8266EE),
                disabled ? const Color(0xFF89869F) : Ink.violetDeep,
              ]
            : [
                Colors.white.withValues(
                  alpha: highContrast
                      ? .98
                      : pressed
                      ? .85
                      : .65,
                ),
                Colors.white.withValues(alpha: highContrast ? .95 : .22),
              ],
      ),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

ButtonStyle liquidActionStyle({bool primary = false}) => ButtonStyle(
  backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  shadowColor: const WidgetStatePropertyAll(Colors.transparent),
  foregroundColor: WidgetStatePropertyAll(
    primary ? Colors.white : Ink.violetDeep,
  ),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  elevation: const WidgetStatePropertyAll(0),
  minimumSize: const WidgetStatePropertyAll(Size(44, 48)),
  shape: const WidgetStatePropertyAll(SquircleBorder(radius: 24)),
  side: const WidgetStatePropertyAll(BorderSide.none),
  textStyle: const WidgetStatePropertyAll(
    TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -.15),
  ),
  backgroundBuilder: (context, states, child) =>
      _glassButtonLayer(context, states, child, primary: primary),
);

/// Milk bottle shared by the vendor tab and milk balance.
class MilkVendorIcon extends StatelessWidget {
  final double size;
  final Color color;
  final bool detailed;
  const MilkVendorIcon({
    super.key,
    this.size = 30,
    this.color = Ink.violetDeep,
    this.detailed = false,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: bi('Milk', 'பால்'),
    child: RanchIcon(type: 'milk', size: size, color: color, weight: 2.7),
  );
}
