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

/// Milk delivery bicycle with two cans, shared by every Vendor surface.
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
    label: bi('Milk delivery cycle', 'பால் விநியோக சைக்கிள்'),
    child: RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MilkCyclePainter(color)),
      ),
    ),
  );
}

class _MilkCyclePainter extends CustomPainter {
  final Color color;
  const _MilkCyclePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    final light = color.computeLuminance() > .6;
    final fill = Paint()..color = color;
    final disc = Paint()..color = color.withValues(alpha: light ? .34 : .26);
    Paint stroke(double width, [Color? tone]) => Paint()
      ..color = tone ?? color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Path path(List<Offset> points) {
      final result = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        result.lineTo(point.dx, point.dy);
      }
      return result;
    }

    for (final x in [15.5, 48.5]) {
      canvas.drawCircle(Offset(x, 46), 11.2, fill);
      canvas.drawCircle(Offset(x, 46), 7.6, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x, 46), 7.6, disc);
      canvas.drawCircle(Offset(x, 46), 2.2, fill);
    }
    final frame = stroke(3.2);
    canvas.drawPath(
      path(const [
        Offset(15.5, 46),
        Offset(30, 46),
        Offset(25.5, 30),
        Offset(15.5, 46),
      ]),
      frame,
    );
    canvas.drawPath(
      path(const [Offset(25.5, 30), Offset(43, 28.5), Offset(30, 46)]),
      frame,
    );
    canvas.drawLine(const Offset(43, 28.5), const Offset(48.5, 46), frame);
    canvas.drawLine(const Offset(43, 28.5), const Offset(42, 22.5), stroke(3));
    canvas.drawLine(
      const Offset(38.5, 21.5),
      const Offset(46.5, 21),
      stroke(3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(20, 25.8, 11, 4.2),
        const Radius.circular(2.1),
      ),
      fill,
    );
    canvas.drawLine(
      const Offset(5.5, 31.5),
      const Offset(27, 31.5),
      stroke(2.8),
    );
    canvas.drawLine(const Offset(9, 31.5), const Offset(15.5, 46), stroke(2.2));
    final band = stroke(1.5, light ? Ink.violetDeep : Colors.white);
    for (final x in [6.2, 16.2]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 14, 9.2, 17.5),
          const Radius.circular(3),
        ),
        fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2.1, 10.8, 5, 3.8),
          const Radius.circular(1.4),
        ),
        fill,
      );
      canvas.drawLine(Offset(x + 2.2, 20.5), Offset(x + 7, 20.5), band);
      canvas.drawLine(Offset(x + 2.2, 25), Offset(x + 7, 25), band);
    }
    canvas.drawLine(
      const Offset(4.8, 24.5),
      const Offset(26.8, 21.8),
      stroke(1.7, const Color(0xFFC9A36A)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MilkCyclePainter old) => old.color != color;
}

final Map<String, ImageProvider> _photoCache = {};

/// Stable providers stop avatars flickering when a parent rebuilds.
ImageProvider? cachedPhoto(String data) {
  if (data.isEmpty) return null;
  if (data.startsWith('http://') || data.startsWith('https://')) {
    return NetworkImage(data);
  }
  final cached = _photoCache[data];
  if (cached != null) return cached;
  final bytes = socialPhotoBytes(data);
  if (bytes.isEmpty) return null;
  if (_photoCache.length > 80) _photoCache.remove(_photoCache.keys.first);
  return _photoCache[data] = MemoryImage(bytes);
}

ImageProvider? personPhoto(Map<String, dynamic> person) => cachedPhoto(
  txt(person, 'imageData').isNotEmpty
      ? txt(person, 'imageData')
      : txt(person, 'photo', txt(person, 'imageUrl')),
);

String _initial(String label) {
  final value = label.trim();
  return value.isEmpty ? '' : value.characters.first.toUpperCase();
}

