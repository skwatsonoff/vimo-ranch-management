/// The ear VIMO uses where the browser's speech service is blocked: an
/// iPhone web app opened from the Home Screen (Apple allows the speech
/// service only in Safari itself).
///
/// The phone's own keyboard dictation (the 🎤 key) still works there, in
/// every language the phone dictates, Tamil included. The person speaks
/// into a text box; this engine turns what appears in the box into the
/// same [VoiceHeard] results the speech service gives.
///
/// Text already acted on stays in the box (rewriting the box while iOS is
/// dictating would make it lose its place), shown faded by
/// [DictationController], and is never sent twice.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'voice_engine.dart';

/// Holds the dictated text and how much of it VIMO has already used.
class DictationController extends TextEditingController {
  DictationController({super.text});

  int _used = 0;

  /// Characters at the start of [text] already acted on.
  int get used => _used.clamp(0, text.length);
  set used(int value) {
    if (value == _used) return;
    _used = value;
    notifyListeners();
  }

  @override
  set value(TextEditingValue next) {
    if (next.text.length < _used) {
      // Words VIMO already used were deleted (or the box was cleared): what
      // is left of them stays used; anything new after it is fresh.
      _used = _commonPrefix(next.text, text);
    }
    super.value = next;
  }

  /// The words not yet acted on.
  String get fresh => text.substring(used).trim();

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final cut = used;
    if (cut == 0) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final faded = (style ?? const TextStyle()).copyWith(
      color: (style?.color ?? const Color(0xFF8E8E93)).withValues(alpha: .38),
    );
    return TextSpan(
      style: style,
      children: [
        TextSpan(text: text.substring(0, cut), style: faded),
        TextSpan(text: text.substring(cut)),
      ],
    );
  }
}

int _commonPrefix(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

/// [VoiceEngine] fed by the keyboard's dictation (or typing) in a text box.
class KeyboardDictationEngine implements VoiceEngine {
  KeyboardDictationEngine(
    this.controller, {
    this.typingPause = const Duration(milliseconds: 2600),
  }) {
    _last = controller.text;
    controller.addListener(_changed);
  }

  final DictationController controller;

  /// How long typed letters wait before they count as a sentence (Return
  /// sends them at once). Dictated words go to VIMO straight away, and VIMO
  /// ends the sentence itself when they stop.
  final Duration typingPause;

  final _results = StreamController<VoiceHeard>.broadcast();
  final _levels = StreamController<double>.broadcast();
  final _errors = StreamController<VoiceEngineError>.broadcast();
  final _statuses = StreamController<String>.broadcast();
  bool _listening = false;
  bool _closed = false;
  String _last = '';
  Timer? _typed;

  @override
  final Map<String, Object?> facts = {'engine': 'keyboard-dictation'};

  @override
  String get name => 'keyboard';
  @override
  bool get isOffline => false;
  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<List<String>> supportedLocales() async => const [];

  @override
  Future<void> start({
    required String locale,
    List<String> hotwords = const [],
    Duration pauseFor = const Duration(seconds: 12),
    Duration listenFor = const Duration(seconds: 55),
  }) async {
    if (_closed || _listening) return;
    _listening = true;
    _statuses.add(VoiceStatus.listening);
    // Words that arrived while VIMO was busy are not lost.
    if (controller.fresh.isNotEmpty) _emit(isFinal: false);
  }

  void _changed() {
    final now = controller.text;
    final before = _last;
    if (now == before) return; // Only the selection or the faded part moved.
    _last = now;
    final added = now.length - before.length;
    _typed?.cancel();
    if (!_listening || controller.fresh.isEmpty) return;
    if (added.abs() >= 2 || added == 0) {
      // Dictation brings whole words (and rewrites them as it hears more).
      _emit(isFinal: false);
    } else {
      // One letter at a time: someone typing. Wait for a pause or Return.
      _typed = Timer(typingPause, () => _emit(isFinal: true));
    }
  }

  /// Return on the keyboard: the typed or dictated words are a sentence.
  void submit() {
    _typed?.cancel();
    if (_listening && controller.fresh.isNotEmpty) _emit(isFinal: true);
  }

  void _emit({required bool isFinal}) {
    if (_closed) return;
    final words = controller.fresh;
    if (words.isEmpty) return;
    _levels.add(isFinal ? 0 : 6);
    _results.add(VoiceHeard(words, isFinal: isFinal));
  }

  @override
  void changePauseFor(Duration pause) {}

  /// VIMO acted on the words so far: they stay in the box, faded.
  void _useAll() {
    _typed?.cancel();
    controller.used = controller.text.length;
  }

  @override
  Future<void> stop() async {
    _useAll();
    _quiet();
  }

  @override
  Future<void> cancel() async {
    _useAll();
    _quiet();
  }

  void _quiet() {
    if (!_listening || _closed) return;
    _listening = false;
    _statuses.add(VoiceStatus.notListening);
  }

  @override
  Stream<VoiceHeard> get results => _results.stream;
  @override
  Stream<double> get soundLevels => _levels.stream;
  @override
  Stream<VoiceEngineError> get errors => _errors.stream;
  @override
  Stream<String> get statuses => _statuses.stream;

  @override
  Future<void> dispose() async {
    _closed = true;
    _typed?.cancel();
    controller.removeListener(_changed);
    await _results.close();
    await _levels.close();
    await _errors.close();
    await _statuses.close();
  }
}
