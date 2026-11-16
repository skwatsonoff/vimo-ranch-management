/// What VIMO may send to the Free Tier Gemini helper for one milk turn, and
/// how its answer is checked before VIMO uses it.
///
/// * Only the current milk sentence, never audio or the conversation.
/// * Registered cow names in the sentence are replaced with anonymous tokens
///   (C1, C2, ...). Real names and canonical cow IDs stay in the app; the
///   app maps tokens back itself.
/// * Sentences with contact details, links, money, long numbers, or that are
///   too long, are not sent at all (VIMO asks, or Manual Entry).
/// * The answer must match a versioned schema exactly. Anything else is
///   ignored. Gemini can never save: every assisted entry is read back and
///   confirmed by the owner before the existing save path runs.
library;

const milkGeminiRequestSchema = 'vimo.milk.req.v2';
const milkGeminiReplySchema = 'vimo.milk.v2';

/// The sentence as it may leave the phone, and the token map kept on it.
class MilkGeminiRequest {
  /// The sanitized sentence, cow names replaced by tokens.
  final String text;

  /// Token → registered cow name (kept in the app, never sent).
  final Map<String, String> tokens;

  const MilkGeminiRequest(this.text, this.tokens);

  Map<String, Object?> toJson() => {
    'schema': milkGeminiRequestSchema,
    'text': text,
    'candidates': tokens.keys.toList(),
  };
}

/// Why a sentence is not sent.
enum MilkGeminiSkip { empty, tooLong, contact, money, longNumber, noMilkWords }

final _email = RegExp(r'\S+@\S+\.\S+');
final _url = RegExp(r'(https?://|www\.)\S+', caseSensitive: false);
final _phone = RegExp(r'(\+?\d[\d\s-]{6,}\d)');
final _longNumber = RegExp(r'\d{4,}');
final _money = RegExp(
  r'(₹|\brs\.?\b|\brupees?\b|ரூபா|ரூவா|\bpetrol\b|பெட்ரோல்|\bsale\b|\bsold\b|விற்ற|விற்பனை|\bprice\b|விலை|\bpaid\b|காசு)',
  caseSensitive: false,
);
final _milkWords = RegExp(
  r'(லிட்டர்|லீட்டர்|litre|liter|\blit\b|\bl\b|பால்|paal|milk|கறந்த|கொடுத்து|kuduth|\d|அரை|கால்|முக்கால்|ஒன்|ஒண்ணு|ரெண்டு|இரண்டு|மூணு|மூன்று|நாலு|நான்கு|அஞ்சு|ஐந்து|ஆறு|ஏழு|எட்டு|ஒம்பது|ஒன்பது|பத்து|one|two|three|four|five|six|seven|eight|nine|ten|half|onnu|rendu|moonu|naalu|anju|aaru|ezhu|ettu|pathu)',
  caseSensitive: false,
);

/// Builds the request, or says why the sentence must not be sent.
/// [cows] maps each registered cow's display name to its spoken aliases.
(MilkGeminiRequest?, MilkGeminiSkip?) buildMilkGeminiRequest(
  String sentence,
  Map<String, List<String>> cows,
) {
  var text = sentence.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return (null, MilkGeminiSkip.empty);
  if (text.length > 160 || text.split(' ').length > 24) {
    return (null, MilkGeminiSkip.tooLong);
  }
  if (_email.hasMatch(text) || _url.hasMatch(text) || _phone.hasMatch(text)) {
    return (null, MilkGeminiSkip.contact);
  }
  if (_money.hasMatch(text)) return (null, MilkGeminiSkip.money);
  if (_longNumber.hasMatch(text)) return (null, MilkGeminiSkip.longNumber);
  if (!_milkWords.hasMatch(text)) return (null, MilkGeminiSkip.noMilkWords);

  // Longest names first, so "Kanmani 2" wins over "Kanmani".
  final spellings = <(String, String)>[
    for (final entry in cows.entries)
      for (final s in {entry.key, ...entry.value})
        if (s.trim().length >= 2) (s.trim(), entry.key),
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));
  final tokens = <String, String>{};
  final byCow = <String, String>{};
  for (final (spelling, cow) in spellings) {
    final pattern = RegExp(
      '(?<![\\p{L}\\p{M}\\p{N}])${RegExp.escape(spelling)}(?![\\p{L}\\p{M}\\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    if (!pattern.hasMatch(text)) continue;
    final token = byCow[cow] ??= 'C${byCow.length + 1}';
    tokens[token] = cow;
    text = text.replaceAll(pattern, token);
  }
  return (MilkGeminiRequest(text, tokens), null);
}

