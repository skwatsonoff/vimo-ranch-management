import 'voice_parser.dart';

/// Learns cow suggestions from corrected examples. Quantities are excluded
/// from the features and are always supplied by the current command.
class MilkRecognitionModel {
  final List<(String, Set<String>)> _examples;
  const MilkRecognitionModel._(this._examples);

  factory MilkRecognitionModel.train(
    Iterable<(String, String)> corrections,
    List<String> cows, {
    Map<String, List<String>> aliases = const {},
  }) {
    final examples = <(String, Set<String>)>[];
    for (final (heard, meant) in corrections) {
      final command = parseVoiceCommand(meant, cows, aliases: aliases);
      if (!command.cowIsSure || command.litres == null || command.sale) {
        continue;
      }
      final features = _features(heard);
      if (features.isNotEmpty) examples.add((command.cow!.name, features));
    }
    return MilkRecognitionModel._(examples);
  }

  int get examples => _examples.length;

  String? suggestCow(String heard) {
    final features = _features(heard);
    if (features.isEmpty) return null;
    final scores = <String, double>{};
    for (final (cow, trained) in _examples) {
      final score = features.intersection(trained).length /
          features.union(trained).length;
      if (score > (scores[cow] ?? 0)) scores[cow] = score;
    }
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.isEmpty || ranked.first.value < .72) return null;
    if (ranked.length > 1 && ranked[0].value - ranked[1].value < .12) {
      return null;
    }
    return ranked.first.key;
  }

  static Set<String> _features(String phrase) {
    const context = {
      'hey', 'vimo', 'விமோ', 'today', 'yesterday', 'morning', 'evening',
      'இன்று', 'இன்னைக்கு', 'நேற்று', 'காலை', 'மாலை', 'innaiku', 'nethu',
      'paal', 'பால்', 'milk', 'gave', 'give', 'add', 'podu', 'போடு',
      'கொடுத்தது', 'குடுத்துச்சு', 'kuduthuchu', 'koduthathu',
    };
    final features = <String>{};
    for (final word in voiceTokens(phrase)) {
      final single = parseVoiceCommand(word, const []);
      if (context.contains(word) || single.hasMilkUnit ||
          single.litres != null || single.invalidQuantity) {
        continue;
      }
      final key = phoneticKey(word);
      if (key.length < 3) continue;
      final marked = '^$key\$';
      for (var i = 0; i + 3 <= marked.length; i++) {
        features.add(marked.substring(i, i + 3));
      }
    }
    return features;
  }
}
