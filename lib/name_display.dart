part of 'main.dart';

const _knownNames = {
  'Lakshmi': 'லட்சுமி',
  'Ganga': 'கங்கா',
  'Ponni': 'பொன்னி',
  'Kutty': 'குட்டி',
  'Meena': 'மீனா',
};
const _taConsonants = {
  'க': 'k',
  'ங': 'ng',
  'ச': 'ch',
  'ஞ': 'ny',
  'ட': 't',
  'ண': 'n',
  'த': 'th',
  'ந': 'n',
  'ப': 'p',
  'ம': 'm',
  'ய': 'y',
  'ர': 'r',
  'ல': 'l',
  'வ': 'v',
  'ழ': 'zh',
  'ள': 'l',
  'ற': 'r',
  'ன': 'n',
  'ஜ': 'j',
  'ஷ': 'sh',
  'ஸ': 's',
  'ஹ': 'h',
};
const _taVowels = {
  'அ': 'a',
  'ஆ': 'aa',
  'இ': 'i',
  'ஈ': 'ee',
  'உ': 'u',
  'ஊ': 'oo',
  'எ': 'e',
  'ஏ': 'ae',
  'ஐ': 'ai',
  'ஒ': 'o',
  'ஓ': 'oa',
  'ஔ': 'au',
};
const _taSigns = {
  'ா': 'aa',
  'ி': 'i',
  'ீ': 'ee',
  'ு': 'u',
  'ூ': 'oo',
  'ெ': 'e',
  'ே': 'ae',
  'ை': 'ai',
  'ொ': 'o',
  'ோ': 'oa',
  'ௌ': 'au',
  '்': '',
};

/// Display-only transliteration. Original record names remain stable identifiers;
/// an explicitly supplied Tamil/English spelling always takes precedence.
String nameInLanguage(String input, bool tamil) {
  if (tamil) {
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(input)) return input;
    for (final entry in _knownNames.entries) {
      if (input == entry.key || input.startsWith('${entry.key} ')) {
        return input.replaceFirst(entry.key, entry.value);
      }
    }
    const consonants = {
      'zh': 'ழ',
      'sh': 'ஷ',
      'th': 'த',
      'ch': 'ச',
      'ng': 'ங',
      'ny': 'ஞ',
      'kh': 'க',
      'ph': 'ப',
      'bh': 'ப',
      'dh': 'த',
      'gh': 'க',
      'k': 'க',
      'g': 'க',
      'c': 'க',
      'j': 'ஜ',
      't': 'ட',
      'd': 'ட',
      'n': 'ந',
      'p': 'ப',
      'b': 'ப',
      'm': 'ம',
      'y': 'ய',
      'r': 'ர',
      'l': 'ல',
      'v': 'வ',
      'w': 'வ',
      's': 'ஸ',
      'h': 'ஹ',
      'f': 'ஃப',
      'z': 'ஸ',
      'q': 'க',
      'x': 'க்ஸ',
    };
    const vowels = {
      'aa': ('ஆ', 'ா'),
      'ee': ('ஈ', 'ீ'),
      'oo': ('ஊ', 'ூ'),
      'ai': ('ஐ', 'ை'),
      'au': ('ஔ', 'ௌ'),
      'a': ('அ', ''),
      'i': ('இ', 'ி'),
      'u': ('உ', 'ு'),
      'e': ('எ', 'ெ'),
      'o': ('ஒ', 'ொ'),
    };
    final source = input.toLowerCase();
    final result = StringBuffer();
    var i = 0;
    while (i < source.length) {
      String? c;
      for (final key in consonants.keys) {
        if (source.startsWith(key, i)) {
          c = key;
          break;
        }
      }
      if (c != null) {
        result.write(consonants[c]);
        i += c.length;
        String? v;
        for (final key in vowels.keys) {
          if (source.startsWith(key, i)) {
            v = key;
            break;
          }
        }
        if (v == null) {
          result.write('்');
        } else {
          result.write(vowels[v]!.$2);
          i += v.length;
        }
      } else {
        String? v;
        for (final key in vowels.keys) {
          if (source.startsWith(key, i)) {
            v = key;
            break;
          }
        }
        if (v != null) {
          result.write(vowels[v]!.$1);
          i += v.length;
        } else {
          result.write(input[i++]);
        }
      }
    }
    return result.toString();
  }
  for (final entry in _knownNames.entries) {
    if (input == entry.value || input.startsWith('${entry.value} ')) {
      return input.replaceFirst(entry.value, entry.key);
    }
  }
  final out = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (_taConsonants.containsKey(c)) {
      out.write(_taConsonants[c]);
      if (i + 1 < input.length && _taSigns.containsKey(input[i + 1])) {
        out.write(_taSigns[input[++i]]);
      } else {
        out.write('a');
      }
    } else {
      out.write(_taVowels[c] ?? c);
    }
  }
  final value = out.toString();
  return value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

String localizedAnimalLabel(String value) {
  if (!Hive.isBoxOpen('animals')) return value;
  for (final raw in Hive.box('animals').values.whereType<Map>()) {
    if (raw['name'] == value ||
        raw['nameEnglish'] == value ||
        raw['nameTamil'] == value) {
      final explicit = raw[tamilUi ? 'nameTamil' : 'nameEnglish'];
      return explicit is String && explicit.trim().isNotEmpty
          ? explicit
          : nameInLanguage('${raw['name']}', tamilUi);
    }
  }
  return value;
}
