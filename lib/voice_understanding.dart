/// One sentence → one intent with its slots, the shape the self-test, the
/// diagnostics report and (later) the dialogue use. Milk sentences come
/// from the tested rules in voice_parser.dart; everything else is added in
/// voice_intents_extra.dart, which is only asked when these rules find
/// nothing.
library;

import 'voice_diagnostics.dart' show VoiceReading;
import 'voice_parser.dart';

/// Everything VIMO can understand in one sentence. [rewrite] applies the
/// owner's own corrections first (on-device learning).
VoiceReading understandVoice(
  String text, {
  List<String> cows = const [],
  Map<String, List<String>> aliases = const {},
  String Function(String text)? rewrite,
}) {
  final heard = rewrite == null ? text : rewrite(text);
  return understandMilkVoice(heard, cows: cows, aliases: aliases);
}

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
