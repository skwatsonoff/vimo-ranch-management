import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/milk_recognition_model.dart';

void main() {
  test('learns a confirmed cow across quantities, scripts and word order', () {
    final model = MilkRecognitionModel.train(
      [('vimo butterfly 5 litres', 'Kanmani 5 litres')],
      ['Kanmani', 'Meena'],
    );
    expect(model.examples, 1);
    expect(model.suggestCow('7 லிட்டர் குடுத்துச்சு butterfly'), 'Kanmani');
    expect(model.suggestCow('4 litres'), isNull);
    expect(model.suggestCow('yellow flowers 7 litres'), isNull);
  });

  test('conflicting cow labels do not produce a suggestion', () {
    final model = MilkRecognitionModel.train(
      [
        ('butterfly 5 litres', 'Kanmani 5 litres'),
        ('butterfly 6 litres', 'Meena 6 litres'),
      ],
      ['Kanmani', 'Meena'],
    );
    expect(model.suggestCow('butterfly 7 litres'), isNull);
  });
}