/// Apple-style glass avatar: photo inside a luminous rim with soft depth.
class GlassAvatar extends StatelessWidget {
  final ImageProvider? image;
  final String label;
  final double radius;
  final bool halo;
  const GlassAvatar({
    super.key,
    this.image,
    this.label = '',
    this.radius = 22,
    this.halo = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final rim = math.max(2.0, radius * .08);
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1EBFF), Color(0xFFDCD2FF)],
        ),
      ),
      child: Center(
        child: _initial(label).isEmpty
            ? Icon(
                CupertinoIcons.person_fill,
                size: radius,
                color: Ink.violetDeep,
              )
            : Text(
                _initial(label),
                style: TextStyle(
                  fontSize: radius * .82,
                  fontWeight: FontWeight.w700,
                  color: Ink.violetDeep,
                ),
              ),
      ),
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(rim),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: halo
              ? const [Color(0xFF9D7BFF), Ink.violetDeep, Color(0xFF6F8BFF)]
              : [
                  Colors.white,
                  Colors.white.withValues(alpha: .55),
                  Colors.white.withValues(alpha: .9),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4526B8).withValues(alpha: .16),
            blurRadius: radius * .6,
            offset: Offset(0, radius * .2),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(halo ? rim * .6 : 0),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image == null)
                fallback
              else
                Image(
                  image: image!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => fallback,
                ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-.55, -.75),
                      radius: .95,
                      colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Large portrait with a frosted lower edge carrying the name (image-5 style).
class GlassPortrait extends StatelessWidget {
  final ImageProvider? image;
  final String title, subtitle;
  final double size;
  const GlassPortrait({
    super.key,
    this.image,
    required this.title,
    this.subtitle = '',
    this.size = 190,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = image != null;
    Widget photo() => Image(
      image: image!,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => const ColoredBox(color: Ink.lavender),
    );
    return Semantics(
      label: title,
      image: hasPhoto,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF2C13D).withValues(alpha: .20),
              blurRadius: size * .22,
              offset: Offset(0, size * .12),
            ),
            BoxShadow(
              color: const Color(0xFF4526B8).withValues(alpha: .14),
              blurRadius: size * .16,
              offset: Offset(0, size * .05),
            ),
          ],
        ),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPhoto)
                photo()
              else
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFEDE6FF), Color(0xFFCFC2FF)],
                    ),
                  ),
                ),
              if (hasPhoto)
                IgnorePointer(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.transparent, Colors.black],
                      stops: [0, .5, .76],
                    ).createShader(rect),
                    child: ImageFiltered(
                      imageFilter: dart_ui.ImageFilter.blur(
                        sigmaX: size * .07,
                        sigmaY: size * .07,
                      ),
                      child: photo(),
                    ),
                  ),
                ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: hasPhoto
                          ? const [
                              Color(0x00FFFFFF),
                              Color(0x14FFF3E0),
                              Color(0x59FFF1D6),
                            ]
                          : const [
                              Color(0x00FFFFFF),
                              Color(0x14FFFFFF),
                              Color(0x33FFFFFF),
                            ],
                      stops: const [.45, .7, 1],
                    ),
                  ),
                ),
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-.6, -.8),
                      radius: .9,
                      colors: [Color(0x4DFFFFFF), Color(0x00FFFFFF)],
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .8),
                      width: math.max(2, size * .012),
                    ),
                  ),
                ),
              ),
              if (!hasPhoto)
                Align(
                  alignment: const Alignment(0, -.2),
                  child: Text(
                    _initial(title),
                    style: TextStyle(
                      fontSize: size * .34,
                      fontWeight: FontWeight.w700,
                      color: Ink.violetDeep,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    size * .14,
                    0,
                    size * .14,
                    size * .15,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: size * .105,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.3,
                          color: hasPhoto ? Colors.white : Ink.navy,
                          shadows: hasPhoto
                              ? const [
                                  Shadow(
                                    color: Color(0x66000000),
                                    blurRadius: 12,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: size * .066,
                            fontWeight: FontWeight.w600,
                            color: hasPhoto
                                ? const Color(0xFFFFE9A8)
                                : Ink.violetDeep,
                            shadows: hasPhoto
                                ? const [
                                    Shadow(
                                      color: Color(0x59000000),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The VIMO signature wordmark from the reference design.
class VimoScript extends StatelessWidget {
  final double size;
  final Color color;
  const VimoScript({super.key, this.size = 52, this.color = Ink.violetDark});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Text(
      'Vimo',
      style: TextStyle(
        fontFamily: 'Parisienne',
        fontSize: size,
        height: 1,
        color: color.withValues(alpha: .82),
      ),
    ),
  );
}
