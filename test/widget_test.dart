import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:ranch_management/main.dart';

void main() {
  group('VIMO data helpers', () {
    test('cloud ids are Firestore-safe and deterministic', () {
      expect(cloudSafeId(' Cow / C-001 '), 'cow_c-001');
      expect(cloudSafeId(' Cow / C-001 '), cloudSafeId(' Cow / C-001 '));
    });

    test('feed labels are normalized before reports are generated', () {
      expect(cleanFoodLabel('🌾  Green fodder'), 'Green fodder');
      expect(cleanFoodLabel('🌱 Concentrate'), 'Concentrate');
    });

    test('invalid animal image data is rejected safely', () {
      expect(
        animalImage({'imageData': 'data:image/png;base64,broken'}),
        isNull,
      );
      expect(animalImage({'imageUrl': 'not-a-url'}), isNull);
    });

    test('duplicate cloud animals keep only the newest visible copy', () {
      final animals = deduplicateAnimals([
        {
          'type': 'cow',
          'id': 'C001',
          'name': 'Lakshmi',
          'updatedAtMillis': 10,
          'notes': 'old',
        },
        {
          'type': 'cow',
          'id': 'C001',
          'name': 'Lakshmi',
          'updatedAtMillis': 20,
          'notes': 'new',
        },
      ]);

      expect(animals, hasLength(1));
      expect(animals.single['notes'], 'new');
    });

    test('duplicate family users collapse to one normalized member', () {
      final users = deduplicateFamilyUsers([
        {
          'name': 'Brother',
          'role': 'Editor',
          'createdAt': '2025-01-01T00:00:00.000',
        },
        {
          'name': ' brother ',
          'role': 'Manager',
          'createdAt': '2026-01-01T00:00:00.000',
        },
      ]);

      expect(users, hasLength(1));
      expect(users.single['name'], 'brother');
      expect(users.single['role'], 'Editor');
      expect(userKeyFor(' Brother ', 'Viewer'), userKeyFor('brother', 'Owner'));
    });

    test('ranch ids use unique social-handle style rules', () {
      expect(normalizeRanchId(' My Ranch! '), 'my_ranch');
      expect(ranchIdValidationError('my_ranch'), isNull);
      expect(ranchIdValidationError('12ranch'), isNotNull);
      expect(ranchIdValidationError('abc'), isNotNull);
      expect(ranchIdValidationError('admin'), isNotNull);
    });

    test('legacy family roles map to the new permission levels', () {
      expect(normalizeFamilyRole('Owner'), 'Admin');
      expect(normalizeFamilyRole('Manager'), 'Editor');
      expect(normalizeFamilyRole('Basic'), 'Basic Entry');
      expect(normalizeFamilyRole('anything else'), 'Viewer');
    });

    test('first calving promotes a heifer and starts milking', () {
      final promoted = motherAfterCalving(
        {
          'type': 'calf',
          'id': 'K004',
          'name': 'Kutty',
          'status': 'Active',
          'pregnancyStartDate': '2026-01-01',
          'milkingStopDate': '2026-08-01',
        },
        cowId: 'C007',
        calfName: 'Baby',
        calfId: 'K005',
        birthDate: '2026-08-26',
        birthTime: '10:30',
      );

      expect(promoted['type'], 'cow');
      expect(promoted['id'], 'C007');
      expect(promoted['previousCalfId'], 'K004');
      expect(promoted['pregnancyStartDate'], isEmpty);
      expect(promoted['milkingStopDate'], isEmpty);
      expect(promoted['milkingStartDate'], '2026-08-26');
      expect(promoted['lactationStatus'], 'Milking');
      expect(promoted['lastCalfId'], 'K005');
    });

    test('animal photos are converted to a Firestore-safe JPEG', () async {
      final photo = image_lib.Image(width: 32, height: 24);
      image_lib.fill(photo, color: image_lib.ColorRgb8(120, 70, 210));
      final tinyPng =
          'data:image/png;base64,${base64Encode(image_lib.encodePng(photo))}';
      final result = await compressAnimalPhotoDataUrl(tinyPng);
      expect(result, startsWith('data:image/jpeg;base64,'));
      expect(result!.length, lessThan(700000));
    });

    test('rank textures use the requested gold, purple and green assets', () {
      expect(rankBackgroundAsset(1), endsWith('rank_gold.jpg'));
      expect(rankBackgroundAsset(2), endsWith('rank_purple.jpg'));
      expect(rankBackgroundAsset(3), endsWith('rank_green.jpg'));
    });

    test('stock ledger adds purchases and subtracts usage', () {
      final balance = stockBalanceFrom([
        {'item': 'Vaikol', 'movement': 'Purchase', 'quantityKg': 100},
        {'item': 'Vaikol', 'movement': 'Usage', 'quantityKg': 22.5},
        {'item': 'Thavudu', 'movement': 'Purchase', 'quantityKg': 40},
      ], 'Vaikol');

      expect(balance, 77.5);
    });

    test('suggestions prefer the most frequently used names', () {
      final suggestions = frequentNameSuggestions([
        {'name': 'Petrol', 'createdAt': '2026-08-01T10:00:00'},
        {'name': 'Rope', 'createdAt': '2026-08-02T10:00:00'},
        {'name': 'petrol', 'createdAt': '2026-08-03T10:00:00'},
      ], 'name');

      expect(suggestions.first.toLowerCase(), 'petrol');
      expect(suggestions, hasLength(2));
    });

    test('milk customer lookup returns the latest saved quantity', () {
      final quantity = lastMilkQuantityForCustomerFrom([
        {
          'type': 'Milk',
          'customerName': 'Kumar',
          'quantity': 4,
          'createdAt': '2026-08-01T10:00:00',
        },
        {
          'type': 'Milk',
          'customerName': 'kumar',
          'quantity': 5,
          'createdAt': '2026-08-02T10:00:00',
        },
      ], 'Kumar');

      expect(quantity, 5);
    });
  });
}
