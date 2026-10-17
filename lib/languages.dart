part of 'main.dart';

/// A language VIMO speaks. English and Tamil are written in the code next
/// to each message; every other language comes from its own translation
/// file in assets/l10n/, looked up by the English text.
class AppLanguage {
  final String mode, code, native, use, glyph;
  const AppLanguage(this.mode, this.code, this.native, this.use, this.glyph);
}

/// India's main dairy languages, in the order people look for them.
const appLanguages = <AppLanguage>[
  AppLanguage('English', 'en', 'English', 'Use VIMO in English', 'Aa'),
  AppLanguage('Hindi', 'hi', 'हिन्दी', 'VIMO को हिन्दी में इस्तेमाल करें', 'अ'),
  AppLanguage(
    'Tamil',
    'ta',
    'தமிழ்',
    'VIMO-வைத் தமிழில் பயன்படுத்துங்கள்',
    'அ',
  ),
  AppLanguage('Telugu', 'te', 'తెలుగు', 'VIMO ని తెలుగులో ఉపయోగించండి', 'అ'),
  AppLanguage('Kannada', 'kn', 'ಕನ್ನಡ', 'VIMO ಅನ್ನು ಕನ್ನಡದಲ್ಲಿ ಬಳಸಿ', 'ಅ'),
  AppLanguage('Malayalam', 'ml', 'മലയാളം', 'VIMO മലയാളത്തിൽ ഉപയോഗിക്കൂ', 'അ'),
  AppLanguage('Marathi', 'mr', 'मराठी', 'VIMO मराठीत वापरा', 'म'),
  AppLanguage('Gujarati', 'gu', 'ગુજરાતી', 'VIMO ગુજરાતીમાં વાપરો', 'અ'),
  AppLanguage('Punjabi', 'pa', 'ਪੰਜਾਬੀ', 'VIMO ਨੂੰ ਪੰਜਾਬੀ ਵਿੱਚ ਵਰਤੋ', 'ੳ'),
  AppLanguage('Bengali', 'bn', 'বাংলা', 'VIMO বাংলায় ব্যবহার করুন', 'অ'),
  AppLanguage('Odia', 'or', 'ଓଡ଼ିଆ', 'VIMO କୁ ଓଡ଼ିଆରେ ବ୍ୟବହାର କରନ୍ତୁ', 'ଅ'),
];

AppLanguage languageFor(String mode) => appLanguages.firstWhere(
  (l) => l.mode == mode,
  orElse: () => appLanguages.first,
);

AppLanguage get appLanguage => Hive.isBoxOpen('settings')
    ? languageFor(settingText('languageMode', 'English'))
    : appLanguages.first;

class _Template {
  final RegExp pattern;
  final List<int> slots;
  final String translation;
  const _Template(this.pattern, this.slots, this.translation);
}

String _loadedCode = 'en';
Map<String, String> _phrases = const {};
List<_Template> _templates = const [];
final Map<String, String> _translated = {};

/// Loads the translation file for [mode] (or the saved language). English
/// and Tamil need none. Call before switching so the change is instant.
Future<void> loadAppLanguage([String? mode]) async {
  final language = mode == null ? appLanguage : languageFor(mode);
  if (language.code == 'en' || language.code == 'ta') return;
  if (language.code == _loadedCode) return;
  try {
    final raw = await rootBundle.loadString(
      'assets/l10n/${language.code}.json',
    );
    final phrases = Map<String, String>.from(jsonDecode(raw) as Map);
    final placeholder = RegExp(r'\{(\d+)\}');
    final templates = <_Template>[];
    for (final entry in phrases.entries) {
      if (!placeholder.hasMatch(entry.key)) continue;
      final slots = <int>[];
      final pattern = StringBuffer('^');
      var last = 0;
      for (final m in placeholder.allMatches(entry.key)) {
        pattern
          ..write(RegExp.escape(entry.key.substring(last, m.start)))
          ..write('(.+?)');
        slots.add(int.parse(m.group(1)!));
        last = m.end;
      }
      pattern
        ..write(RegExp.escape(entry.key.substring(last)))
        ..write(r'$');
      templates.add(
        _Template(RegExp(pattern.toString(), dotAll: true), slots, entry.value),
      );
    }
    _phrases = phrases;
    _templates = templates;
    _translated.clear();
    _loadedCode = language.code;
  } catch (_) {
    // A missing file leaves the app in English rather than half translated.
  }
}

/// The current language's version of an English message. Messages with
/// values in them ("Sold 2 L") match their template and keep the values.
String tr(String english) {
  final code = appLanguage.code;
  if (code == 'en' || code == 'ta' || code != _loadedCode) return english;
  final exact = _phrases[english];
  if (exact != null) return exact;
  final known = _translated[english];
  if (known != null) return known;
  var result = english;
  for (final t in _templates) {
    final m = t.pattern.firstMatch(english);
    if (m == null) continue;
    result = t.translation;
    for (var i = 0; i < t.slots.length; i++) {
      result = result.replaceAll('{${t.slots[i]}}', m.group(i + 1)!);
    }
    break;
  }
  if (_translated.length > 4000) _translated.clear();
  _translated[english] = result;
  return result;
}
