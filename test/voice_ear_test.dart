import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/voice_ear.dart';

void main() {
  test('each language gets the ear that knows it', () {
    expect(earModelFor('ta-IN'), tamilEarModel);
    expect(earModelFor('en-IN'), englishEarModel);
    expect(earModelFor('hi-IN'), otherEarModel);
    expect(englishEarModel.id, 'cactus:whistle');
  });

  test("Whisper's language names", () {
    expect(earLanguageFor('ta-IN'), 'tamil');
    expect(earLanguageFor('en-IN'), 'english');
    expect(earLanguageFor('ml-IN'), 'malayalam');
    expect(earLanguageFor('xx'), 'english');
  });

  test('away from the browser the ear says no, and VIMO keeps its usual ear', () async {
    expect(earSupported, isFalse);
    expect(await earDownloaded(tamilEarModel), isFalse);
    final engine = BrowserEarEngine(englishEarModel);
    expect(await engine.initialize(), isFalse);
    await engine.dispose();
  });
}
