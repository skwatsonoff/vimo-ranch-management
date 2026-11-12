part of 'main.dart';

bool validMilkQuantity(double litres) =>
    litres.isFinite && litres > 0 && litres <= maxMilkLitres;

Map<String, dynamic>? milkCowByName(String name) {
  final wanted = name.trim().toLowerCase();
  if (wanted.isEmpty || !Hive.isBoxOpen('animals')) return null;
  final matches = animalsBy('cow').where(
    (cow) =>
        txt(cow, 'gender', 'Female') != 'Male' &&
        txt(cow, 'name').trim().toLowerCase() == wanted,
  );
  return matches.length == 1 ? matches.single : null;
}

Map<String, dynamic> milkRecord(
  Map<String, dynamic> cow,
  double litres,
  DateTime at,
  String session,
  String notes,
) {
  final id = txt(cow, 'id').trim();
  final cloudId = txt(cow, 'cloudId').trim();
  final cowId = cloudId.isNotEmpty
      ? cloudId
      : id.isNotEmpty
      ? 'animal_${cloudSafeId(id)}'
      : null;
  return {
    'cow': txt(cow, 'name').trim(),
    'cowId': ?cowId,
    'date': _dayOf(at),
    'time': '${two(at.hour)}:${two(at.minute)}',
    'session': session,
    'quantity': litres,
    'notes': notes,
    'addedBy': currentUserName(),
    'createdAt': at.toIso8601String(),
  };
}
