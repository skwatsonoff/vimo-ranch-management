part of 'main.dart';

/// The interface's sound set. Each sound is short and quiet, and plays on
/// the same frame as the visual change and haptic it belongs to (Apple:
/// causality, harmony, utility). Sounds are reserved for meaningful moments:
/// a primary action, a switch, a save, a problem, a page opening and a new
/// notification — never for scrolling or typing.
enum UiSoundKind {
  tap('tap.wav', .55),
  toggleOn('toggle_on.wav', .6),
  toggleOff('toggle_off.wav', .6),
  success('success.wav', .7),
  error('error.wav', .7),
  whoosh('whoosh.wav', .45),
  notification('notification.wav', .7);

  const UiSoundKind(this.file, this.volume);
  final String file;
  final double volume;
}

/// Plays [UiSoundKind]s with no perceptible delay: every sound is loaded
/// into its own small pool of players at launch, so playing is only "start".
///
/// - Settings → Sounds turns them off (default on, stored on this device).
/// - On iOS the players use the ambient audio session, which the Silent
///   switch mutes and which mixes with music instead of stopping it.
/// - On Android they use the sonification stream (system sounds), which
///   silent and vibrate modes mute, and take no audio focus.
/// - While a voice note plays or records, sounds are held back so they never
///   cut into the recording or the message.
class UiSound {
  const UiSound._();

  static const String settingKey = 'uiSounds';

  static bool get enabled =>
      !Hive.isBoxOpen('settings') || settingValue(settingKey, true) != false;

  static final Map<UiSoundKind, AudioPool> _pools = {};
  static final Set<Object> _holds = {};
  static bool _loading = false;
  static bool _reclaimSession = false;
  static DateTime _lastPlayed = DateTime(2000);
  static UiSoundKind? _lastKind;

  static bool get _iOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Widget tests run on a test binding and never load audio.
  static bool get _testing =>
      WidgetsBinding.instance.runtimeType != WidgetsFlutterBinding;

  static AudioContext get _context => AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: _iOS
        ? AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const {AVAudioSessionOptions.mixWithOthers},
          )
        : null,
  );

  /// Loads every sound once. Safe to call more than once.
  static Future<void> preload() async {
    if (_loading || _testing) return;
    _loading = true;
    for (final kind in UiSoundKind.values) {
      try {
        _pools[kind] = await AudioPool.create(
          source: AssetSource('sounds/${kind.file}'),
          audioContext: _context,
          minPlayers: kind == UiSoundKind.tap ? 2 : 1,
          maxPlayers: 3,
          playerMode: PlayerMode.lowLatency,
        );
      } catch (_) {
        // A device without audio output still runs the app silently.
      }
    }
  }

  /// Plays [kind] if sounds are on and nothing is holding them back.
  static void play(UiSoundKind kind) {
    if (!enabled || _holds.isNotEmpty) return;
    final now = DateTime.now();
    // Two of the same sound within 60 ms read as one; skip the echo.
    if (kind == _lastKind &&
        now.difference(_lastPlayed) < const Duration(milliseconds: 60)) {
      return;
    }
    _lastKind = kind;
    _lastPlayed = now;
    final pool = _pools[kind];
    if (pool == null) {
      unawaited(preload());
      return;
    }
    unawaited(_start(pool, kind.volume));
  }

  static Future<void> _start(AudioPool pool, double volume) async {
    try {
      if (_reclaimSession && _iOS) {
        _reclaimSession = false;
        await AudioPlayer.global.setAudioContext(_context);
      }
      await pool.start(volume: volume);
    } catch (_) {}
  }

  /// Holds sounds back while [owner] plays or records audio of its own.
  static void hold(Object owner) => _holds.add(owner);

  /// Releases a [hold]. The other audio may have changed the shared audio
  /// session, so the next sound restores the ambient one first.
  static void release(Object owner) {
    if (_holds.remove(owner)) _reclaimSession = true;
  }

  /// Settings switch.
  static Future<void> setEnabled(bool on) async {
    await setSetting(settingKey, on);
    if (on) {
      unawaited(preload());
      play(UiSoundKind.toggleOn);
    }
  }
}

/// The iOS switch with its toggle sound, played as the thumb moves.
class SoundSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeTrackColor;

  const SoundSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeTrackColor,
  });

  @override
  Widget build(BuildContext context) {
    final changed = onChanged;
    return CupertinoSwitch(
      value: value,
      activeTrackColor: activeTrackColor,
      onChanged: changed == null
          ? null
          : (on) {
              UiSound.play(on ? UiSoundKind.toggleOn : UiSoundKind.toggleOff);
              changed(on);
            },
    );
  }
}