/// One staged entry from a validated reply.
class MilkGeminiEntry {
  /// A registered cow name (from a token), or null.
  final String? cow;

  /// Words Gemini thinks name an unregistered or misheard cow; VIMO
  /// resolves them locally against registered cows only.
  final String? cowWords;
  final double? litres;

  /// When the amount was unclear ("5 or 6"), the choices to offer.
  final List<double> litresChoices;

  /// 'Morning', 'Evening', or null when not said.
  final String? session;

  const MilkGeminiEntry({
    this.cow,
    this.cowWords,
    this.litres,
    this.litresChoices = const [],
    this.session,
  });
}

class MilkGeminiReply {
  /// 'milk_record', 'not_milk' or 'unclear'.
  final String intent;
  final List<MilkGeminiEntry> entries;
  final bool uncertain;
  const MilkGeminiReply(this.intent, this.entries, this.uncertain);
}

double? _litres(Object? value, double max) {
  if (value is! num) return null;
  final v = value.toDouble();
  if (!v.isFinite || v <= 0 || v > max) return null;
  return v;
}

/// Checks Gemini's answer against the schema and the request's tokens.
/// Returns null for anything malformed, unknown or out of range.
MilkGeminiReply? validateMilkGeminiReply(
  Object? raw,
  MilkGeminiRequest request, {
  double maxLitres = 99,
}) {
  if (raw is! Map) return null;
  if (raw['schema'] != milkGeminiReplySchema) return null;
  final intent = raw['intent'];
  if (intent is! String ||
      !const {'milk_record', 'not_milk', 'unclear'}.contains(intent)) {
    return null;
  }
  final uncertain = raw['uncertain'];
  if (uncertain is! bool) return null;
  final list = raw['entries'];
  if (list is! List || list.length > 6) return null;
  if (intent != 'milk_record' && list.isNotEmpty) return null;
  final entries = <MilkGeminiEntry>[];
  for (final item in list) {
    if (item is! Map) return null;
    final token = item['cow'];
    if (token != null &&
        (token is! String || !request.tokens.containsKey(token))) {
      return null;
    }
    final words = item['cowWords'];
    if (words != null &&
        (words is! String ||
            words.isEmpty ||
            words.length > 40 ||
            RegExp(r'C\d').hasMatch(words))) {
      return null;
    }
    final litres = item['litres'];
    if (litres != null && _litres(litres, maxLitres) == null) return null;
    final choices = item['litresChoices'] ?? const [];
    if (choices is! List || choices.length > 3) return null;
    final parsedChoices = <double>[];
    for (final c in choices) {
      final v = _litres(c, maxLitres);
      if (v == null) return null;
      parsedChoices.add(v);
    }
    final session = item['session'];
    if (session != null && session != 'morning' && session != 'evening') {
      return null;
    }
    entries.add(
      MilkGeminiEntry(
        cow: token == null ? null : request.tokens[token as String],
        cowWords: words as String?,
        litres: _litres(litres, maxLitres),
        litresChoices: parsedChoices,
        session: switch (session) {
          'morning' => 'Morning',
          'evening' => 'Evening',
          _ => null,
        },
      ),
    );
  }
  return MilkGeminiReply(intent, entries, uncertain);
}
