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

/// Original vector symbol: Indian step-through delivery moped, rear rack,
/// paired aluminium milk cans and securing strap. Crisp at tab-bar sizes.
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
    label: bi(
      'Milk delivery moped with cans',
      'பால் கேன்களுடன் பால் விநியோக மொபெட்',
    ),
    image: true,
    child: RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MilkMopedPainter(color, detailed)),
      ),
    ),
  );
}

class _MilkMopedPainter extends CustomPainter {
  final Color color;
  final bool detailed;
  const _MilkMopedPainter(this.color, this.detailed);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    for (final x in [15.0, 51.0]) {
      canvas.drawCircle(Offset(x, 48), 9, line);
      canvas.drawCircle(Offset(x, 48), 2, fill);
      if (detailed) {
        canvas.drawCircle(
          Offset(x, 48),
          5.8,
          Paint()
            ..color = color.withValues(alpha: .28)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
    canvas.drawPath(
      Path()
        ..moveTo(15, 48)
        ..lineTo(27, 35)
        ..lineTo(33, 46)
        ..lineTo(43, 46)
        ..lineTo(44, 28),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(43, 24)
        ..lineTo(51, 48)
        ..moveTo(43, 24)
        ..lineTo(40, 19)
        ..lineTo(46, 19),
      line,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(23, 29, 15, 4),
        const Radius.circular(2),
      ),
      fill,
    );
    canvas.drawLine(const Offset(29, 33), const Offset(27, 39), line);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(27, 43, 9, 5),
        const Radius.circular(2),
      ),
      fill,
    );
    canvas.drawLine(const Offset(35, 49), const Offset(41, 49), line);
    canvas.drawLine(const Offset(5, 36), const Offset(25, 36), line);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(44, 23, 6, 4),
        const Radius.circular(1),
      ),
      fill,
    );
    for (final x in [6.0, 17.0]) {
      final can = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 19, 9, 15),
        const Radius.circular(2),
      );
      canvas.drawRRect(
        can,
        Paint()
          ..shader = LinearGradient(
            colors: detailed
                ? [
                    Colors.white,
                    const Color(0xFFDCE4ED),
                    Colors.white,
                    const Color(0xFFBCC8D5),
                  ]
                : [color.withValues(alpha: .13), color.withValues(alpha: .04)],
          ).createShader(can.outerRect),
      );
      canvas.drawRRect(can, line..strokeWidth = 1.9);
      canvas.drawLine(Offset(x + 1, 18), Offset(x + 8, 18), line);
      canvas.drawLine(Offset(x + 3, 15.5), Offset(x + 6, 15.5), line);
      canvas.drawLine(
        Offset(x + 2, 25),
        Offset(x + 7, 25),
        line..strokeWidth = 1.2,
      );
    }
    canvas.drawLine(
      const Offset(5, 29),
      const Offset(27, 32),
      Paint()
        ..color = detailed ? const Color(0xFFB48852) : color
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MilkMopedPainter old) =>
      old.color != color || old.detailed != detailed;
}
