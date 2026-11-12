import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/voice_parser.dart';

void main() {
  const cows = ['Maina', 'Lakshmi', 'Ganga', 'Ponni', 'Kutty', 'Meena'];

  VoiceCommand p(String text) => parseVoiceCommand(text, cows);

  group('phonetic keys', () {
    test('Tamil and Latin spellings of a name sound alike', () {
      expect(phoneticKey('மைனா'), phoneticKey('Maina'));
      expect(phoneticKey('Mayna'), phoneticKey('Maina'));
      expect(phoneticKey('குட்டி'), phoneticKey('Kutty'));
      expect(phoneticKey('பொன்னி'), phoneticKey('Ponni'));
      expect(phoneticKey('மீனா'), phoneticKey('Meena'));
      expect(phoneticKey('கங்கா'), phoneticKey('Ganga'));
      expect(
        soundSimilarity(phoneticKey('லட்சுமி'), phoneticKey('Lakshmi')),
        greaterThan(cowSureScore),
      );
    });
  });

  group('cow and litres in any order and language', () {
    final sentences = {
      'maina 5 litter add pannu': ('Maina', 5.0),
      'Maina add 5 litter': ('Maina', 5.0),
      'add 5 litre for Maina': ('Maina', 5.0),
      'மைனா 5 லிட்டர் ஆட் பண்ணு': ('Maina', 5.0),
      'மைனாக்கு அஞ்சு லிட்டர்': ('Maina', 5.0),
      'மைனாவுக்கு 5 லிட்டர் போடு': ('Maina', 5.0),
      'maina ku anju litre podu': ('Maina', 5.0),
      'லட்சுமிக்கு ரெண்டரை லிட்டர்': ('Lakshmi', 2.5),
      'Lakshmi two and a half litres': ('Lakshmi', 2.5),
      'ganga 3.5': ('Ganga', 3.5),
      'பொன்னி ஒரு ஆறு லிட்டர்': ('Ponni', 6.0),
      'kutty 4 l': ('Kutty', 4.0),
      'Meena ko paanch litre': ('Meena', 5.0),
      'மீனா ஏழு லிட்டர் பால்': ('Meena', 7.0),
      'five point five litre lakshmi': ('Lakshmi', 5.5),
      'maina 5லிட்டர்': ('Maina', 5.0),
      'அஞ்சு அரை லிட்டர் கங்கா': ('Ganga', 5.5),
    };
    sentences.forEach((text, expected) {
      test(text, () {
        final c = p(text);
        expect(c.cow?.name, expected.$1, reason: '${c.cows}');
        expect(c.litres, expected.$2);
      });
    });
  });

  test('a misheard name is a guess to confirm, not a sure match', () {
    final c = p('mena 5 litre');
    expect(c.cow?.name, 'Meena');
    // "Mena" only sounds near Meena: VIMO must ask before adding.
    expect(c.cowIsSure, isFalse);
    // Same sound, other spelling: "Mina" is Meena.
    expect(p('mina 5 litre').cow?.name, 'Meena');
  });

  test('missing parts are reported as missing', () {
    expect(p('maina add pannu').litres, isNull);
    expect(p('maina add pannu').cow?.name, 'Maina');
    expect(p('5 litre add pannu').cow, isNull);
    expect(p('5 litre add pannu').litres, 5);
  });

  test('asks about alternatives and rejects signed negative quantities', () {
    for (final input in [
      'Maina five or six litres',
      'மைனா அஞ்சா ஆறா லிட்டர்',
    ]) {
      final command = p(input);
      expect(command.cow?.name, 'Maina');
      expect(command.litres, isNull);
      expect(command.quantityOptions, [5.0, 6.0]);
    }
    for (final input in ['Maina -5 litres', 'மைனா − 5 லிட்டர்']) {
      expect(p(input).litres, isNull);
      expect(p(input).invalidQuantity, isTrue);
    }
  });

  test('a milk batch pairs each cow with its own quantity', () {
    final batch = parseMilkBatch('Maina 5, Lakshmi 7', cows)!;
    expect(batch.map((c) => (c.cow?.name, c.litres)), [
      ('Maina', 5.0),
      ('Lakshmi', 7.0),
    ]);
    expect(
      parseMilkBatch(
        '5,5 litres Maina and 7 litres Lakshmi',
        cows,
      )!.map((c) => c.litres),
      [5.5, 7.0],
    );
    expect(parseMilkBatch('Maina 5, unregistered 7', cows), isEmpty);
    expect(parseMilkBatch('Maina five and a half litres', cows), isNull);
  });

  group('wake word', () {
    for (final text in [
      'hey vimo',
      'Vimo',
      'விமோ',
      'ஹே வீமோ',
      'hey bimo',
      'v mo',
    ]) {
      test(text, () => expect(p(text).wake, isTrue));
    }
    for (final text in ['hello', 'demo', 'video', 'maina 5 litre']) {
      test('not $text', () => expect(p(text).wake, isFalse));
    }
    test('wake word with a command in one breath', () {
      final c = p('hey vimo maina 5 litre');
      expect(c.wake, isTrue);
      expect(c.cow?.name, 'Maina');
      expect(c.litres, 5);
    });
  });

  group('answers', () {
    for (final text in [
      'ஆமா',
      'சரி',
      'yes',
      'ok',
      'aama',
      'add pannu',
      'हाँ',
    ]) {
      test('yes: $text', () {
        expect(p(text).yes, isTrue);
        expect(p(text).hasEntryData, isFalse);
      });
    }
    for (final text in ['இல்ல', 'வேண்டாம்', 'no', 'venam', 'தப்பு']) {
      test('no: $text', () => expect(p(text).no, isTrue));
    }
  });

  group('finish', () {
    for (final text in [
      'finish',
      'mudinchu',
      'முடிஞ்சது',
      'பால் கறந்து முடிச்சிட்டேன்',
      'paal karanthu mudichitten',
      'முடிந்தது',
      'போதும்',
      'done',
      'that\'s all',
    ]) {
      test(text, () => expect(p(text).finish, isTrue));
    }
    test('"I cannot" is not finish', () {
      expect(p('முடியல').finish, isFalse);
    });
  });

  test('best alternative wins', () {
    final c = bestVoiceCommand(['my na five', 'maina 5 litre'], cows);
    expect(c.cow?.name, 'Maina');
    expect(c.litres, 5);
  });

  group('five ways to say each thing', () {
    // People speak differently: every intent must work in many phrasings.
    const adds = [
      'add 5 litter for Maina',
      'maina kku 5 litter add pannu',
      'மைனாவுக்கு 5 லிட்டர் சேர்',
      'Maina 5 litre',
      '5 litre maina',
      'மைனா அஞ்சு லிட்டர் பால் கொடுத்தது',
      'maina maadu 5 lit kuduthuchu',
      'Maina gave 5 litres of milk',
      'சரி, மைனா 5 லிட்டர் ஐயா',
      'VIMO maina ku anju liter podu',
    ];
    for (final text in adds) {
      test('add: $text', () {
        final c = p(text);
        expect(c.cow?.name, 'Maina', reason: '${c.cows}');
        expect(c.litres, 5);
        expect(c.sale, isFalse);
      });
    }
    const sales = [
      'selvikku 2 litre paal kuduthen',
      'செல்விக்கு 2 லிட்டர் பால் விற்றேன்',
      'Ravi bought 2 litres milk',
      'sold 2 litres of milk to Ravi',
      'I gave Kumar 2 litres',
      'ravi anna ku 2 litre koduthaen',
    ];
    for (final text in sales) {
      test('sale: $text', () => expect(p(text).sale, isTrue));
    }
    const corrections = {
      '5 இல்லை 6 லிட்டர்': 6.0,
      '5 illa 6 litre': 6.0,
      'not 5, 6 litres': 6.0,
      'தவறு, 6 லிட்டர் என்று மாற்று': 6.0,
      'thappu, 6 litre nu maathu': 6.0,
    };
    corrections.forEach((text, litres) {
      test('correction: $text', () {
        final c = p(text);
        expect(c.correction, isTrue);
        expect(c.litres, litres);
      });
    });
    const removals = [
      'கடைசி பதிவை நீக்கு',
      'remove that',
      'அதை அழி',
      'adha azhichidu',
      'undo',
      'cancel',
    ];
    for (final text in removals) {
      test('remove: $text', () {
        expect(p(text).cancel, isTrue);
        expect(p(text).hasEntryData, isFalse);
      });
    }
  });

  test('which milking and which day', () {
    expect(p('இன்று காலை மைனா 5 லிட்டர்').session, 'Morning');
    expect(p('maina maalaila 5 litre').session, 'Evening');
    expect(p('Maina 5 litres evening').session, 'Evening');
    expect(p('maina 5 litre').session, isNull);
    expect(p('நேற்று மாலை மைனா 5 லிட்டர்').yesterday, isTrue);
    expect(p('nethu maina 5 litre').yesterday, isTrue);
    expect(p('maina 5 litre').yesterday, isFalse);
  });

  test('a saved Tamil name finds the cow', () {
    final c = parseVoiceCommand(
      'செவலை 4 லிட்டர்',
      ['Red'],
      aliases: {
        'Red': ['செவலை'],
      },
    );
    expect(c.cow?.name, 'Red');
    expect(c.litres, 4);
  });
}
