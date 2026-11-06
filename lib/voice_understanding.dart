/// One sentence → one intent with its slots, the shape the self-test, the
/// diagnostics report and (later) the dialogue use. Milk sentences come
/// from the tested rules in voice_parser.dart; everything else is added in
/// voice_intents_extra.dart, which is only asked when these rules find
/// nothing.
library;

import 'voice_diagnostics.dart' show VoiceReading;
import 'voice_intents_extra.dart';
import 'voice_parser.dart';

export 'voice_intents_extra.dart' show extraIntent, personIn, amountsIn;

/// Everything VIMO can understand in one sentence. [rewrite] applies the
/// owner's own corrections first (on-device learning).
VoiceReading understandVoice(
  String text, {
  List<String> cows = const [],
  Map<String, List<String>> aliases = const {},
  String Function(String text)? rewrite,
}) {
  final heard = rewrite == null ? text : rewrite(text);
  final c = parseVoiceCommand(heard, cows, aliases: aliases);
  final milk = readingFromCommand(c);
  final tokens = voiceTokens(heard);
  // "150 இல்லை 250 ரூபாய்": a corrected amount of money.
  if (c.correction && milk.intent != 'edit_last') {
    final money = amountsIn(tokens);
    if (money.isNotEmpty) {
      return (intent: 'edit_last', slots: {'amount': money.last});
    }
  }
  // A clear milk entry, removal or correction stays with the milk rules.
  final sureMilk =
      milk.intent == 'milk_record' &&
      milk.slots['cow'] != null &&
      milk.slots['liters'] != null;
  if (const {'edit_last', 'delete_last'}.contains(milk.intent)) return milk;
  final extra = extraIntent(heard, cows: cows, aliases: aliases);
  // A sentence with its own ranch words (expense, feed, doctor, a new cow,
  // a question…) is that, even when it also names a cow and a number.
  if (extra != null && !(sureMilk && _weakOverMilk.contains(extra.intent))) {
    return extra;
  }
  if (milk.intent == 'sell_milk') return _withPerson(milk, tokens);
  return milk;
}

/// Intents that never replace a clear "cow + litres" milk entry.
const _weakOverMilk = {'payment', 'unknown'};

VoiceReading _withPerson(VoiceReading sale, List<String> tokens) =>
    (intent: sale.intent, slots: {...sale.slots, 'name': personIn(tokens)});

/// Reads [text] for a ranch with [cows] (and their other spellings).
VoiceReading understandMilkVoice(
  String text, {
  List<String> cows = const [],
  Map<String, List<String>> aliases = const {},
}) {
  final c = parseVoiceCommand(text, cows, aliases: aliases);
  return readingFromCommand(c);
}

/// The intent a parsed milk sentence carries.
VoiceReading readingFromCommand(VoiceCommand c) {
  final date = c.yesterday ? 'yesterday' : 'today';
  if (c.cancel && !c.hasEntryData) {
    return (intent: 'delete_last', slots: const {});
  }
  if (c.correction && c.litres != null && c.cow == null) {
    return (intent: 'edit_last', slots: {'liters': c.litres});
  }
  if (c.sale) {
    return (
      intent: 'sell_milk',
      slots: {'liters': c.litres, 'session': c.session, 'date': date},
    );
  }
  if (c.hasEntryData) {
    return (
      intent: 'milk_record',
      slots: {
        'cow': c.cowIsSure ? c.cow?.name : null,
        'liters': c.litres,
        'session': c.session,
        'date': date,
      },
    );
  }
  if (c.finish) return (intent: 'finish', slots: const {});
  if (c.no) return (intent: 'no', slots: const {});
  if (c.yes) return (intent: 'yes', slots: const {});
  if (c.wake && c.rest.isEmpty) return (intent: 'wake', slots: const {});
  return (intent: 'unknown', slots: const {});
}

/// What the owner taught VIMO, applied before understanding: whole
/// sentences, and single words compared by sound ("மைனஸ்" heard when
/// "மைனா" was said).
class VoiceLexicon {
  VoiceLexicon({Map<String, String>? words, Map<String, String>? sentences})
    : words = words ?? {},
      sentences = sentences ?? {};

  /// phoneticKey(heard word) → the word meant.
  final Map<String, String> words;

  /// heard sentence (lower case) → the sentence meant.
  final Map<String, String> sentences;

  bool get isEmpty => words.isEmpty && sentences.isEmpty;

  /// Learns from one correction. Same number of words: each differing word
  /// is learned on its own, so it helps in every later sentence. Otherwise
  /// the whole sentence is learned.
  /// Returns the word pairs learned (heard → meant).
  List<(String, String)> learn(String heard, String meant) {
    final from = heard.trim();
    final to = meant.trim();
    if (from.isEmpty || to.isEmpty || from == to) return const [];
    sentences[from.toLowerCase()] = to;
    final a = voiceTokens(from);
    final b = voiceTokens(to);
    final pairs = <(String, String)>[];
    if (a.length == b.length) {
      for (int i = 0; i < a.length; i++) {
        if (a[i] == b[i]) continue;
        final key = phoneticKey(a[i]);
        // Numbers are said differently every time: never learn them.
        if (key.isEmpty || extractLitres([a[i]]) != null) continue;
        words[key] = b[i];
        pairs.add((a[i], b[i]));
      }
    }
    return pairs;
  }

  String apply(String text) {
    final whole = sentences[text.trim().toLowerCase()];
    if (whole != null) return whole;
    if (words.isEmpty) return text;
    final tokens = voiceTokens(text);
    var changed = false;
    final out = [
      for (final t in tokens)
        () {
          final meant = words[phoneticKey(t)];
          if (meant == null || meant == t) return t;
          changed = true;
          return meant;
        }(),
    ];
    return changed ? out.join(' ') : text;
  }
}
