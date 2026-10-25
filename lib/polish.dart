part of 'main.dart';

// =============================================================================
//  Shared polish widgets: counting numbers, state panels, skeletons and the
//  Home "Today's milk" card.
// =============================================================================

/// A number that counts from the value it showed to the new one, so a total
/// that grows (a milk entry saved, a sync arriving) reads as a change rather
/// than a jump. It starts from what is on screen, so a second change mid-way
/// carries on from there. Reduce Motion shows the new value at once.
class CountUpText extends StatefulWidget {
  final double value;
  final String Function(double value) format;
  final TextStyle? style;
  final TextAlign? textAlign;

  const CountUpText({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.textAlign,
  });

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.countUp,
  )..addListener(() => setState(() {}));
  late double _from = widget.value;
  late double _to = widget.value;

  double get _shown =>
      _from + (_to - _from) * Motion.settle.transform(_controller.value);

  @override
  void didUpdateWidget(CountUpText old) {
    super.didUpdateWidget(old);
    if (widget.value == _to) return;
    _from = _controller.isAnimating ? _shown : _to;
    _to = widget.value;
    if (Motion.reduced(context)) {
      _from = _to;
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = (widget.style ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Text(
      widget.format(_controller.isAnimating ? _shown : _to),
      style: style,
      textAlign: widget.textAlign,
      maxLines: 1,
      // Screen readers hear the final value, never the in-between ones.
      semanticsLabel: widget.format(_to),
    );
  }
}

/// A full state for a screen or a section that has nothing to show yet, or
/// cannot show it: a symbol, a title, one sentence and the action that moves
/// people forward. Used for signed-out, error and empty states.
class StatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final Color? accent;

  const StatePanel({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tone = accent ?? Ink.violetDeep;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s32,
          vertical: Space.s24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: ShapeDecoration(
                    shape: const SquircleBorder(radius: Gold.r21),
                    color: Ink.lavender,
                  ),
                  child: Icon(icon, size: 30, color: tone),
                ),
              ),
              const SizedBox(height: Space.s16),
              Semantics(
                header: true,
                child: AppText(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.3,
                    color: Ink.navy,
                  ),
                ),
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: Space.s8),
                AppText(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.4, color: Ink.muted),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: Space.s24),
                LiquidButton(
                  label: actionLabel!,
                  icon: actionIcon,
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Signed out, or the session expired: say so and offer the way back in.
/// Signing out returns the app to [AuthGate]'s sign-in screen. When the app
/// started without its cloud connection (offline launch), there is nothing
/// to sign in to yet, so it says that instead and reassures that ranch
/// records keep working.
class SignInStatePanel extends StatelessWidget {
  final String message;
  const SignInStatePanel({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    if (!firebaseReady) {
      return StatePanel(
        icon: CupertinoIcons.wifi_slash,
        title: bi('You are offline', 'இணைய இணைப்பு இல்லை'),
        message: bi(
          'This needs an internet connection. Your ranch records keep '
              'working offline and sync when you are back.',
          'இதற்கு இணைய இணைப்பு தேவை. தொழுவப் பதிவுகள் இணையமின்றியும் '
              'செயல்படும்; இணைப்பு வந்ததும் ஒத்திசைக்கப்படும்.',
        ),
      );
    }
    return StatePanel(
      icon: CupertinoIcons.person_crop_circle_badge_exclam,
      title: bi('Please sign in', 'உள்நுழையவும்'),
      message: message,
      actionLabel: bi('Sign In', 'உள்நுழை'),
      actionIcon: CupertinoIcons.arrow_right_circle,
      onAction: () async {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
      },
    );
  }
}

/// Placeholder rows while a list loads: soft blocks the shape of the rows to
/// come, with a slow light sweep. Reduce Motion keeps the blocks still.
class SkeletonList extends StatefulWidget {
  final int rows;
  final EdgeInsetsGeometry padding;
  const SkeletonList({
    super.key,
    this.rows = 6,
    this.padding = const EdgeInsets.all(Space.s20),
  });

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  Widget _block(double width, double height, {double radius = 6}) => Container(
    width: width,
    height: height,
    decoration: ShapeDecoration(
      shape: SquircleBorder(radius: radius),
      color: Ink.fill,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: bi('Loading', 'ஏற்றுகிறது'),
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _sweep,
            builder: (context, child) => ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) {
                final t = _sweep.value * 2 - .5;
                return LinearGradient(
                  begin: Alignment(-1 + t * 2, 0),
                  end: Alignment(t * 2, 0),
                  colors: [
                    Colors.transparent,
                    Ink.surface.withValues(alpha: Ink.dark ? .10 : .55),
                    Colors.transparent,
                  ],
                ).createShader(rect);
              },
              child: child,
            ),
            child: ListView.separated(
              padding: widget.padding,
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: widget.rows,
              separatorBuilder: (_, _) => const SizedBox(height: Space.s12),
              itemBuilder: (_, i) => Glass(
                radius: Gold.r21,
                padding: const EdgeInsets.all(Space.s16),
                child: Row(
                  children: [
                    _block(44, 44, radius: 22),
                    const SizedBox(width: Space.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _block(i.isEven ? 140 : 180, 14),
                          const SizedBox(height: Space.s8),
                          _block(i.isEven ? 200 : 120, 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Litres for display: whole numbers without a decimal, otherwise one place.
String formatLitres(double value) {
  final rounded = (value * 10).round() / 10;
  final text = rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
  return '$text L';
}

String _litres(double value) => formatLitres(value);

/// The milking session a new entry most likely belongs to, from the clock:
/// before 11:00 morning, before 16:00 afternoon, otherwise evening.
String milkSessionForTime(DateTime time) => time.hour < 11
    ? 'Morning'
    : time.hour < 16
    ? 'Afternoon'
    : 'Evening';

double _milkFor(String date, {String? session}) {
  double total = 0;
  for (final r in milkRows()) {
    if (txt(r, 'date') != date) continue;
    if (session != null && txt(r, 'session', 'Morning') != session) continue;
    total += numv(r, 'quantity');
  }
  return total;
}

/// Litres already recorded for [cow] in [session] on [date].
double milkRecordedFor(String cow, String session, String date) {
  double total = 0;
  for (final r in milkRows()) {
    if (txt(r, 'cow') == cow &&
        txt(r, 'date') == date &&
        txt(r, 'session', 'Morning') == session) {
      total += numv(r, 'quantity');
    }
  }
  return total;
}

/// The amount of the most recent "Others" expense called [name].
double? lastExpenseAmountFor(String name) {
  final wanted = name.trim().toLowerCase();
  Map<String, dynamic>? latest;
  for (final r in expenseRows()) {
    if (txt(r, 'name').trim().toLowerCase() != wanted) continue;
    if (latest == null || activityDate(r).isAfter(activityDate(latest))) {
      latest = r;
    }
  }
  if (latest == null) return null;
  final amount = numv(latest, 'amount');
  return amount > 0 ? amount : null;
}

/// The quantity of [cow]'s most recent entry for [session], if any.
double? lastMilkQuantityFor(String cow, String session) {
  Map<String, dynamic>? latest;
  for (final r in milkRows()) {
    if (txt(r, 'cow') != cow || txt(r, 'session', 'Morning') != session) {
      continue;
    }
    if (latest == null || activityDate(r).isAfter(activityDate(latest))) {
      latest = r;
    }
  }
  if (latest == null) return null;
  final quantity = numv(latest, 'quantity');
  return quantity > 0 ? quantity : null;
}

/// Home's answer to a dairy's first question: how much milk today. Litres
/// count up as entries arrive, split by milking session, with sold and still
/// available beside it and yesterday as the baseline. "Add milk" is the most
/// frequent job on the ranch, so it sits on the card.
class TodayMilkCard extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  const TodayMilkCard({super.key, required this.onOpen, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final today = todayDate();
    final now = DateTime.now();
    final y = now.subtract(const Duration(days: 1));
    final yesterday = '${y.year}-${two(y.month)}-${two(y.day)}';
    final total = _milkFor(today);
    final previous = _milkFor(yesterday);
    final sold = milkSold('Today') + milkOwnUse('Today');
    final available = availableMilk('Today');
    final sessions = [
      (bi('Morning', 'காலை'), _milkFor(today, session: 'Morning')),
      (bi('Afternoon', 'மதியம்'), _milkFor(today, session: 'Afternoon')),
      (bi('Evening', 'மாலை'), _milkFor(today, session: 'Evening')),
    ];
    final delta = total - previous;
    final baseline = previous <= 0
        ? ''
        : delta.abs() < .05
        ? bi('Same as yesterday', 'நேற்றைப் போலவே')
        : bi(
            '${delta > 0 ? '+' : '−'}${_litres(delta.abs())} vs yesterday',
            'நேற்றை விட ${delta > 0 ? '+' : '−'}${_litres(delta.abs())}',
          );

    return Semantics(
      container: true,
      button: true,
      label: bi(
        "Today's milk ${_litres(total)}",
        'இன்றைய பால் ${_litres(total)}',
      ),
      child: Glass(
        radius: Gold.r27,
        padding: const EdgeInsets.fromLTRB(
          Space.s20,
          Space.s16,
          Space.s16,
          Space.s16,
        ),
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.drop_fill,
                            size: 15,
                            color: Ink.orange,
                          ),
                          const SizedBox(width: Space.s4),
                          Flexible(
                            child: AppText(
                              bi("Today's milk", 'இன்றைய பால்'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Ink.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.s4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: CountUpText(
                          value: total,
                          format: _litres,
                          style: TextStyle(
                            fontSize: 40,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.2,
                            color: Ink.deepPurple,
                          ),
                        ),
                      ),
                      if (baseline.isNotEmpty) ...[
                        const SizedBox(height: Space.s2),
                        Text(
                          baseline,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: delta >= 0 ? Ink.greenText : Ink.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Space.s12),
                if (canRecordEntries) _AddMilkButton(onPressed: onAdd),
              ],
            ),
            const SizedBox(height: Space.s16),
            Row(
              children: [
                for (int i = 0; i < sessions.length; i++) ...[
                  if (i > 0) const SizedBox(width: Space.s8),
                  Expanded(
                    child: _SessionCell(
                      label: sessions[i].$1,
                      value: sessions[i].$2,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Space.s12),
            Row(
              children: [
                Expanded(
                  child: AppText(
                    bi('Sold ${_litres(sold)}', 'விற்றது ${_litres(sold)}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Ink.muted),
                  ),
                ),
                AppText(
                  bi(
                    'Available ${_litres(available)}',
                    'இருப்பு ${_litres(available)}',
                  ),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Ink.greenText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCell extends StatelessWidget {
  final String label;
  final double value;
  const _SessionCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final recorded = value > 0;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s12,
        vertical: Space.s8,
      ),
      decoration: ShapeDecoration(
        shape: const SquircleBorder(radius: Gold.r13),
        color: recorded ? Ink.cream : Ink.surface2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: recorded ? Ink.orangeText : Ink.muted,
            ),
          ),
          const SizedBox(height: Space.s2),
          CountUpText(
            value: value,
            format: (v) => recorded || v > 0 ? _litres(v) : '—',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: recorded ? Ink.deepPurple : Ink.faint,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMilkButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddMilkButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: bi('Add milk', 'பால் பதிவு'),
    child: ExcludeSemantics(
      child: Pressable(
        radius: 22,
        onTap: onPressed,
        child: Container(
          height: Space.target,
          padding: const EdgeInsets.symmetric(horizontal: Space.s16),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: Ink.tint,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.plus, size: 17, color: Colors.white),
              const SizedBox(width: Space.s4),
              AppText(
                bi('Milk', 'பால்'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
