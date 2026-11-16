// The milk examples from the VIMO Voice brief, against the real parser
// (on-device understanding, no Gemini).
import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/milk_gemini.dart';
import 'package:ranch_management/voice_parser.dart';

void main() {
  const cows = ['Kanmani', 'Lakshmi', 'Sevvalai', 'Sevvala'];
  const aliases = {
    'Kanmani': ['கண்மணி'],
    'Lakshmi': ['லட்சுமி', 'லக்ஷ்மி'],
    'Sevvalai': ['செவலை'],
    'Sevvala': ['செவ்வாளா'],
  };
  VoiceCommand p(String s) => parseVoiceCommand(s, cows, aliases: aliases);

  test('cow first or last, same cow and amount', () {
    final a = p('இன்னைக்கு கண்மணி அஞ்சு லிட்டர்');
    final b = p('அஞ்சு லிட்டர் கொடுத்துச்சு கண்மணி');
    expect(a.cow?.name, 'Kanmani');
    expect(b.cow?.name, 'Kanmani');
    expect(a.litres, 5);
    expect(b.litres, 5);
    expect(a.sale || b.sale, isFalse);
  });

  test('Tanglish, halves and spoken decimals', () {
    expect(p('5 litres kuduthuchu Kanmani').litres, 5);
    expect(p('5 litres kuduthuchu Kanmani').cow?.name, 'Kanmani');
    expect(p('கண்மணி ஐந்தரை லிட்டர்').litres, 5.5);
    expect(p('கண்மணி அஞ்சு புள்ளி ஐந்து').litres, 5.5);
  });

  test('two close cows: ask, and keep the 5 litres', () {
    final c = p('செவ்வாள 5 லிட்டர்');
    expect(c.litres, 5);
    expect(c.cowIsSure, isFalse);
    expect(c.closeCows.toSet(), containsAll(<String>['Sevvala', 'Sevvalai']));
    // The exact registered name is still certain.
    expect(p('Sevvala 5 litre').cowIsSure, isTrue);
  });

  test('5 or 6: offers both and keeps the cow', () {
    final c = p('கண்மணி அஞ்சா ஆறா லிட்டர்');
    expect(c.cow?.name, 'Kanmani');
    expect(c.litres, isNull);
    expect(c.quantityOptions, [5, 6]);
  });

  test('two cows in one sentence stage two rows', () {
    final batch = parseMilkBatch('Kanmani 5, Lakshmi 7', cows, aliases: aliases);
    expect(batch, isNotNull);
    expect([for (final c in batch!) (c.cow?.name, c.litres)],
        [('Kanmani', 5.0), ('Lakshmi', 7.0)]);
  });

  test('unknown cow in a batch is not silently dropped', () {
    final batch = parseMilkBatch('Kanmani 5, Ramu 7', cows, aliases: aliases);
    // An empty batch means "repeat the unclear part": nothing is staged
    // or saved from it, so no silent partial save.
    expect(batch, isEmpty);
  });

  test('negative, money, petrol, sales and chatter are never milk', () {
    final neg = p('கண்மணி -5 லிட்டர்');
    expect(neg.litres == null || neg.invalidQuantity, isTrue);
    final petrol = p('300 ரூபாய் பெட்ரோல்');
    expect(petrol.cow, isNull);
    expect(p('Kanmani paal 5 litre vithen').sale, isTrue);
    expect(p('இன்னைக்கு மழை வருமா').hasEntryData, isFalse);
    expect(p('').isEmpty, isTrue);
  });

  group('Gemini request sanitizer', () {
    test('cow names become tokens; the map stays in the app', () {
      final (r, skip) = buildMilkGeminiRequest('கண்மணி அஞ்சா ஆறா லிட்டர்', aliases);
      expect(skip, isNull);
      expect(r!.text, 'C1 அஞ்சா ஆறா லிட்டர்');
      expect(r.tokens, {'C1': 'Kanmani'});
      expect(r.toJson().toString(), isNot(contains('Kanmani')));
    });

    test('contact details, money, long numbers and chatter are not sent', () {
      expect(buildMilkGeminiRequest('call 98765 43210 Kanmani 5', aliases).$2, MilkGeminiSkip.contact);
      expect(buildMilkGeminiRequest('300 ரூபாய் பெட்ரோல்', aliases).$2, MilkGeminiSkip.money);
      expect(buildMilkGeminiRequest('a@b.co Kanmani', aliases).$2, MilkGeminiSkip.contact);
      expect(buildMilkGeminiRequest('இன்னைக்கு மழை வருமா', aliases).$2, MilkGeminiSkip.noMilkWords);
      expect(buildMilkGeminiRequest('x ' * 40, aliases).$2, MilkGeminiSkip.tooLong);
    });

    test('reply schema: only known tokens, finite litres, no writes', () {
      final (r, _) = buildMilkGeminiRequest('கண்மணி அஞ்சா ஆறா லிட்டர்', aliases);
      final ok = validateMilkGeminiReply({
        'schema': 'vimo.milk.v2',
        'intent': 'milk_record',
        'uncertain': true,
        'entries': [
          {'cow': 'C1', 'litres': null, 'litresChoices': [5, 6], 'session': null},
        ],
      }, r!);
      expect(ok!.entries.single.cow, 'Kanmani');
      expect(ok.entries.single.litresChoices, [5, 6]);
      for (final bad in [
        null,
        'text',
        {'schema': 'vimo.milk.v1'},
        {'schema': 'vimo.milk.v2', 'intent': 'save_now', 'uncertain': false, 'entries': []},
        {'schema': 'vimo.milk.v2', 'intent': 'milk_record', 'uncertain': false, 'entries': [{'cow': 'C9'}]},
        {'schema': 'vimo.milk.v2', 'intent': 'milk_record', 'uncertain': false, 'entries': [{'cow': 'C1', 'litres': -5}]},
        {'schema': 'vimo.milk.v2', 'intent': 'milk_record', 'uncertain': false, 'entries': [{'cow': 'C1', 'litres': double.infinity}]},
        {'schema': 'vimo.milk.v2', 'intent': 'milk_record', 'uncertain': false, 'entries': [{'cow': 'C1', 'litres': 300}]},
        {'schema': 'vimo.milk.v2', 'intent': 'not_milk', 'uncertain': false, 'entries': [{'cow': 'C1'}]},
        {'schema': 'vimo.milk.v2', 'intent': 'milk_record', 'uncertain': 'no', 'entries': []},
        {'schema': 'vimo.milk.v2', 'intent': 'milk_record', 'uncertain': false, 'entries': [{'session': 'night'}]},
      ]) {
        expect(validateMilkGeminiReply(bad, r), isNull, reason: '$bad');
      }
    });
  });
}
