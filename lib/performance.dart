part of 'main.dart';

/// Matches the effects to the phone. On a capable phone VIMO uses the full
/// Liquid Glass with its motion; on a low-end phone it switches to solid
/// surfaces without animations, so everything stays quick and smooth.
/// Always automatic, from the phone itself; there is no setting for it.
class DevicePerformance {
  const DevicePerformance._();

  /// Always 'auto': the phone decides.
  static String get mode => 'auto';

  /// What the last measurement found, remembered so the next launch starts
  /// in the right style.
  static bool get lowEnd => settingValue('lowEndDevice', false) == true;

  static bool get fast => mode == 'fast' || (mode == 'auto' && lowEnd);

  static bool _measuring = false;

  /// Watches real frames for a short while after launch. A phone that
  /// misses most frames at 60 Hz is treated as low-end.
  static void measure(VoidCallback onChange) {
    if (_measuring) return;
    _measuring = true;
    if (!lowEnd && _browserRuntime.lowEndHint) {
      unawaited(setSetting('lowEndDevice', true));
      onChange();
    }
    final samples = <int>[];
    late final TimingsCallback watch;
    // Launch work is slow everywhere; judge ordinary use only.
    final start = DateTime.now().add(const Duration(seconds: 4));
    watch = (timings) {
      if (DateTime.now().isBefore(start)) return;
      for (final t in timings) {
        samples.add(t.totalSpan.inMicroseconds);
      }
      if (samples.length < 90) return;
      SchedulerBinding.instance.removeTimingsCallback(watch);
      samples.sort();
      final p75 = samples[(samples.length * .75).floor()];
      final slow = p75 > 22000;
      if (slow != lowEnd) {
        unawaited(setSetting('lowEndDevice', slow));
        onChange();
      }
    };
    SchedulerBinding.instance.addTimingsCallback(watch);
  }
}
