// =============================================================================
//  VIMO  ·  My Ranch
//  Manage. Care. Grow.
//
//  A dairy-farm management app built on a golden-ratio design system with an
//  Apple-style Liquid Glass material layer.
//
//  Design foundations
//  ------------------
//  · Every spacing, radius and type step comes from the Fibonacci / phi ladder
//    defined in the `Gold` class. Nothing is an arbitrary number.
//  · All surfaces are squircles (superellipse corners), not circular-arc
//    rounded rectangles, matching Apple's continuous corner curvature.
//  · Glass surfaces carry a real specular rim, an inner sheen at the golden
//    minor (0.382) height, and layered ambient + key shadows.
//  · Motion is uniformly easeOutCubic with phi-derived durations.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as image_lib;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'web_runtime.dart';

bool firebaseReady = false;

/// Local visual-QA switch. Production builds keep this false unless the
/// developer explicitly passes --dart-define=VIMO_PREVIEW_MODE=true.
const bool vimoPreviewMode = bool.fromEnvironment('VIMO_PREVIEW_MODE');

/// One deliberate pre-launch reset. Keep this marker unchanged in every future
/// release: changing it would clear real customer data on the next app start.
const String prelaunchResetMarker = 'vimo_prelaunch_reset_20260826';

const List<String> backupBoxNames = [
  'animals',
  'milk_records',
  'food_records',
  'stock_records',
  'expense_records',
  'doctor_records',
  'purchase_records',
  'sale_records',
  'death_records',
  'calving_records',
  'settings',
  'family_users',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Ink.canvasLow,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    firebaseReady = true;
  } catch (_) {
    firebaseReady = false;
  }

  await Hive.initFlutter();
  for (final name in backupBoxNames) {
    await Hive.openBox(name);
  }

  await applyPrelaunchResetOnce();
  await seedAnimals();
  await seedSettingsAndUsers();
  AutoSyncService.start();

  runApp(const VimoApp());
}

// -----------------------------------------------------------------------------
//  Seeding
// -----------------------------------------------------------------------------

Future<void> applyPrelaunchResetOnce() async {
  if (vimoPreviewMode) return;
  final settings = Hive.box('settings');
  if (settings.get(prelaunchResetMarker) == true) return;

  final existingDeviceId = '${settings.get('deviceId', defaultValue: '')}';
  for (final name in backupBoxNames) {
    if (name == 'settings') continue;
    await Hive.box(name).clear();
  }
  await settings.clear();
  if (existingDeviceId.isNotEmpty) {
    await settings.put('deviceId', existingDeviceId);
  }
  await settings.put(prelaunchResetMarker, true);
}

Future<void> seedAnimals() async {
  final box = Hive.box('animals');
  if (box.isNotEmpty) return;
  // Production accounts start with an empty ranch. Demo animals are only
  // useful for explicit visual-QA builds and must never leak into a new user's
  // ranch or be uploaded to Firebase.
  if (!vimoPreviewMode) return;

  final base = <String, dynamic>{
    'status': 'Active',
    'mother': '',
    'arrivalDate': todayDate(),
    'source': 'Existing',
    'purchaseAmount': 0.0,
    'pregnancyStartDate': '',
    'pregnancyInjection': '',
    'milkingStopDate': '',
    'notes': '',
    'gender': '',
    'imageUrl': '',
    'imageData': '',
  };

  await box.add({
    ...base,
    'type': 'cow',
    'name': 'Lakshmi',
    'id': 'C001',
    'breed': 'HF Cross',
    'dob': '2021-05-01',
    'ageYears': 0,
    'ageMonths': 0,
    'ageDays': 0,
  });
  await box.add({
    ...base,
    'type': 'cow',
    'name': 'Ganga',
    'id': 'C002',
    'breed': 'Jersey Cross',
    'dob': '2022-02-10',
    'ageYears': 0,
    'ageMonths': 0,
    'ageDays': 0,
  });
  await box.add({
    ...base,
    'type': 'cow',
    'name': 'Ponni',
    'id': 'C003',
    'breed': 'Native Cow',
    'dob': '',
    'ageYears': 6,
    'ageMonths': 0,
    'ageDays': 0,
  });
  await box.add({
    ...base,
    'type': 'calf',
    'name': 'Kutty 1',
    'id': 'K001',
    'breed': 'HF Cross',
    'dob': todayDate(),
    'ageYears': 0,
    'ageMonths': 0,
    'ageDays': 0,
    'mother': 'Lakshmi',
    'source': 'Born',
    'gender': 'Female',
  });
}

Future<void> seedSettingsAndUsers() async {
  final settings = Hive.box('settings');

  Future<void> putIfMissing(String key, dynamic value) async {
    if (!settings.containsKey(key)) await settings.put(key, value);
  }

  await putIfMissing('appName', 'VIMO');
  await putIfMissing('farmName', 'My Ranch');
  await putIfMissing('ownerName', '');
  await putIfMissing('place', '');
  await putIfMissing('currency', '\u20b9');
  await putIfMissing('defaultMilkPrice', 60.0);
  await putIfMissing('languageMode', 'Tamil-English');
  await putIfMissing('ranchId', '');
  await putIfMissing('pendingRanchId', '');
  await putIfMissing('currentUser', '');
  await putIfMissing('currentRole', '');
  await putIfMissing('autoSyncEnabled', true);
  await putIfMissing('pendingSync', false);
  await putIfMissing('pendingSyncCount', 0);
  await putIfMissing('lastSyncedAt', '');
  await putIfMissing('syncStatus', 'Waiting for sync');
  await putIfMissing('lastAutoSyncReason', '');
  await putIfMissing(
    'deviceId',
    'dev_${DateTime.now().millisecondsSinceEpoch}',
  );

  await normalizeFamilyUsers();
}

String normalizeFamilyRole(String role) {
  final value = role.trim().toLowerCase();
  if (value == 'owner' || value == 'admin') return 'Admin';
  if (value == 'manager' || value == 'editor') return 'Editor';
  if (value == 'basic' || value == 'basic entry' || value == 'entry') {
    return 'Basic Entry';
  }
  return 'Viewer';
}

int familyUserUpdatedAt(Map<String, dynamic> user) {
  final millis = toInt(user['updatedAtMillis']);
  if (millis > 0) return millis;
  return DateTime.tryParse(txt(user, 'createdAt'))?.millisecondsSinceEpoch ?? 0;
}

List<Map<String, dynamic>> deduplicateFamilyUsers(Iterable<Map> values) {
  final byName = <String, Map<String, dynamic>>{};
  for (final raw in values) {
    final user = Map<String, dynamic>.from(raw);
    final name = txt(user, 'name').trim();
    if (name.isEmpty) continue;

    user['name'] = name;
    user['role'] = normalizeFamilyRole(txt(user, 'role', 'Viewer'));
    final identity = name.toLowerCase();
    final current = byName[identity];
    if (current == null ||
        familyUserUpdatedAt(user) >= familyUserUpdatedAt(current)) {
      byName[identity] = user;
    }
  }
  return byName.values.toList();
}

String userKeyFor(String name, String _) =>
    cloudSafeId(name.trim().toLowerCase());

Future<void> normalizeFamilyUsers() async {
  final users = Hive.box('family_users');
  final cleaned = deduplicateFamilyUsers(users.values.whereType<Map>())
      .where((user) {
        // Older demo builds manufactured these rows on every device. They are
        // not real authenticated members and should disappear during upgrade.
        final system = txt(user, 'addedBy') == 'System';
        final noUid = txt(user, 'authUid').isEmpty;
        final legacyId = {
          'selva_owner',
          'brother_manager',
          'father_viewer',
        }.contains(txt(user, 'userId'));
        return !(system && noUid && legacyId);
      })
      .map((user) {
        final uid = txt(user, 'authUid');
        return <String, dynamic>{
          ...user,
          'userId': uid.isNotEmpty
              ? uid
              : txt(
                  user,
                  'userId',
                  userKeyFor(txt(user, 'name'), txt(user, 'role', 'Viewer')),
                ),
          'role': normalizeFamilyRole(txt(user, 'role', 'Viewer')),
          'active': user['active'] ?? true,
        };
      })
      .toList();
  await users.clear();
  for (final user in cleaned) {
    await users.put(txt(user, 'userId'), user);
  }
}

// -----------------------------------------------------------------------------
//  Cross-platform file helpers
// -----------------------------------------------------------------------------

Future<bool> downloadCsvFile(String fileName, String csvContent) async {
  final contentWithBom = '\ufeff$csvContent';
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save VIMO report',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['csv'],
    bytes: Uint8List.fromList(utf8.encode(contentWithBom)),
  );
  return path != null;
}

Future<bool> downloadJsonFile(String fileName, String jsonContent) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save VIMO backup',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['json'],
    bytes: Uint8List.fromList(utf8.encode(jsonContent)),
  );
  return path != null;
}

Future<bool> downloadExcelFile(String fileName, String workbookContent) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save complete VIMO Excel workbook',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['xls'],
    bytes: Uint8List.fromList(utf8.encode(workbookContent)),
  );
  return path != null;
}

String safeFileName(String text) =>
    text.toLowerCase().replaceAll(' ', '_').replaceAll('/', '_');

String cleanFoodLabel(String value) => value
    .replaceAll('\u{1F6CD}\u{FE0F}', '')
    .replaceAll('\u{1F6CD}', '')
    .replaceAll('\u{1F33E}', '')
    .replaceAll('\u{1F331}', '')
    .trim();

String buildBackupJson() {
  final backup = <String, dynamic>{
    'app': 'VIMO',
    'version': 'v20',
    'addedBy': currentUserName(),
    'createdAt': DateTime.now().toIso8601String(),
  };

  for (final boxName in backupBoxNames) {
    final box = Hive.box(boxName);
    if (boxName == 'settings') {
      backup[boxName] = box.toMap().map(
        (key, value) => MapEntry('$key', value),
      );
    } else {
      backup[boxName] = box.values
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
  }

  return const JsonEncoder.withIndent('  ').convert(backup);
}

String _xml(dynamic value) => '$value'
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _excelLabel(String key) {
  final spaced = key
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll('_', ' ')
      .trim();
  if (spaced.isEmpty) return key;
  return spaced
      .split(RegExp(r'\s+'))
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

String _excelValue(dynamic value) {
  if (value == null) return '';
  if (value is Uint8List || value is ByteData) return '[image stored in app]';
  if (value is Map || value is Iterable) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
  }
  return '$value';
}

String _excelCell(dynamic value, {String? style}) {
  final safeStyle = style == null ? '' : ' ss:StyleID="$style"';
  if (value is num && value.isFinite) {
    return '<Cell$safeStyle><Data ss:Type="Number">$value</Data></Cell>';
  }
  return '<Cell$safeStyle><Data ss:Type="String">${_xml(_excelValue(value))}</Data></Cell>';
}

String _excelWorksheet(
  String name,
  List<Map<String, dynamic>> data, {
  List<String>? preferredColumns,
}) {
  final keys = <String>[];
  for (final key in preferredColumns ?? const <String>[]) {
    if (!keys.contains(key)) keys.add(key);
  }
  for (final row in data) {
    for (final key in row.keys) {
      if (key == 'imageData' || key == 'key') continue;
      if (!keys.contains(key)) keys.add(key);
    }
  }
  if (keys.isEmpty) keys.add('status');

  final safeName = name
      .replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ')
      .trim()
      .substring(0, math.min(31, name.trim().length));
  final b = StringBuffer(
    '<Worksheet ss:Name="${_xml(safeName)}"><Table>'
    '<Row ss:StyleID="header">',
  );
  for (final key in keys) {
    b.write(_excelCell(_excelLabel(key), style: 'header'));
  }
  b.write('</Row>');
  if (data.isEmpty) {
    b.write('<Row>${_excelCell('No records yet')}</Row>');
  } else {
    for (final row in data) {
      b.write('<Row>');
      for (final key in keys) {
        b.write(_excelCell(row[key]));
      }
      b.write('</Row>');
    }
  }
  b.write(
    '</Table><WorksheetOptions xmlns="urn:schemas-microsoft-com:office:excel">'
    '<FreezePanes/><FrozenNoSplit/><SplitHorizontal>1</SplitHorizontal>'
    '<TopRowBottomPane>1</TopRowBottomPane><ActivePane>2</ActivePane>'
    '</WorksheetOptions></Worksheet>',
  );
  return b.toString();
}

String buildCompleteExcelWorkbook() {
  List<Map<String, dynamic>> boxData(String boxName) => Hive.box(boxName).values
      .whereType<Map>()
      .map((value) => Map<String, dynamic>.from(value))
      .toList();

  final summary = <Map<String, dynamic>>[
    {'detail': 'App', 'value': appName()},
    {'detail': 'Ranch', 'value': farmName()},
    {'detail': 'Owner', 'value': ownerName()},
    {'detail': 'Place', 'value': placeName()},
    {'detail': 'Exported at', 'value': DateTime.now().toIso8601String()},
    {'detail': 'Active cows', 'value': animalsBy('cow').length},
    {'detail': 'Active calves', 'value': animalsBy('calf').length},
    {'detail': 'Total milk (L)', 'value': milkTotal('All')},
    {'detail': 'Total income', 'value': saleIncome('All')},
    {'detail': 'Total expense', 'value': totalExpense('All')},
    {'detail': 'Net result', 'value': profit('All')},
  ];

  final settings = Hive.box('settings')
      .toMap()
      .entries
      .where((entry) => !{'deviceId', 'firebaseUid'}.contains('${entry.key}'))
      .map(
        (entry) => <String, dynamic>{
          'setting': '${entry.key}',
          'value': entry.value,
        },
      )
      .toList();

  final workbook = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<?mso-application progid="Excel.Sheet"?>'
    '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
    'xmlns:o="urn:schemas-microsoft-com:office:office" '
    'xmlns:x="urn:schemas-microsoft-com:office:excel" '
    'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">'
    '<DocumentProperties xmlns="urn:schemas-microsoft-com:office:office">'
    '<Author>VIMO</Author><Company>${_xml(farmName())}</Company>'
    '<Title>Complete Ranch Data</Title></DocumentProperties>'
    '<Styles><Style ss:ID="Default" ss:Name="Normal">'
    '<Alignment ss:Vertical="Center"/><Font ss:FontName="Courier New" ss:Size="11"/>'
    '</Style><Style ss:ID="header"><Font ss:FontName="Courier New" ss:Bold="1" ss:Color="#FFFFFF"/>'
    '<Interior ss:Color="#5B23D9" ss:Pattern="Solid"/>'
    '<Alignment ss:Vertical="Center"/></Style></Styles>',
  );
  workbook
    ..write(
      _excelWorksheet(
        'Summary',
        summary,
        preferredColumns: const ['detail', 'value'],
      ),
    )
    ..write(
      _excelWorksheet(
        'Cows and Calves',
        boxData('animals'),
        preferredColumns: const [
          'id',
          'name',
          'type',
          'breed',
          'gender',
          'dob',
          'status',
          'mother',
          'source',
          'arrivalDate',
          'purchaseAmount',
          'notes',
        ],
      ),
    )
    ..write(_excelWorksheet('Milk Records', boxData('milk_records')))
    ..write(_excelWorksheet('Legacy Feed Records', boxData('food_records')))
    ..write(_excelWorksheet('Stock Ledger', boxData('stock_records')))
    ..write(_excelWorksheet('Other Expenses', boxData('expense_records')))
    ..write(_excelWorksheet('Doctor Visits', boxData('doctor_records')))
    ..write(_excelWorksheet('Purchases', boxData('purchase_records')))
    ..write(_excelWorksheet('Sales', boxData('sale_records')))
    ..write(_excelWorksheet('Deaths and Loss', boxData('death_records')))
    ..write(_excelWorksheet('Calving Records', boxData('calving_records')))
    ..write(_excelWorksheet('Family Users', boxData('family_users')))
    ..write(
      _excelWorksheet(
        'Ranch Settings',
        settings,
        preferredColumns: const ['setting', 'value'],
      ),
    )
    ..write('</Workbook>');
  return workbook.toString();
}

Future<void> restoreBackupData(BuildContext context) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
    allowMultiple: false,
    withData: true,
  );
  final bytes = result?.files.firstOrNull?.bytes;
  if (bytes == null) return;

  if (!context.mounted) return;

  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      snack(context, 'Invalid backup file');
      return;
    }

    for (final boxName in backupBoxNames) {
      final value = decoded[boxName];
      final box = Hive.box(boxName);
      if (boxName == 'settings' && value is Map) {
        await box.clear();
        for (final entry in value.entries) {
          await box.put('${entry.key}', entry.value);
        }
      } else if (value is List) {
        await box.clear();
        for (final item in value) {
          if (item is Map) await box.add(Map<String, dynamic>.from(item));
        }
      }
    }

    if (context.mounted) snack(context, 'Backup restored successfully');
  } catch (_) {
    if (context.mounted) {
      snack(context, 'Restore failed. Please choose a valid backup file');
    }
  }
}

Future<String?> pickImageDataUrl() async {
  // iOS home-screen PWAs are much more reliable when the native HTML file
  // input is opened directly from the tap event. BrowserRuntime provides that
  // path on web; desktop/mobile Flutter keeps FilePicker as the fallback.
  try {
    final webImage = await _browserRuntime.pickImageDataUrl();
    if (webImage != null && webImage.startsWith('data:image')) {
      return compressAnimalPhotoDataUrl(webImage);
    }
  } catch (_) {
    // Fall through to the platform picker below.
  }

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
    allowMultiple: false,
    withData: true,
  );
  final file = result?.files.firstOrNull;
  Uint8List? bytes = file?.bytes;
  if ((bytes == null || bytes.isEmpty) && file?.readStream != null) {
    final chunks = <int>[];
    await for (final chunk in file!.readStream!) {
      chunks.addAll(chunk);
      if (chunks.length > 8 * 1024 * 1024) return null;
    }
    bytes = Uint8List.fromList(chunks);
  }
  if (file == null || bytes == null || bytes.isEmpty) return null;

  // Keeping photos bounded prevents a single camera image from making the
  // offline Hive database and every Firebase sync unnecessarily huge.
  if (bytes.lengthInBytes > 8 * 1024 * 1024) return null;

  return compressAnimalPhotoDataUrl(
    'data:image/jpeg;base64,${base64Encode(bytes)}',
  );
}

/// Phone camera images are often several megabytes, while a Firestore document
/// has a hard 1 MiB limit. Keep the local/cloud animal record comfortably below
/// that ceiling, without changing the visible profile quality.
Future<String?> compressAnimalPhotoDataUrl(String source) async {
  final comma = source.indexOf(',');
  if (comma < 0) return null;
  try {
    final bytes = base64Decode(source.substring(comma + 1));
    final compressed = await compute(_compressAnimalPhotoBytes, bytes);
    if (compressed == null || compressed.isEmpty) return null;
    return 'data:image/jpeg;base64,${base64Encode(compressed)}';
  } catch (_) {
    return null;
  }
}

Uint8List? _compressAnimalPhotoBytes(Uint8List bytes) {
  var decoded = image_lib.decodeImage(bytes);
  if (decoded == null) return null;
  decoded = image_lib.bakeOrientation(decoded);

  const maxSide = 960;
  if (decoded.width > maxSide || decoded.height > maxSide) {
    decoded = decoded.width >= decoded.height
        ? image_lib.copyResize(decoded, width: maxSide)
        : image_lib.copyResize(decoded, height: maxSide);
  }

  var quality = 78;
  var encoded = Uint8List.fromList(
    image_lib.encodeJpg(decoded, quality: quality),
  );
  // Base64 adds ~33%; target 430 KiB leaves generous room for animal fields.
  while (encoded.lengthInBytes > 430 * 1024 && quality > 52) {
    quality -= 8;
    encoded = Uint8List.fromList(
      image_lib.encodeJpg(decoded, quality: quality),
    );
  }
  if (encoded.lengthInBytes > 430 * 1024) {
    final smaller = decoded.width >= decoded.height
        ? image_lib.copyResize(decoded, width: 720)
        : image_lib.copyResize(decoded, height: 720);
    encoded = Uint8List.fromList(image_lib.encodeJpg(smaller, quality: 58));
  }
  return encoded.lengthInBytes <= 520 * 1024 ? encoded : null;
}

// =============================================================================
//  PART 2 — DESIGN SYSTEM
//  Golden-ratio tokens, palette, squircle geometry, Liquid Glass material
// =============================================================================

/// Every dimension in this app is derived from phi (the golden ratio) or from
/// the Fibonacci sequence, which converges on phi. No magic numbers.
class Gold {
  const Gold._();

  static const double phi = 1.618033988749895;
  static const double invPhi = 0.618033988749895;
  static const double sqrtPhi = 1.272019649514069;

  /// 1 - 1/phi. The "golden minor" — used for sheen height and split points.
  static const double minor = 0.381966011250105;

  // --- Fibonacci spacing ladder ---------------------------------------------
  // Whole steps are Fibonacci numbers. s16 and s27 are the sqrt(phi) half-steps
  // between 13-21 and 21-34, needed when a full step would be too coarse.
  static const double s2 = 2;
  static const double s3 = 3;
  static const double s5 = 5;
  static const double s8 = 8;
  static const double s13 = 13;
  static const double s16 = 16;
  static const double s21 = 21;
  static const double s27 = 27;
  static const double s34 = 34;
  static const double s55 = 55;
  static const double s89 = 89;

  // --- Corner radii (phi-stepped) -------------------------------------------
  static const double r8 = 8;
  static const double r13 = 13;
  static const double r21 = 21;
  static const double r27 = 27;
  static const double r34 = 34;
  static const double r55 = 55;

  // --- Type scale -----------------------------------------------------------
  // Base 13, stepped by sqrt(phi) and phi:
  // 13/phi = 8 · 13 = 13 · 13*sqrtPhi = 16.5 · 13*phi = 21
  // 21*sqrtPhi = 27 · 21*phi = 34 · 34*sqrtPhi = 43
  static const double t10 = 10;
  static const double t11 = 11;
  static const double t13 = 13;
  static const double t16 = 16;
  static const double t21 = 21;
  static const double t27 = 27;
  static const double t34 = 34;
  static const double t43 = 43;

  // --- Motion ---------------------------------------------------------------
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration ambient = Duration(milliseconds: 680);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve easeIn = Curves.easeInCubic;

  // --- Layout ---------------------------------------------------------------
  /// Phone-width content column. 377 is a Fibonacci number.
  static const double contentWidth = 377;

  /// Desktop-width content column for the main web workspace.
  static const double wideContentWidth = 987;

  /// Golden angle in radians (137.507°) — used to distribute sparkles so they
  /// never visually clump, the same way seeds pack in a sunflower head.
  static const double goldenAngle = 2.399963229728653;

  /// Apple's concentric-corner rule: an inner radius equals the outer radius
  /// minus the padding between them, so the two curves stay parallel.
  static double concentric(double outer, double pad) =>
      math.max(4.0, outer - pad);
}

/// Palette sampled directly from the approved VIMO screen designs.
class Ink {
  const Ink._();

  // Brand
  static const Color violet = Color(0xFF7C4DFF);
  static const Color violetDeep = Color(0xFF5B2EE0);
  static const Color violetDark = Color(0xFF4526B8);

  // Text
  static const Color navy = Color(0xFF231A5E);
  static const Color body = Color(0xFF2C2748);
  static const Color muted = Color(0xFF6E6A86);
  static const Color faint = Color(0xFF9A96B0);

  // Surfaces
  static const Color canvasTop = Color(0xFFF8F5FF);
  static const Color canvasMid = Color(0xFFF0E9FE);
  static const Color canvasLow = Color(0xFFFBF9FF);
  static const Color lavender = Color(0xFFEDE6FF);

  // Semantic
  static const Color green = Color(0xFF35A66B);
  static const Color amber = Color(0xFFF0A02A);
  static const Color red = Color(0xFFE1495B);
  static const Color blue = Color(0xFF4F6BFF);

  // Rank — read off the gold / purple / green cards in the reference design
  static const Color goldLight = Color(0xFFFBE08B);
  static const Color goldBase = Color(0xFFF2C13D);
  static const Color goldDeep = Color(0xFFDC9C1E);

  static const Color rankPurpleLight = Color(0xFFC6A9F7);
  static const Color rankPurpleBase = Color(0xFFA67FE8);
  static const Color rankPurpleDeep = Color(0xFF7F51D4);

  static const Color rankGreenLight = Color(0xFFC6E3A2);
  static const Color rankGreenBase = Color(0xFFA0C878);
  static const Color rankGreenDeep = Color(0xFF74A44C);
}

// -----------------------------------------------------------------------------
//  Squircle geometry
// -----------------------------------------------------------------------------

/// Builds a superellipse ("squircle") path.
///
/// A plain rounded rectangle joins its straight edges to a circular arc, which
/// leaves a visible curvature discontinuity at the join. Apple's shapes instead
/// ease into the corner over a longer run, so curvature changes continuously.
/// Extending the corner to 1.5x the radius along each edge and pulling the
/// control points to 0.55x reproduces that continuity closely, and keeps the
/// tangent parallel to the edge at both ends of every corner.
Path squirclePath(Rect rect, double radius) {
  final maxR = math.min(rect.width, rect.height) / 2;
  final r = radius.clamp(0.0, maxR).toDouble();
  if (r <= 0.01) return Path()..addRect(rect);

  // Corner run along the edge, clamped so opposite corners never overlap.
  final k = math.min(r * 1.5, maxR);
  // Control-point pull toward the corner.
  final c = r * 0.5523;

  return Path()
    ..moveTo(rect.left, rect.top + k)
    ..cubicTo(
      rect.left,
      rect.top + c,
      rect.left + c,
      rect.top,
      rect.left + k,
      rect.top,
    )
    ..lineTo(rect.right - k, rect.top)
    ..cubicTo(
      rect.right - c,
      rect.top,
      rect.right,
      rect.top + c,
      rect.right,
      rect.top + k,
    )
    ..lineTo(rect.right, rect.bottom - k)
    ..cubicTo(
      rect.right,
      rect.bottom - c,
      rect.right - c,
      rect.bottom,
      rect.right - k,
      rect.bottom,
    )
    ..lineTo(rect.left + k, rect.bottom)
    ..cubicTo(
      rect.left + c,
      rect.bottom,
      rect.left,
      rect.bottom - c,
      rect.left,
      rect.bottom - k,
    )
    ..close();
}

/// A [ShapeBorder] wrapper so squircles work with [ShapeDecoration], [Material]
/// and anything else that accepts a shape.
class SquircleBorder extends OutlinedBorder {
  final double radius;

  const SquircleBorder({this.radius = Gold.r27, super.side = BorderSide.none});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ShapeBorder scale(double t) =>
      SquircleBorder(radius: radius * t, side: side.scale(t));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      squirclePath(rect, radius);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => squirclePath(
    rect.deflate(side.width),
    math.max(0.0, radius - side.width),
  );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    canvas.drawPath(
      squirclePath(
        rect.deflate(side.width / 2),
        math.max(0.0, radius - side.width / 2),
      ),
      side.toPaint(),
    );
  }

  @override
  SquircleBorder copyWith({BorderSide? side, double? radius}) =>
      SquircleBorder(radius: radius ?? this.radius, side: side ?? this.side);

  @override
  bool operator ==(Object other) =>
      other is SquircleBorder && other.radius == radius && other.side == side;

  @override
  int get hashCode => Object.hash(radius, side);
}

class SquircleClipper extends CustomClipper<Path> {
  final double radius;
  const SquircleClipper(this.radius);

  @override
  Path getClip(Size size) => squirclePath(Offset.zero & size, radius);

  @override
  bool shouldReclip(covariant SquircleClipper oldClipper) =>
      oldClipper.radius != radius;
}

// -----------------------------------------------------------------------------
//  Liquid Glass material
// -----------------------------------------------------------------------------

/// Paints the specular rim and inner sheen that make a surface read as glass
/// rather than as flat translucent plastic.
///
/// Two things sell it: a rim that is brightest where a light source would graze
/// the top-left edge and picks up again on the opposite edge as a reflected
/// bounce, and a soft sheen filling the top [Gold.minor] (38.2%) of the surface.
class _GlassSkinPainter extends CustomPainter {
  final double radius;
  final double strength;
  final bool sheen;

  const _GlassSkinPainter({
    required this.radius,
    required this.strength,
    required this.sheen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final path = squirclePath(rect, radius);

    if (sheen) {
      final sheenRect = Rect.fromLTWH(
        0,
        0,
        size.width,
        size.height * Gold.minor,
      );
      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(
        sheenRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.34 * strength),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(sheenRect),
      );
      canvas.restore();
    }

    // Specular rim. Bright at the light-facing edge, nearly gone across the
    // middle, then a weaker bounce on the far edge.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.92 * strength),
            Colors.white.withValues(alpha: 0.28 * strength),
            Colors.white.withValues(alpha: 0.10 * strength),
            Colors.white.withValues(alpha: 0.52 * strength),
          ],
          stops: const [0.0, 0.32, 0.66, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassSkinPainter old) =>
      old.radius != radius || old.strength != strength || old.sheen != sheen;
}

/// The core surface of the app. A blurred, tinted squircle carrying a specular
/// rim, an inner sheen and layered depth shadows.
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final Color? tint;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double elevation;
  final double specular;
  final bool sheen;
  final Gradient? gradient;
  final VoidCallback? onTap;

  const Glass({
    super.key,
    required this.child,
    this.radius = Gold.r27,
    this.blur = 21,
    this.tint,
    this.opacity = 0.62,
    this.padding = const EdgeInsets.all(Gold.s21),
    this.margin,
    this.elevation = 1,
    this.specular = 1,
    this.sheen = true,
    this.gradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final base = tint ?? Colors.white;

    Widget surface = ClipPath(
      clipper: SquircleClipper(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: CustomPaint(
          foregroundPainter: _GlassSkinPainter(
            radius: radius,
            strength: specular,
            sheen: sheen,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient:
                  gradient ??
                  LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      base.withValues(alpha: opacity),
                      base.withValues(alpha: opacity * Gold.invPhi),
                    ],
                  ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );

    if (elevation > 0) {
      surface = DecoratedBox(
        decoration: ShapeDecoration(
          shape: SquircleBorder(radius: radius),
          shadows: [
            // Ambient occlusion — wide, soft, barely there.
            BoxShadow(
              color: Ink.violetDark.withValues(alpha: 0.07 * elevation),
              blurRadius: Gold.s34 * elevation,
              offset: Offset(0, Gold.s13 * elevation),
            ),
            // Key shadow — tighter and slightly darker.
            BoxShadow(
              color: Ink.violetDark.withValues(alpha: 0.05 * elevation),
              blurRadius: Gold.s13 * elevation,
              offset: Offset(0, Gold.s5 * elevation),
            ),
          ],
        ),
        child: surface,
      );
    }

    if (margin != null) {
      surface = Padding(padding: margin!, child: surface);
    }
    if (onTap != null) {
      surface = Pressable(radius: radius, onTap: onTap, child: surface);
    }
    return surface;
  }
}

/// Press feedback. Scales toward 1/phi of the usual travel and lifts a coloured
/// glow, so a tap feels like pressing into a soft physical surface.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final double depth;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.radius = Gold.r27,
    this.depth = 1,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        child: AnimatedScale(
          scale: _down ? 1 - (0.038 * widget.depth) : 1,
          duration: Gold.fast,
          curve: Gold.ease,
          child: AnimatedContainer(
            duration: Gold.base,
            curve: Gold.ease,
            decoration: ShapeDecoration(
              shape: SquircleBorder(radius: widget.radius),
              shadows: _down
                  ? [
                      BoxShadow(
                        color: Ink.violet.withValues(alpha: 0.20),
                        blurRadius: Gold.s21,
                        offset: const Offset(0, Gold.s8),
                      ),
                    ]
                  : const [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Background
// -----------------------------------------------------------------------------

/// The ambient canvas. Three slow-drifting colour fields sit under a heavy blur
/// so the glass above always has something with structure to refract.
class LiquidCanvas extends StatefulWidget {
  final Widget child;
  const LiquidCanvas({super.key, required this.child});

  @override
  State<LiquidCanvas> createState() => _LiquidCanvasState();
}

class _LiquidCanvasState extends State<LiquidCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 34))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Ink.canvasTop, Ink.canvasMid, Ink.canvasLow],
          stops: [0.0, Gold.invPhi, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) =>
                    CustomPaint(painter: _AuroraPainter(_c.value)),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  const _AuroraPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final tau = math.pi * 2;

    void field(Color color, double cx, double cy, double r, double phase) {
      final dx = math.cos(tau * (t + phase)) * size.width * 0.10;
      final dy = math.sin(tau * (t + phase) * Gold.invPhi) * size.height * 0.06;
      final center = Offset(size.width * cx + dx, size.height * cy + dy);
      final radius = size.shortestSide * r;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.42),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    field(const Color(0xFFB388FF), 0.08, 0.05, 0.52, 0.0);
    field(const Color(0xFFFFD9EC), 0.96, 0.24, 0.46, 0.33);
    field(const Color(0xFFCFE3FF), 0.28, 0.92, 0.50, 0.66);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t;
}

/// Constrains content to the golden content column and applies safe area.
class Shell extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const Shell({
    super.key,
    required this.child,
    this.maxWidth = Gold.contentWidth + Gold.s55,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidCanvas(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SafeArea(child: child),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Motion
// -----------------------------------------------------------------------------

/// Page transition: a short rise, a slight scale-up and a fade, all on one
/// curve so the whole surface reads as a single object arriving.
class LiquidRoute<T> extends PageRouteBuilder<T> {
  LiquidRoute({required WidgetBuilder builder})
    : super(
        transitionDuration: Gold.slow,
        reverseTransitionDuration: Gold.base,
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (context, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Gold.ease,
            reverseCurve: Gold.easeIn,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.034),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.968, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          );
        },
      );
}

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(LiquidRoute<T>(builder: (_) => page));

Future<T?> guardedPush<T>(
  BuildContext context, {
  required bool allowed,
  required String message,
  required Widget page,
}) {
  if (!allowed) {
    snack(context, message);
    return Future<T?>.value();
  }
  return push<T>(context, page);
}

/// Staggered entrance. Each item waits a Fibonacci-scaled beat longer than the
/// one before it, so a grid resolves as a wave rather than all at once.
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  final double rise;

  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.rise = 0.055,
  });

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Gold.ambient);

    // The stagger is an Interval inside one controller run rather than a
    // start-up delay. A delayed timer can fire while this element is briefly
    // detached -- during a tab switch or page transition -- and the callback is
    // then skipped for good, leaving the content stranded at zero opacity. A
    // controller started here always runs to completion, so the widget cannot
    // end up permanently invisible no matter what happens to the tree.
    final int step = widget.index < 0
        ? 0
        : (widget.index > 10 ? 10 : widget.index);
    final double begin = step * 0.055; // at most 0.55, so the interval is valid
    _t = CurvedAnimation(
      parent: _c,
      curve: Interval(begin, 1.0, curve: Gold.ease),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _t,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, widget.rise),
          end: Offset.zero,
        ).animate(_t),
        child: widget.child,
      ),
    );
  }
}

/// A number that cross-fades when it changes, so a stat updating never snaps.
class FlowText extends StatelessWidget {
  final String value;
  final TextStyle? style;

  const FlowText(this.value, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Gold.base,
      switchInCurve: Gold.ease,
      switchOutCurve: Gold.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.28),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Text(
        value,
        key: ValueKey<String>(value),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// =============================================================================
//  PART 3 — CONTROLS
// =============================================================================

/// Primary action. A gradient squircle with its own specular sheen so it reads
/// as the same material family as the glass around it.
class LiquidButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color start;
  final Color end;
  final double height;
  final double radius;
  final bool busy;

  const LiquidButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.start = Ink.violet,
    this.end = Ink.violetDeep,
    this.height = Gold.s55,
    this.radius = Gold.r21,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    return Pressable(
      radius: radius,
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: Gold.base,
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: height,
          decoration: ShapeDecoration(
            shape: SquircleBorder(radius: radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [start, end],
            ),
            shadows: [
              BoxShadow(
                color: start.withValues(alpha: 0.34),
                blurRadius: Gold.s21,
                offset: const Offset(0, Gold.s8),
              ),
            ],
          ),
          child: CustomPaint(
            foregroundPainter: _GlassSkinPainter(
              radius: radius,
              strength: 0.62,
              sheen: true,
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: Gold.s21,
                      height: Gold.s21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: Gold.s21),
                          const SizedBox(width: Gold.s8),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: Gold.t16,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary action — glass instead of gradient.
class GhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;

  const GhostButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.color = Ink.violetDeep,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Gold.r21,
      blur: 13,
      opacity: 0.50,
      elevation: 0.55,
      padding: const EdgeInsets.symmetric(
        horizontal: Gold.s21,
        vertical: Gold.s13,
      ),
      onTap: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: Gold.s21, color: color),
            const SizedBox(width: Gold.s8),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: Gold.t13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented control pill, as used for Cows / Calves and the period selector.
class Segment extends StatelessWidget {
  final String title;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  const Segment({
    super.key,
    required this.title,
    required this.active,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Gold.base,
          curve: Gold.ease,
          margin: const EdgeInsets.symmetric(horizontal: Gold.s3),
          padding: const EdgeInsets.symmetric(
            vertical: Gold.s13,
            horizontal: Gold.s8,
          ),
          decoration: ShapeDecoration(
            shape: SquircleBorder(radius: Gold.r21),
            gradient: active
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Ink.violet, Ink.violetDeep],
                  )
                : LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.72),
                      Colors.white.withValues(alpha: 0.44),
                    ],
                  ),
            shadows: active
                ? [
                    BoxShadow(
                      color: Ink.violet.withValues(alpha: 0.30),
                      blurRadius: Gold.s13,
                      offset: const Offset(0, Gold.s5),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: Gold.t16,
                  color: active ? Colors.white : Ink.muted,
                ),
                const SizedBox(width: Gold.s5),
              ],
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.white : Ink.body,
                    fontWeight: FontWeight.w800,
                    fontSize: Gold.t13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single sheet of glass that physically glides between choices. The moving
/// highlight stays mounted while the selected value changes, giving navigation
/// and filters the continuous Liquid Glass motion used by Apple interfaces.
class LiquidSegmentBar extends StatelessWidget {
  final List<String> labels;
  final List<IconData?>? icons;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;

  const LiquidSegmentBar({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.icons,
    this.height = Gold.s55 - Gold.s5,
  });

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final selected = index.clamp(0, labels.length - 1);

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = constraints.maxWidth / labels.length;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 460),
                curve: Curves.easeOutBack,
                left: selected * cellWidth + Gold.s2,
                width: math.max(0, cellWidth - Gold.s5),
                top: Gold.s2,
                bottom: Gold.s2,
                child: IgnorePointer(
                  child: Glass(
                    radius: Gold.r21,
                    blur: Gold.s21,
                    opacity: 0.58,
                    specular: 1.15,
                    elevation: 0.82,
                    padding: EdgeInsets.zero,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.74),
                        Ink.violet.withValues(alpha: 0.22),
                        Ink.violetDeep.withValues(alpha: 0.15),
                      ],
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Row(
                children: [
                  for (int i = 0; i < labels.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Gold.s5,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (icons != null &&
                                    i < icons!.length &&
                                    icons![i] != null) ...[
                                  AnimatedSwitcher(
                                    duration: Gold.fast,
                                    child: Icon(
                                      icons![i],
                                      key: ValueKey<bool>(selected == i),
                                      size: Gold.t16,
                                      color: selected == i
                                          ? Ink.violetDeep
                                          : Ink.faint,
                                    ),
                                  ),
                                  const SizedBox(width: Gold.s5),
                                ],
                                Flexible(
                                  child: AnimatedDefaultTextStyle(
                                    duration: Gold.base,
                                    curve: Gold.ease,
                                    style: TextStyle(
                                      color: selected == i
                                          ? Ink.violetDeep
                                          : Ink.body,
                                      fontWeight: selected == i
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                      fontSize: Gold.t13,
                                    ),
                                    child: Text(
                                      labels[i],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shared field styling. Fields are glass-filled with concentric corners.
InputDecoration fieldStyle(
  String label, {
  IconData? icon,
  Widget? prefix,
  Widget? suffix,
}) {
  OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Gold.r21),
    borderSide: BorderSide(color: c, width: w),
  );

  return InputDecoration(
    labelText: label,
    prefixIcon:
        prefix ??
        (icon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: Gold.s13, right: Gold.s8),
                child: Icon(icon, size: Gold.t21, color: Ink.violet),
              )),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix,
    labelStyle: const TextStyle(
      color: Ink.muted,
      fontWeight: FontWeight.w600,
      fontSize: Gold.t13,
    ),
    floatingLabelStyle: const TextStyle(
      color: Ink.violetDeep,
      fontWeight: FontWeight.w800,
    ),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.66),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: Gold.s21,
      vertical: Gold.s21,
    ),
    enabledBorder: border(Colors.white.withValues(alpha: 0.80), 1),
    focusedBorder: border(Ink.violet, 1.6),
    disabledBorder: border(Colors.white.withValues(alpha: 0.50), 1),
    errorBorder: border(Ink.red.withValues(alpha: 0.70), 1.2),
    focusedErrorBorder: border(Ink.red, 1.6),
  );
}

void snack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Ink.navy.withValues(alpha: 0.94),
      elevation: 0,
      margin: const EdgeInsets.all(Gold.s21),
      duration: const Duration(milliseconds: 2600),
      shape: const SquircleBorder(radius: Gold.r21),
    ),
  );
}

// =============================================================================
//  ICON SYSTEM
// =============================================================================

/// Domain icons are drawn as live paths rather than shipped as bitmaps, so they
/// stay crisp at any size and can be recoloured freely. Geometry is expressed
/// in fractions of the icon box, keeping every proportion resolution-free.
class RanchIcon extends StatelessWidget {
  final String type;
  final double size;
  final Color color;
  final double weight;

  const RanchIcon({
    super.key,
    required this.type,
    this.size = Gold.s21,
    this.color = Ink.violet,
    this.weight = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    if (type == 'cow' || type == 'calf') {
      return CowMark(size: size);
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RanchIconPainter(type: type, color: color, weight: weight),
      ),
    );
  }
}

class _RanchIconPainter extends CustomPainter {
  final String type;
  final Color color;
  final double weight;

  const _RanchIconPainter({
    required this.type,
    required this.color,
    required this.weight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight * (s / 24)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (type) {
      case 'milk':
        _milkCan(canvas, s, stroke);
        break;
      case 'bottle':
        _bottle(canvas, s, stroke);
        break;
      case 'bag':
        _sack(canvas, s, stroke);
        break;
      case 'dryGrass':
        _hay(canvas, s, stroke);
        break;
      case 'freshGrass':
        _fodder(canvas, s, stroke);
        break;
      case 'doctor':
        _stethoscope(canvas, s, stroke);
        break;
      case 'hoof':
        _hoof(canvas, s);
        break;
      default:
        _milkCan(canvas, s, stroke);
    }
  }

  // A traditional milk churn: tapered shoulder, banded body, lidded neck.
  void _milkCan(Canvas canvas, double s, Paint p) {
    final neck = Rect.fromLTWH(s * 0.38, s * 0.10, s * 0.24, s * 0.11);
    canvas.drawPath(squirclePath(neck, s * 0.035), p);

    final body = Path()
      ..moveTo(s * 0.38, s * 0.21)
      ..cubicTo(s * 0.36, s * 0.30, s * 0.24, s * 0.32, s * 0.24, s * 0.46)
      ..lineTo(s * 0.24, s * 0.80)
      ..cubicTo(s * 0.24, s * 0.88, s * 0.30, s * 0.90, s * 0.38, s * 0.90)
      ..lineTo(s * 0.62, s * 0.90)
      ..cubicTo(s * 0.70, s * 0.90, s * 0.76, s * 0.88, s * 0.76, s * 0.80)
      ..lineTo(s * 0.76, s * 0.46)
      ..cubicTo(s * 0.76, s * 0.32, s * 0.64, s * 0.30, s * 0.62, s * 0.21)
      ..close();
    canvas.drawPath(body, p);

    // Two hoops, placed at the golden split of the body height.
    final top = s * 0.32;
    final bottom = s * 0.90;
    final span = bottom - top;
    canvas.drawLine(
      Offset(s * 0.245, top + span * Gold.minor),
      Offset(s * 0.755, top + span * Gold.minor),
      p,
    );
    canvas.drawLine(
      Offset(s * 0.245, top + span * Gold.invPhi),
      Offset(s * 0.755, top + span * Gold.invPhi),
      p,
    );
  }

  void _bottle(Canvas canvas, double s, Paint p) {
    canvas.drawPath(
      squirclePath(
        Rect.fromLTWH(s * 0.40, s * 0.08, s * 0.20, s * 0.10),
        s * 0.03,
      ),
      p,
    );
    final body = Path()
      ..moveTo(s * 0.40, s * 0.18)
      ..cubicTo(s * 0.40, s * 0.28, s * 0.29, s * 0.30, s * 0.29, s * 0.42)
      ..lineTo(s * 0.29, s * 0.84)
      ..cubicTo(s * 0.29, s * 0.90, s * 0.33, s * 0.92, s * 0.39, s * 0.92)
      ..lineTo(s * 0.61, s * 0.92)
      ..cubicTo(s * 0.67, s * 0.92, s * 0.71, s * 0.90, s * 0.71, s * 0.84)
      ..lineTo(s * 0.71, s * 0.42)
      ..cubicTo(s * 0.71, s * 0.30, s * 0.60, s * 0.28, s * 0.60, s * 0.18)
      ..close();
    canvas.drawPath(body, p);
    // Fill line at the golden split.
    canvas.drawLine(
      Offset(s * 0.295, s * 0.42 + (s * 0.50) * Gold.minor),
      Offset(s * 0.705, s * 0.42 + (s * 0.50) * Gold.minor),
      p,
    );
  }

  // Grain sack with a rolled-open collar.
  void _sack(Canvas canvas, double s, Paint p) {
    final body = Path()
      ..moveTo(s * 0.28, s * 0.34)
      ..cubicTo(s * 0.22, s * 0.56, s * 0.20, s * 0.74, s * 0.24, s * 0.86)
      ..cubicTo(s * 0.26, s * 0.92, s * 0.74, s * 0.92, s * 0.76, s * 0.86)
      ..cubicTo(s * 0.80, s * 0.74, s * 0.78, s * 0.56, s * 0.72, s * 0.34)
      ..close();
    canvas.drawPath(body, p);

    final collar = Path()
      ..moveTo(s * 0.28, s * 0.34)
      ..cubicTo(s * 0.30, s * 0.22, s * 0.70, s * 0.22, s * 0.72, s * 0.34)
      ..cubicTo(s * 0.66, s * 0.40, s * 0.34, s * 0.40, s * 0.28, s * 0.34)
      ..close();
    canvas.drawPath(collar, p);

    // Grain specks, spaced by the golden angle so they never grid up.
    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 3; i++) {
      final a = i * Gold.goldenAngle;
      canvas.drawCircle(
        Offset(
          s * 0.50 + math.cos(a) * s * 0.10,
          s * 0.29 + math.sin(a) * s * 0.03,
        ),
        s * 0.018,
        dot,
      );
    }
  }

  // Bundled straw, fanned from a single tie point.
  void _hay(Canvas canvas, double s, Paint p) {
    const stalks = 5;
    for (int i = 0; i < stalks; i++) {
      final f = (i / (stalks - 1)) - 0.5;
      final topX = s * (0.50 + f * 0.62);
      final topY = s * (0.16 + f.abs() * 0.10);
      canvas.drawLine(Offset(s * 0.50, s * 0.86), Offset(topX, topY), p);
      // Seed head.
      canvas.drawLine(
        Offset(topX, topY),
        Offset(topX + (f >= 0 ? s * 0.05 : -s * 0.05), topY + s * 0.09),
        p,
      );
    }
    // Tie band.
    canvas.drawLine(Offset(s * 0.36, s * 0.70), Offset(s * 0.64, s * 0.70), p);
    canvas.drawLine(Offset(s * 0.37, s * 0.77), Offset(s * 0.63, s * 0.77), p);
  }

  // Fresh fodder: a central stem with leaves alternating at golden spacing.
  void _fodder(Canvas canvas, double s, Paint p) {
    canvas.drawLine(Offset(s * 0.50, s * 0.90), Offset(s * 0.50, s * 0.18), p);
    void leaf(double baseY, double dir, double reach) {
      canvas.drawPath(
        Path()
          ..moveTo(s * 0.50, s * baseY)
          ..quadraticBezierTo(
            s * (0.50 + dir * reach * 0.62),
            s * (baseY - reach * 0.50),
            s * (0.50 + dir * reach),
            s * (baseY - reach * 0.86),
          ),
        p,
      );
    }

    leaf(0.42, -1, 0.30);
    leaf(0.50, 1, 0.32);
    leaf(0.64, -1, 0.26);
    leaf(0.72, 1, 0.28);
  }

  void _stethoscope(Canvas canvas, double s, Paint p) {
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.26, s * 0.14)
        ..lineTo(s * 0.26, s * 0.42)
        ..cubicTo(s * 0.26, s * 0.62, s * 0.56, s * 0.62, s * 0.56, s * 0.42)
        ..lineTo(s * 0.56, s * 0.14),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.41, s * 0.60)
        ..lineTo(s * 0.41, s * 0.70)
        ..cubicTo(s * 0.41, s * 0.82, s * 0.74, s * 0.82, s * 0.74, s * 0.70),
      p,
    );
    canvas.drawCircle(Offset(s * 0.74, s * 0.60), s * 0.10, p);
  }

  // A cloven bovine hoof print: two broad, inward-curving halves based on a
  // real cow hoof rather than the generic cat/dog paw used by icon fonts.
  void _hoof(Canvas canvas, double s) {
    final bounds = Rect.fromLTWH(0, 0, s, s);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: 0.82), color],
      ).createShader(bounds);

    Path half() {
      return Path()
        ..moveTo(s * 0.44, s * 0.10)
        ..cubicTo(s * 0.25, s * 0.08, s * 0.10, s * 0.27, s * 0.11, s * 0.55)
        ..cubicTo(s * 0.12, s * 0.79, s * 0.27, s * 0.92, s * 0.41, s * 0.86)
        ..cubicTo(s * 0.50, s * 0.82, s * 0.49, s * 0.68, s * 0.43, s * 0.57)
        ..cubicTo(s * 0.35, s * 0.43, s * 0.35, s * 0.26, s * 0.44, s * 0.10)
        ..close();
    }

    final left = half();
    canvas.drawPath(left, fill);
    canvas.save();
    canvas.translate(s, 0);
    canvas.scale(-1, 1);
    canvas.drawPath(left, fill);
    canvas.restore();

    final gleam = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.22, s * 0.29)
        ..quadraticBezierTo(s * 0.27, s * 0.18, s * 0.36, s * 0.16),
      gleam,
    );
  }

  @override
  bool shouldRepaint(covariant _RanchIconPainter old) =>
      old.type != type || old.color != color || old.weight != weight;
}

// =============================================================================
//  PART 4 — DATA + BUSINESS LOGIC
// =============================================================================

const List<String> breeds = [
  'HF Cross',
  'Jersey Cross',
  'Kangeyam',
  'Gir',
  'Sahiwal',
  'Red Sindhi',
  'Native Cow',
  'Other',
];

const List<String> semenTypes = [
  'HF Semen',
  'Jersey Semen',
  'Gir Semen',
  'Sahiwal Semen',
  'Native Breed Semen',
  'Other',
];

const List<String> deathReasons = [
  'Old Age',
  'Disease',
  'Accident',
  'Delivery Problem',
  'Unknown',
  'Other',
];

const List<String> periods = ['Today', 'This Week', 'This Month', 'This Year'];

const List<String> familyRoles = ['Admin', 'Editor', 'Basic Entry', 'Viewer'];

// --- primitives --------------------------------------------------------------

String two(int n) => n.toString().padLeft(2, '0');

String todayDate() {
  final n = DateTime.now();
  return '${n.year}-${two(n.month)}-${two(n.day)}';
}

String currentTime() {
  final n = DateTime.now();
  return '${two(n.hour)}:${two(n.minute)}';
}

String thisMonth() {
  final n = DateTime.now();
  return '${n.year}-${two(n.month)}';
}

String thisYear() => DateTime.now().year.toString();

double toDouble(String s) => double.tryParse(s.trim()) ?? 0.0;

int toInt(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

Map<String, dynamic> asMap(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

Map<String, dynamic> withKey(dynamic key, dynamic value) => {
  ...asMap(value),
  'key': key,
};

String txt(Map<String, dynamic> m, String k, [String d = '']) {
  final v = m[k];
  if (v == null) return d;
  final s = '$v';
  return s.trim().isEmpty || s == 'null' ? d : s;
}

double numv(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0.0;
}

String csv(dynamic v) => '"${'$v'.replaceAll('"', '""')}"';

// --- settings ----------------------------------------------------------------

dynamic settingValue(String key, dynamic fallback) {
  if (!Hive.isBoxOpen('settings')) return fallback;
  return Hive.box('settings').get(key, defaultValue: fallback);
}

String settingText(String key, String fallback) =>
    '${settingValue(key, fallback)}';

Future<void> setSetting(String key, dynamic value) async {
  if (Hive.isBoxOpen('settings')) await Hive.box('settings').put(key, value);
}

String appName() => settingText('appName', 'VIMO');
String farmName() => settingText('farmName', 'My Ranch');
String ownerName() => settingText('ownerName', '');
String placeName() => settingText('place', '');
String currencySymbol() => settingText('currency', '\u20b9');
String currentUserName() {
  final stored = settingText('currentUser', '').trim();
  if (stored.isNotEmpty) return stored;
  final email = FirebaseAuth.instance.currentUser?.email ?? '';
  return email.contains('@') ? email.split('@').first : 'Ranch Member';
}

String currentUserRole() =>
    normalizeFamilyRole(settingText('currentRole', 'Viewer'));

bool get canManageRanch => currentUserRole() == 'Admin';
bool get canEditAnimals =>
    const {'Admin', 'Editor'}.contains(currentUserRole());
bool get canRecordEntries =>
    const {'Admin', 'Editor', 'Basic Entry'}.contains(currentUserRole());
bool get canViewRanch => ranchId().isNotEmpty;

bool autoSyncEnabled() => settingValue('autoSyncEnabled', true) == true;
bool pendingSync() => settingValue('pendingSync', false) == true;
int pendingSyncCount() => toInt(settingValue('pendingSyncCount', 0));

String ranchId() =>
    settingText('ranchId', '').replaceAll(' ', '_').toLowerCase();

String pendingRanchId() =>
    settingText('pendingRanchId', '').replaceAll(' ', '_').toLowerCase();

String normalizeRanchId(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
    .replaceAll(RegExp(r'_+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

String? ranchIdValidationError(String value) {
  final id = normalizeRanchId(value);
  if (id.length < 4) return 'Use at least 4 characters';
  if (id.length > 24) return 'Use no more than 24 characters';
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
    return 'Start with a letter; use letters, numbers and underscore only';
  }
  if (const {
    'admin',
    'support',
    'vimo',
    'system',
    'settings',
    'new_ranch',
  }.contains(id)) {
    return 'That Ranch ID is reserved';
  }
  return null;
}

double defaultMilkPrice() {
  final value = settingValue('defaultMilkPrice', 60.0);
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 60.0;
}

String money(num amount) => '${currencySymbol()}${amount.toStringAsFixed(0)}';

String deviceId() {
  if (!Hive.isBoxOpen('settings')) return 'device';
  final box = Hive.box('settings');
  final current = '${box.get('deviceId', defaultValue: '')}';
  if (current.trim().isNotEmpty) return current;
  final id = 'dev_${DateTime.now().microsecondsSinceEpoch}';
  box.put('deviceId', id);
  return id;
}

String compactDateTime(String iso) {
  if (iso.trim().isEmpty) return 'Never';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return 'Today ${two(d.hour)}:${two(d.minute)}';
  }
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String lastSyncedText() => compactDateTime(settingText('lastSyncedAt', ''));

String cloudSafeId(String input) {
  final cleaned = input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'item' : cleaned;
}

String makeRecordId(
  String boxName,
  String localKey,
  Map<String, dynamic> data,
) {
  final existing = txt(data, 'cloudId');
  if (existing.isNotEmpty) return existing;
  if (boxName == 'animals' && txt(data, 'id').isNotEmpty) {
    return 'animal_${cloudSafeId(txt(data, 'id'))}';
  }
  final created = txt(data, 'createdAt', DateTime.now().toIso8601String());
  final seed =
      '${boxName}_${deviceId()}_${created}_${localKey}_${DateTime.now().microsecondsSinceEpoch}';
  return cloudSafeId(seed);
}

final BrowserRuntime _browserRuntime = BrowserRuntime();

bool isOnlineNow() => _browserRuntime.online;

// --- collections -------------------------------------------------------------

List<Map<String, dynamic>> boxRows(String boxName) => Hive.box(
  boxName,
).toMap().entries.map((e) => withKey(e.key, e.value)).toList();

List<Map<String, dynamic>> rows(String boxName) =>
    Hive.box(boxName).values.map(asMap).toList().reversed.toList();

int animalFreshness(Map<String, dynamic> animal) {
  final millis = toInt(animal['updatedAtMillis']);
  if (millis > 0) return millis;
  final text = txt(animal, 'updatedAtText', txt(animal, 'createdAt'));
  return DateTime.tryParse(text)?.millisecondsSinceEpoch ?? 0;
}

List<Map<String, dynamic>> deduplicateAnimals(
  Iterable<Map<String, dynamic>> source,
) {
  // Older cloud builds could download the same animal under both a legacy
  // numeric document id and its newer stable cloud id. Keep the newest copy in
  // the UI without deleting either local record, so no user data is lost.
  final unique = <String, Map<String, dynamic>>{};
  for (final animal in source) {
    final type = txt(animal, 'type').toLowerCase();
    final id = txt(animal, 'id').trim().toLowerCase();
    final name = txt(animal, 'name').trim().toLowerCase();
    final identity = '$type|${id.isNotEmpty ? id : name}';
    final existing = unique[identity];
    if (existing == null ||
        animalFreshness(animal) >= animalFreshness(existing)) {
      unique[identity] = animal;
    }
  }
  return unique.values.toList();
}

List<Map<String, dynamic>> animals({bool all = false}) {
  final list = deduplicateAnimals(boxRows('animals'));
  if (all) return list;
  return list.where((a) => txt(a, 'status', 'Active') == 'Active').toList();
}

List<Map<String, dynamic>> animalsBy(String type, {bool all = false}) =>
    animals(all: all).where((a) => txt(a, 'type') == type).toList();

bool isActiveAnimal(Map<String, dynamic> animal) =>
    txt(animal, 'status', 'Active') == 'Active';

List<String> cowNames() {
  final seen = <String>{};
  final result = <String>[];
  for (final animal in animalsBy('cow')) {
    final name = txt(animal, 'name').trim();
    if (name.isNotEmpty && seen.add(name.toLowerCase())) result.add(name);
  }
  return result;
}

List<String> motherNames() => ['Unknown Mother', ...cowNames()];

List<Map<String, dynamic>> milkRows() => rows('milk_records');
List<Map<String, dynamic>> foodRows() => rows('food_records');
List<Map<String, dynamic>> stockRows() => rows('stock_records');
List<Map<String, dynamic>> expenseRows() => rows('expense_records');
List<Map<String, dynamic>> doctorRows() => rows('doctor_records');
List<Map<String, dynamic>> purchaseRows() => rows('purchase_records');
List<Map<String, dynamic>> saleRows() => rows('sale_records');
List<Map<String, dynamic>> deathRows() => rows('death_records');
List<Map<String, dynamic>> calvingRows() => rows('calving_records');

String nextId(String type) {
  final prefix = type == 'cow' ? 'C' : 'K';
  int max = 0;
  for (final a in animalsBy(type, all: true)) {
    final id = txt(a, 'id');
    if (id.startsWith(prefix)) {
      final n = int.tryParse(id.substring(1)) ?? 0;
      if (n > max) max = n;
    }
  }
  return '$prefix${(max + 1).toString().padLeft(3, '0')}';
}

void updateAnimal(Map<String, dynamic> animal, Map<String, dynamic> updates) {
  final key = animal['key'];
  if (key == null) return;
  final box = Hive.box('animals');
  final raw = box.get(key);
  if (raw == null) return;
  final data = asMap(raw);
  data.addAll(updates);
  box.put(key, data);
}

// --- dates and age -----------------------------------------------------------

/// Calendar-accurate age. Borrowing from the previous month uses that month's
/// real length rather than a flat 30, so the day count is never off.
String ageFromDob(String dob) {
  if (dob.isEmpty) return '';
  final b = DateTime.tryParse(dob);
  if (b == null) return '';
  final n = DateTime.now();

  int y = n.year - b.year;
  int m = n.month - b.month;
  int d = n.day - b.day;

  if (d < 0) {
    m--;
    // Day 0 of the current month resolves to the last day of the previous one.
    d += DateTime(n.year, n.month, 0).day;
  }
  if (m < 0) {
    y--;
    m += 12;
  }

  if (y > 0) return '$y Years $m Months';
  if (m > 0) return '$m Months $d Days';
  return '$d Days';
}

String ageText(Map<String, dynamic> a) {
  final fromDob = ageFromDob(txt(a, 'dob'));
  if (fromDob.isNotEmpty) return fromDob;

  final y = toInt(a['ageYears']);
  final m = toInt(a['ageMonths']);
  final d = toInt(a['ageDays']);
  final parts = <String>[];
  if (y > 0) parts.add('$y Years');
  if (m > 0) parts.add('$m Months');
  if (d > 0) parts.add('$d Days');
  return parts.isEmpty ? 'Not set' : parts.join(' ');
}

/// Compact age for the ranking cards, e.g. "4.2 Y".
String ageShort(Map<String, dynamic> a) {
  final dob = DateTime.tryParse(txt(a, 'dob'));
  if (dob != null) {
    final days = DateTime.now().difference(dob).inDays;
    if (days < 0) return '0 Y';
    if (days < 62) return '$days D';
    if (days < 365) return '${(days / 30.44).toStringAsFixed(0)} M';
    return '${(days / 365.25).toStringAsFixed(1)} Y';
  }
  final y = toInt(a['ageYears']);
  final m = toInt(a['ageMonths']);
  final d = toInt(a['ageDays']);
  if (y > 0) return m > 0 ? '${(y + m / 12).toStringAsFixed(1)} Y' : '$y Y';
  if (m > 0) return '$m M';
  if (d > 0) return '$d D';
  return '--';
}

int daysSince(String date) {
  final d = DateTime.tryParse(date);
  if (d == null) return 0;
  return DateTime.now().difference(d).inDays;
}

String durationText(String date) {
  if (date.isEmpty) return 'Not set';
  final days = daysSince(date);
  if (days <= 0) return 'Today';
  if (days < 30) return '$days days';
  final months = days ~/ 30;
  if (months < 12) return '$months months ${days % 30} days';
  return '${months ~/ 12} years ${months % 12} months';
}

bool matchPeriod(String date, String period) {
  if (period == 'Today') return date == todayDate();
  if (period == 'This Month') return date.startsWith(thisMonth());
  if (period == 'This Year') return date.startsWith(thisYear());
  if (period == 'This Week') {
    final d = DateTime.tryParse(date);
    if (d == null) return false;
    final diff = DateTime.now().difference(d).inDays;
    return diff >= 0 && diff <= 6;
  }
  return true;
}

DateTime activityDate(Map<String, dynamic> r) {
  final created = DateTime.tryParse(txt(r, 'createdAt'));
  if (created != null) return created;
  final withTime = DateTime.tryParse(
    '${txt(r, 'date')} ${txt(r, 'time', '00:00')}',
  );
  if (withTime != null) return withTime;
  return DateTime.tryParse(txt(r, 'date')) ?? DateTime(2000);
}

// --- totals ------------------------------------------------------------------

double sumPeriod(List<Map<String, dynamic>> list, String key, String period) {
  double total = 0;
  for (final r in list) {
    if (matchPeriod(txt(r, 'date'), period)) total += numv(r, key);
  }
  return total;
}

double milkTotal(String period) => sumPeriod(milkRows(), 'quantity', period);
double foodExpense(String period) => sumPeriod(foodRows(), 'price', period);
double stockPurchaseExpense(String period) {
  double total = 0;
  for (final record in stockRows()) {
    if (txt(record, 'movement') == 'Purchase' &&
        matchPeriod(txt(record, 'date'), period)) {
      total += numv(record, 'amount');
    }
  }
  return total;
}

double otherExpense(String period) =>
    sumPeriod(expenseRows(), 'amount', period);
double doctorExpense(String period) => sumPeriod(doctorRows(), 'cost', period);
double purchaseExpense(String period) =>
    sumPeriod(purchaseRows(), 'amount', period);
double deathExpense(String period) => sumPeriod(deathRows(), 'cost', period);
double saleIncome(String period) => sumPeriod(saleRows(), 'amount', period);

double totalExpense(String period) =>
    foodExpense(period) +
    stockPurchaseExpense(period) +
    otherExpense(period) +
    doctorExpense(period) +
    purchaseExpense(period) +
    deathExpense(period);

double profit(String period) => saleIncome(period) - totalExpense(period);

double stockBalanceFrom(Iterable<Map<String, dynamic>> records, String item) {
  double total = 0;
  for (final record in records) {
    if (txt(record, 'item') != item) continue;
    final quantity = numv(record, 'quantityKg');
    total += txt(record, 'movement') == 'Usage' ? -quantity : quantity;
  }
  return math.max(0, total);
}

double stockBalance(String item) => stockBalanceFrom(stockRows(), item);

/// Suggestions are ranked by how often they were used, then by most recent
/// use. This makes the everyday petrol/customer names rise to the top while
/// still keeping older choices available.
List<String> frequentNameSuggestions(
  Iterable<Map<String, dynamic>> records,
  String key, {
  bool Function(Map<String, dynamic>)? where,
}) {
  final counts = <String, int>{};
  final labels = <String, String>{};
  final latest = <String, DateTime>{};
  for (final record in records) {
    if (where != null && !where(record)) continue;
    final label = txt(record, key).trim();
    if (label.isEmpty) continue;
    final normalized = label.toLowerCase();
    counts[normalized] = (counts[normalized] ?? 0) + 1;
    labels[normalized] = label;
    final stamp = activityDate(record);
    if (latest[normalized] == null || stamp.isAfter(latest[normalized]!)) {
      latest[normalized] = stamp;
    }
  }
  final names = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      if (byCount != 0) return byCount;
      final byRecent = latest[b]!.compareTo(latest[a]!);
      if (byRecent != 0) return byRecent;
      return labels[a]!.toLowerCase().compareTo(labels[b]!.toLowerCase());
    });
  return names.map((key) => labels[key]!).toList();
}

double? lastMilkQuantityForCustomerFrom(
  Iterable<Map<String, dynamic>> records,
  String customer,
) {
  final wanted = customer.trim().toLowerCase();
  if (wanted.isEmpty) return null;
  final matches = records.where(
    (record) =>
        txt(record, 'type') == 'Milk' &&
        txt(record, 'customerName').trim().toLowerCase() == wanted,
  );
  if (matches.isEmpty) return null;
  final sorted = matches.toList()
    ..sort((a, b) => activityDate(b).compareTo(activityDate(a)));
  final quantity = numv(sorted.first, 'quantity');
  return quantity > 0 ? quantity : null;
}

double? lastMilkQuantityForCustomer(String customer) =>
    lastMilkQuantityForCustomerFrom(saleRows(), customer);

double milkSold(String period) {
  double total = 0;
  for (final r in saleRows()) {
    final saleType = txt(r, 'type');
    final category = txt(r, 'category');
    if (matchPeriod(txt(r, 'date'), period) &&
        (saleType == 'Milk' || category == 'Milk Sale')) {
      total += numv(r, 'quantity');
    }
  }
  return total;
}

double availableMilk(String period) {
  final balance = milkTotal(period) - milkSold(period);
  return balance < 0 ? 0 : balance;
}

int pregnantCowCount() => animals()
    .where(
      (a) =>
          txt(a, 'gender', 'Female') == 'Female' &&
          txt(a, 'pregnancyStartDate').isNotEmpty,
    )
    .length;

Map<String, dynamic> motherAfterCalving(
  Map<String, dynamic> mother, {
  required String cowId,
  required String calfName,
  required String calfId,
  required String birthDate,
  required String birthTime,
}) {
  final wasCalf = txt(mother, 'type') == 'calf';
  return {
    ...mother,
    'type': 'cow',
    'id': cowId,
    'previousCalfId': wasCalf
        ? txt(mother, 'id')
        : txt(mother, 'previousCalfId'),
    'promotedFromCalf': wasCalf,
    'promotionDate': wasCalf ? birthDate : txt(mother, 'promotionDate'),
    'pregnancyStartDate': '',
    'pregnancyInjection': '',
    'milkingStopDate': '',
    'milkingStartDate': birthDate,
    'lactationStatus': 'Milking',
    'status': 'Active',
    'lastCalvingDate': birthDate,
    'lastCalvingTime': birthTime,
    'lastCalfName': calfName,
    'lastCalfId': calfId,
  };
}

double cowMilkToday(String name) {
  double total = 0;
  for (final r in milkRows()) {
    if (txt(r, 'cow') == name && txt(r, 'date') == todayDate()) {
      total += numv(r, 'quantity');
    }
  }
  return total;
}

double cowMilkForPeriod(String cowName, String period) {
  double total = 0;
  for (final r in milkRows()) {
    if (txt(r, 'cow') == cowName && matchPeriod(txt(r, 'date'), period)) {
      total += numv(r, 'quantity');
    }
  }
  return total;
}

String lastDoctor(String name) {
  final list = doctorRows().where((r) => txt(r, 'cow') == name).toList();
  return list.isEmpty ? 'No visit' : txt(list.first, 'date');
}

List<Map<String, dynamic>> calvesOf(String mother) =>
    animalsBy('calf').where((a) => txt(a, 'mother') == mother).toList();

/// Number of recorded calvings — shown as "Lactation" on the ranking cards.
int lactationCount(String cowName) =>
    calvingRows().where((r) => txt(r, 'mother') == cowName).length;

/// A display status derived from the breeding fields, so the profile can show
/// Pregnant or Dry without those being stored as a separate state to keep in
/// sync with the underlying dates.
String displayStatus(Map<String, dynamic> a) {
  final status = txt(a, 'status', 'Active');
  if (status != 'Active') return status;
  if (txt(a, 'milkingStopDate').isNotEmpty) return 'Dry';
  if (txt(a, 'pregnancyStartDate').isNotEmpty) return 'Pregnant';
  return 'Active';
}

Color statusColor(String status) {
  switch (status) {
    case 'Sold':
      return Ink.amber;
    case 'Died':
      return Ink.red;
    case 'Pregnant':
      return Ink.violet;
    case 'Dry':
      return Ink.blue;
    default:
      return Ink.green;
  }
}

// --- ranking -----------------------------------------------------------------

/// Top cows by milk for the period. Only active cows compete, and the window
/// resets naturally each month because the period filter is date-based.
List<Map<String, dynamic>> topCowRankings({
  int limit = 3,
  String period = 'This Month',
}) {
  final list = <Map<String, dynamic>>[];
  for (final cow in animalsBy('cow')) {
    list.add({...cow, 'rankMilk': cowMilkForPeriod(txt(cow, 'name'), period)});
  }
  list.sort((a, b) {
    final byMilk = numv(b, 'rankMilk').compareTo(numv(a, 'rankMilk'));
    if (byMilk != 0) return byMilk;
    return txt(a, 'name').compareTo(txt(b, 'name'));
  });
  // A cow with no milk this month has not earned a place on the podium.
  return list.where((c) => numv(c, 'rankMilk') > 0).take(limit).toList();
}

int cowRank(String cowName, {String period = 'This Month'}) {
  final ranks = topCowRankings(limit: 3, period: period);
  for (var i = 0; i < ranks.length; i++) {
    if (txt(ranks[i], 'name') == cowName) return i + 1;
  }
  return 0;
}

List<Color> rankPalette(int rank) {
  if (rank == 1) return const [Ink.goldLight, Ink.goldBase, Ink.goldDeep];
  if (rank == 2) {
    return const [Ink.rankPurpleLight, Ink.rankPurpleBase, Ink.rankPurpleDeep];
  }
  if (rank == 3) {
    return const [Ink.rankGreenLight, Ink.rankGreenBase, Ink.rankGreenDeep];
  }
  return const [Colors.white, Colors.white, Colors.white];
}

String rankBackgroundAsset(int rank) {
  if (rank == 1) return 'assets/images/rank_gold.jpg';
  if (rank == 2) return 'assets/images/rank_purple.jpg';
  return 'assets/images/rank_green.jpg';
}

Color rankColor(int rank) => rankPalette(rank)[1];

String rankLabel(int rank) {
  if (rank == 1) return 'Gold Champion';
  if (rank == 2) return 'Purple Star';
  if (rank == 3) return 'Green Star';
  return '';
}

// --- birthdays ---------------------------------------------------------------

/// Sold and died animals never celebrate a birthday.
bool isBirthdayToday(Map<String, dynamic> animal) {
  if (!isActiveAnimal(animal)) return false;
  final dob = DateTime.tryParse(txt(animal, 'dob'));
  if (dob == null) return false;
  final now = DateTime.now();
  return dob.month == now.month && dob.day == now.day;
}

List<Map<String, dynamic>> birthdayAnimalsToday() {
  final result = animals(all: true).where(isBirthdayToday).toList();
  result.sort((a, b) => txt(a, 'name').compareTo(txt(b, 'name')));
  return result;
}

/// The animal the dashboard hero should celebrate today, if any.
Map<String, dynamic>? birthdayHeroAnimal() {
  final list = birthdayAnimalsToday();
  return list.isEmpty ? null : list.first;
}

int birthdayAgeYears(Map<String, dynamic> a) {
  final dob = DateTime.tryParse(txt(a, 'dob'));
  if (dob == null) return 0;
  final now = DateTime.now();
  var years = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
    years--;
  }
  return years < 0 ? 0 : years;
}

/// Decodes whichever image an animal carries — an uploaded data URL or a remote
/// URL — into something [Image] can display. Returns null when there is none.
ImageProvider? animalImage(Map<String, dynamic> animal) {
  final data = txt(animal, 'imageData');
  if (data.startsWith('data:image')) {
    try {
      return MemoryImage(base64Decode(data.split(',').last));
    } catch (_) {
      return null;
    }
  }
  final url = txt(animal, 'imageUrl');
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return NetworkImage(url);
  }
  return null;
}

class _AnimalPortrait extends StatelessWidget {
  final Map<String, dynamic> animal;
  final double size;

  const _AnimalPortrait({required this.animal, required this.size});

  @override
  Widget build(BuildContext context) {
    final provider = animalImage(animal);
    final fallback = Center(child: CowMark(size: size * 0.62));

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Ink.lavender,
      ),
      clipBehavior: Clip.antiAlias,
      child: provider == null
          ? fallback
          : Image(
              image: provider,
              width: size,
              height: size,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

// --- recent activity ---------------------------------------------------------

List<Map<String, dynamic>> recentActivities({int limit = 6}) {
  final list = <Map<String, dynamic>>[];

  for (final r in milkRows()) {
    list.add({
      'title': 'Milk recorded for ${txt(r, 'cow')}',
      'sub': '${txt(r, 'date')} \u2022 ${txt(r, 'time')}',
      'value': '${numv(r, 'quantity').toStringAsFixed(1)} L',
      'icon': Icons.water_drop_rounded,
      'color': Ink.violet,
      'sort': activityDate(r),
    });
  }
  for (final r in foodRows()) {
    list.add({
      'title': 'Feed added',
      'sub':
          '${cleanFoodLabel(txt(r, 'foodLabel', txt(r, 'foodType')))} \u2022 ${txt(r, 'date')}',
      'value': money(numv(r, 'price')),
      'icon': Icons.grass_rounded,
      'color': Ink.green,
      'sort': activityDate(r),
    });
  }
  for (final r in stockRows()) {
    list.add({
      'title': '${txt(r, 'item')} ${txt(r, 'movement').toLowerCase()}',
      'sub': '${txt(r, 'date')} \u2022 ${txt(r, 'target', 'Stock')}',
      'value': '${numv(r, 'quantityKg').toStringAsFixed(1)} kg',
      'icon': Icons.inventory_2_rounded,
      'color': txt(r, 'movement') == 'Usage' ? Ink.amber : Ink.green,
      'sort': activityDate(r),
    });
  }
  for (final r in expenseRows()) {
    list.add({
      'title': '${txt(r, 'name')} expense',
      'sub': '${txt(r, 'date')} \u2022 Others',
      'value': money(numv(r, 'amount')),
      'icon': Icons.receipt_long_rounded,
      'color': Ink.red,
      'sort': activityDate(r),
    });
  }
  for (final r in doctorRows()) {
    list.add({
      'title': 'Health record for ${txt(r, 'cow')}',
      'sub': '${txt(r, 'type')} \u2022 ${txt(r, 'date')}',
      'value': money(numv(r, 'cost')),
      'icon': Icons.medical_services_rounded,
      'color': Ink.blue,
      'sort': activityDate(r),
    });
  }
  for (final r in saleRows()) {
    list.add({
      'title': '${txt(r, 'category', 'Sale')} saved',
      'sub': '${txt(r, 'animal')} \u2022 ${txt(r, 'date')}',
      'value': money(numv(r, 'amount')),
      'icon': Icons.sell_rounded,
      'color': Ink.green,
      'sort': activityDate(r),
    });
  }
  for (final r in calvingRows()) {
    list.add({
      'title': 'New calf born',
      'sub': '${txt(r, 'calfName')} \u2022 Mother ${txt(r, 'mother')}',
      'value': txt(r, 'date'),
      'icon': Icons.child_care_rounded,
      'color': Ink.amber,
      'sort': activityDate(r),
    });
  }

  list.sort((a, b) => (b['sort'] as DateTime).compareTo(a['sort'] as DateTime));
  return list.take(limit).toList();
}

Future<String?> chooseDate(BuildContext context, String current) async {
  final initial = DateTime.tryParse(current) ?? DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(1990),
    lastDate: DateTime(2100),
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: Ink.violet,
          onPrimary: Colors.white,
          onSurface: Ink.navy,
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    ),
  );
  if (picked == null) return null;
  return '${picked.year}-${two(picked.month)}-${two(picked.day)}';
}

// =============================================================================
//  PART 5 — CLOUD SYNC
// =============================================================================

enum RanchGateMode { active, onboarding, waiting }

class RanchGateState {
  final RanchGateMode mode;
  final String ranchId;
  final String role;

  const RanchGateState(this.mode, {this.ranchId = '', this.role = ''});
}

class RanchAccessService {
  const RanchAccessService._();

  static FirebaseFirestore get db => FirebaseFirestore.instance;
  static User? get user => FirebaseAuth.instance.currentUser;
  static String get uid => user?.uid ?? '';

  static DocumentReference<Map<String, dynamic>> ranchRef(String id) =>
      db.collection('ranches').doc(normalizeRanchId(id));

  static DocumentReference<Map<String, dynamic>> memberRef(
    String id,
    String memberUid,
  ) => ranchRef(id).collection('members').doc(memberUid);

  static DocumentReference<Map<String, dynamic>> requestRef(
    String id,
    String memberUid,
  ) => ranchRef(id).collection('join_requests').doc(memberUid);

  static DocumentReference<Map<String, dynamic>> get userRef =>
      db.collection('users').doc(uid);

  static String displayNameFor(User value) {
    final display = value.displayName?.trim() ?? '';
    if (display.isNotEmpty) return display;
    final email = value.email ?? '';
    if (email.contains('@')) return email.split('@').first;
    return 'Ranch Member';
  }

  static Future<void> clearLocalRanchData() async {
    AutoSyncService.beginRemoteWrite();
    try {
      for (final boxName in backupBoxNames) {
        if (boxName == 'settings' || !Hive.isBoxOpen(boxName)) continue;
        await Hive.box(boxName).clear();
      }
    } finally {
      AutoSyncService.endRemoteWrite();
    }
  }

  static Future<void> _prepareUserSession() async {
    final current = user;
    if (current == null || !Hive.isBoxOpen('settings')) return;
    final storedUid = settingText('firebaseUid', '').trim();

    if (storedUid.isNotEmpty && storedUid != current.uid) {
      await clearLocalRanchData();
      await setSetting('ranchId', '');
      await setSetting('pendingRanchId', '');
      await setSetting('currentRole', '');
      await setSetting('farmName', 'My Ranch');
      await setSetting('ownerName', '');
      await setSetting('place', '');
    }

    await setSetting('firebaseUid', current.uid);
    if (settingText('currentUser', '').trim().isEmpty ||
        storedUid != current.uid) {
      await setSetting('currentUser', displayNameFor(current));
    }
  }

  static bool _activeMember(Map<String, dynamic>? data) =>
      data != null &&
      data['active'] != false &&
      txt(data, 'status', 'active') == 'active';

  static Future<Map<String, dynamic>?> _membership(String id) async {
    if (uid.isEmpty || id.isEmpty) return null;
    final snap = await memberRef(id, uid).get();
    if (!snap.exists || !_activeMember(snap.data())) return null;
    return Map<String, dynamic>.from(snap.data()!);
  }

  static Future<Map<String, dynamic>?> _claimLegacyRanch(String id) async {
    final current = user;
    if (current == null || id.isEmpty) return null;
    final normalized = normalizeRanchId(id);
    final ranch = ranchRef(normalized);
    final registry = db.collection('ranch_ids').doc(normalized);
    final member = memberRef(normalized, current.uid);

    return db.runTransaction<Map<String, dynamic>?>((transaction) async {
      final ranchSnap = await transaction.get(ranch);
      final registrySnap = await transaction.get(registry);
      if (ranchSnap.exists) {
        final data = ranchSnap.data() ?? <String, dynamic>{};
        final owner = txt(data, 'ownerUid', txt(data, 'authUid'));
        if (owner.isNotEmpty && owner != current.uid) return null;
      }
      if (registrySnap.exists &&
          txt(registrySnap.data() ?? <String, dynamic>{}, 'ownerUid') !=
              current.uid) {
        return null;
      }

      final now = FieldValue.serverTimestamp();
      if (!ranchSnap.exists) {
        transaction.set(ranch, {
          'ranchId': normalized,
          'farmName': farmName(),
          'ownerName': ownerName().isEmpty
              ? displayNameFor(current)
              : ownerName(),
          'place': placeName(),
          'ownerUid': current.uid,
          'createdAt': now,
          'updatedAt': now,
        });
      } else {
        transaction.set(ranch, {
          'ownerUid': current.uid,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }
      transaction.set(registry, {
        'ranchId': normalized,
        'farmName': farmName(),
        'ownerUid': current.uid,
        'createdAt': now,
      }, SetOptions(merge: true));
      final memberData = <String, dynamic>{
        'uid': current.uid,
        'name': displayNameFor(current),
        'email': current.email ?? '',
        'role': 'Admin',
        'status': 'active',
        'active': true,
        'joinedAt': now,
      };
      transaction.set(member, memberData, SetOptions(merge: true));
      transaction.set(userRef, {
        'uid': current.uid,
        'email': current.email ?? '',
        'displayName': displayNameFor(current),
        'currentRanchId': normalized,
        'pendingRanchId': '',
        'updatedAt': now,
      }, SetOptions(merge: true));
      return memberData;
    });
  }

  static Future<void> activate(
    String id,
    Map<String, dynamic> member, {
    bool download = true,
  }) async {
    final normalized = normalizeRanchId(id);
    final old = ranchId();
    if (old.isNotEmpty && old != normalized) {
      await clearLocalRanchData();
    }
    await setSetting('ranchId', normalized);
    await setSetting('pendingRanchId', '');
    await setSetting(
      'currentRole',
      normalizeFamilyRole(txt(member, 'role', 'Viewer')),
    );
    await setSetting(
      'currentUser',
      txt(
        member,
        'name',
        user == null ? 'Ranch Member' : displayNameFor(user!),
      ),
    );
    await setSetting('syncStatus', 'Waiting to sync');
    final current = user;
    if (current != null) {
      await userRef.set({
        'uid': current.uid,
        'email': current.email ?? '',
        'displayName': txt(member, 'name', displayNameFor(current)),
        'currentRanchId': normalized,
        'pendingRanchId': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    final ranchSnap = await ranchRef(normalized).get();
    final ranch = ranchSnap.data();
    if (ranch != null) {
      await setSetting('farmName', txt(ranch, 'farmName', 'My Ranch'));
      await setSetting('ownerName', txt(ranch, 'ownerName'));
      await setSetting('place', txt(ranch, 'place'));
    }
    if (download && CloudSyncService.ready) {
      // Ranch access must never hold the user on a loading page while every
      // record downloads. Enter immediately, then hydrate data in background.
      unawaited(_hydrateActivatedRanch());
    }
  }

  static Future<void> _hydrateActivatedRanch() async {
    try {
      await setSetting('syncStatus', 'Downloading ranch data...');
      await CloudSyncService.downloadAll().timeout(const Duration(seconds: 30));
      await setSetting('syncStatus', 'Synced');
    } catch (error) {
      await setSetting('syncStatus', 'Will retry automatically');
      await setSetting('lastSyncError', '$error');
      AutoSyncService.scheduleSync(reason: 'ranch hydration retry');
    }
  }

  static Future<RanchGateState> resolve() async {
    final current = user;
    if (current == null) {
      return const RanchGateState(RanchGateMode.onboarding);
    }
    await _prepareUserSession();

    final localId = ranchId();
    if (localId.isNotEmpty) {
      var member = await _membership(localId);
      member ??= await _claimLegacyRanch(localId);
      if (member != null) {
        await activate(localId, member, download: false);
        return RanchGateState(
          RanchGateMode.active,
          ranchId: localId,
          role: normalizeFamilyRole(txt(member, 'role', 'Viewer')),
        );
      }
      await setSetting('ranchId', '');
      await setSetting('currentRole', '');
    }

    final profile = (await userRef.get()).data();
    final profileRanch = normalizeRanchId(
      txt(profile ?? <String, dynamic>{}, 'currentRanchId'),
    );
    if (profileRanch.isNotEmpty) {
      final member = await _membership(profileRanch);
      if (member != null) {
        await activate(profileRanch, member);
        return RanchGateState(
          RanchGateMode.active,
          ranchId: profileRanch,
          role: normalizeFamilyRole(txt(member, 'role', 'Viewer')),
        );
      }
    }

    final pending = normalizeRanchId(
      pendingRanchId().isNotEmpty
          ? pendingRanchId()
          : txt(profile ?? <String, dynamic>{}, 'pendingRanchId'),
    );
    if (pending.isNotEmpty) {
      await setSetting('pendingRanchId', pending);
      return RanchGateState(RanchGateMode.waiting, ranchId: pending);
    }
    return const RanchGateState(RanchGateMode.onboarding);
  }

  static Future<void> createRanch({
    required String requestedId,
    required String farm,
    required String owner,
    required String place,
  }) async {
    final current = user;
    if (current == null) throw StateError('Please sign in again');
    final id = normalizeRanchId(requestedId);
    final validation = ranchIdValidationError(id);
    if (validation != null) throw StateError(validation);
    final registry = db.collection('ranch_ids').doc(id);
    final ranch = ranchRef(id);
    final member = memberRef(id, current.uid);

    await db.runTransaction((transaction) async {
      final existing = await transaction.get(registry);
      if (existing.exists) {
        throw StateError('Ranch ID "$id" is already taken');
      }
      final now = FieldValue.serverTimestamp();
      transaction.set(registry, {
        'ranchId': id,
        'farmName': farm,
        'ownerUid': current.uid,
        'createdAt': now,
      });
      transaction.set(ranch, {
        'ranchId': id,
        'farmName': farm,
        'ownerName': owner,
        'place': place,
        'ownerUid': current.uid,
        'createdAt': now,
        'updatedAt': now,
      });
      transaction.set(member, {
        'uid': current.uid,
        'name': owner,
        'email': current.email ?? '',
        'role': 'Admin',
        'status': 'active',
        'active': true,
        'joinedAt': now,
      });
      transaction.set(userRef, {
        'uid': current.uid,
        'email': current.email ?? '',
        'displayName': owner,
        'currentRanchId': id,
        'pendingRanchId': '',
        'updatedAt': now,
      }, SetOptions(merge: true));
    });

    await clearLocalRanchData();
    await setSetting('farmName', farm);
    await setSetting('ownerName', owner);
    await setSetting('place', place);
    await activate(id, {
      'name': owner,
      'role': 'Admin',
      'status': 'active',
      'active': true,
    }, download: false);
  }

  static Future<String> requestToJoin({
    required String requestedId,
    required String name,
  }) async {
    final current = user;
    if (current == null) throw StateError('Please sign in again');
    final id = normalizeRanchId(requestedId);
    final validation = ranchIdValidationError(id);
    if (validation != null) throw StateError(validation);
    final registry = await db.collection('ranch_ids').doc(id).get();
    if (!registry.exists) throw StateError('No ranch exists with ID "$id"');

    await clearLocalRanchData();
    final batch = db.batch();
    batch.set(requestRef(id, current.uid), {
      'uid': current.uid,
      'name': name,
      'email': current.email ?? '',
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(userRef, {
      'uid': current.uid,
      'email': current.email ?? '',
      'displayName': name,
      'currentRanchId': '',
      'pendingRanchId': id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    final delivered = await requestRef(id, current.uid).get();
    if (!delivered.exists ||
        txt(delivered.data() ?? {}, 'status') != 'pending') {
      throw StateError('Join request could not be delivered. Please try again');
    }
    await setSetting('ranchId', '');
    await setSetting('pendingRanchId', id);
    await setSetting('currentUser', name);
    await setSetting('currentRole', '');
    return txt(registry.data() ?? <String, dynamic>{}, 'farmName', id);
  }

  static Future<void> cancelJoinRequest(String id) async {
    if (uid.isEmpty) return;
    final batch = db.batch();
    batch.delete(requestRef(id, uid));
    batch.set(userRef, {
      'pendingRanchId': '',
      'currentRanchId': '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    await setSetting('pendingRanchId', '');
    await setSetting('ranchId', '');
    await setSetting('currentRole', '');
  }

  static Future<void> approveRequest(
    String id,
    Map<String, dynamic> request, {
    String role = 'Basic Entry',
  }) async {
    if (!canManageRanch) throw StateError('Admin permission required');
    final memberUid = txt(request, 'uid');
    if (memberUid.isEmpty) throw StateError('Invalid join request');
    final normalizedRole = normalizeFamilyRole(role);
    final batch = db.batch();
    batch.set(memberRef(id, memberUid), {
      'uid': memberUid,
      'name': txt(request, 'name', 'Ranch Member'),
      'email': txt(request, 'email'),
      'role': normalizedRole,
      'status': 'active',
      'active': true,
      'joinedAt': FieldValue.serverTimestamp(),
      'approvedBy': uid,
    });
    batch.set(requestRef(id, memberUid), {
      ...request,
      'status': 'approved',
      'role': normalizedRole,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': uid,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  static Future<void> rejectRequest(
    String id,
    Map<String, dynamic> request,
  ) async {
    if (!canManageRanch) throw StateError('Admin permission required');
    final memberUid = txt(request, 'uid');
    if (memberUid.isEmpty) return;
    final batch = db.batch();
    batch.set(requestRef(id, memberUid), {
      ...request,
      'status': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': uid,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  static Future<void> updateMemberRole(
    String id,
    String memberUid,
    String role,
  ) async {
    if (!canManageRanch) throw StateError('Admin permission required');
    if (memberUid == uid) {
      throw StateError('You cannot change your own admin role');
    }
    await memberRef(id, memberUid).update({
      'role': normalizeFamilyRole(role),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    });
  }

  static Future<void> removeMember(String id, String memberUid) async {
    if (!canManageRanch) throw StateError('Admin permission required');
    if (memberUid == uid) throw StateError('You cannot remove yourself');
    await memberRef(id, memberUid).delete();
  }
}

class CloudSyncService {
  const CloudSyncService._();

  static const Set<String> localOnlySettings = {
    'ranchId',
    'pendingRanchId',
    'firebaseUid',
    'currentUser',
    'currentRole',
    'deviceId',
    'pendingSync',
    'pendingSyncCount',
    'syncStatus',
    'lastSyncError',
    'lastSyncedAt',
    'lastAutoSyncReason',
  };

  static FirebaseFirestore get db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> get ranch =>
      db.collection('ranches').doc(ranchId());

  static bool get ready =>
      firebaseReady &&
      FirebaseAuth.instance.currentUser != null &&
      ranchId().isNotEmpty;

  static Future<void> uploadAll() async {
    if (!ready) return;

    if (canManageRanch) {
      await ranch.set({
        'appName': appName(),
        'farmName': farmName(),
        'ownerName': ownerName(),
        'place': placeName(),
        'autoSyncEnabled': autoSyncEnabled(),
        'lastLocalSyncAttempt': DateTime.now().toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUserName(),
        'ownerUid': FirebaseAuth.instance.currentUser?.uid ?? '',
      }, SetOptions(merge: true));
    }

    for (final boxName in backupBoxNames) {
      await uploadBox(boxName);
    }
  }

  static Future<void> uploadBox(String boxName) async {
    if (!ready || !Hive.isBoxOpen(boxName)) return;
    if ((boxName == 'settings' || boxName == 'family_users') &&
        !canManageRanch) {
      return;
    }
    const animalEditBoxes = {
      'animals',
      'purchase_records',
      'death_records',
      'calving_records',
    };
    if (animalEditBoxes.contains(boxName) && !canEditAnimals) return;
    if (!{'settings', 'family_users', ...animalEditBoxes}.contains(boxName) &&
        !canRecordEntries) {
      return;
    }

    final col = ranch.collection(boxName);
    final box = Hive.box(boxName);
    WriteBatch batch = db.batch();
    int count = 0;

    Future<void> flushIfFull() async {
      // Firestore caps a batch at 500 writes; stop well short of it.
      if (count >= 400) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }

    for (final entry in box.toMap().entries) {
      if (boxName == 'settings') {
        if (localOnlySettings.contains('${entry.key}')) continue;
        batch.set(col.doc('${entry.key}'), {
          'settingKey': '${entry.key}',
          'value': entry.value,
          'updatedBy': currentUserName(),
          'updatedAtText': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
        count++;
      } else if (entry.value is Map) {
        final data = Map<String, dynamic>.from(entry.value as Map);
        if (boxName == 'sale_records' &&
            !canEditAnimals &&
            {'Cow', 'Calf'}.contains(txt(data, 'type'))) {
          continue;
        }
        final docId = makeRecordId(boxName, '${entry.key}', data);
        final now = DateTime.now();
        data['cloudId'] = docId;
        data['deviceKey'] = '${entry.key}';
        data['updatedBy'] = currentUserName();
        data['updatedAtText'] = txt(
          data,
          'updatedAtText',
          now.toIso8601String(),
        );
        if (toInt(data['updatedAtMillis']) <= 0) {
          data['updatedAtMillis'] = now.millisecondsSinceEpoch;
        }
        if (txt(data, 'createdAt').isEmpty) {
          data['createdAt'] = now.toIso8601String();
        }

        // Last-write-wins guard. A device coming back online must not replace
        // a newer edit that another family member has already synced.
        final remote = await col.doc(docId).get();
        final remoteMillis = toInt(remote.data()?['updatedAtMillis']);
        final localMillis = toInt(data['updatedAtMillis']);
        if (remote.exists && remoteMillis > localMillis) {
          final newerRemote = Map<String, dynamic>.from(remote.data()!);
          newerRemote['cloudId'] = docId;
          AutoSyncService.beginRemoteWrite();
          try {
            await box.put(entry.key, newerRemote);
          } finally {
            AutoSyncService.endRemoteWrite();
          }
          continue;
        }
        data['pendingUpload'] = false;

        // Stamp the cloud id back onto the local record so the next download
        // can match this row instead of duplicating it.
        final existingLocal = asMap(entry.value);
        if (txt(existingLocal, 'cloudId') != docId ||
            existingLocal['pendingUpload'] == true) {
          AutoSyncService.beginRemoteWrite();
          try {
            await box.put(entry.key, data);
          } finally {
            AutoSyncService.endRemoteWrite();
          }
        }

        // Older builds keyed documents by the raw Hive index. Remove that
        // stale document so the record does not appear twice in the cloud.
        final legacyId = '${entry.key}';
        if (legacyId != docId) {
          batch.delete(col.doc(legacyId));
          count++;
          await flushIfFull();
        }

        batch.set(col.doc(docId), data, SetOptions(merge: true));
        count++;
      } else {
        batch.set(col.doc('${entry.key}'), {
          'value': entry.value,
          'updatedBy': currentUserName(),
          'updatedAtText': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
        count++;
      }

      await flushIfFull();
    }

    if (count > 0) await batch.commit();
  }

  static Future<void> downloadAll() async {
    if (!ready) return;
    for (final boxName in backupBoxNames) {
      await downloadBox(boxName);
    }
    // Older cloud builds could store one family member under several keys.
    // Compact those legacy rows after every download so the UI and the next
    // upload both contain one person only.
    AutoSyncService.beginRemoteWrite();
    try {
      await normalizeFamilyUsers();
    } finally {
      AutoSyncService.endRemoteWrite();
    }
  }

  /// Merges the cloud copy into the local box.
  ///
  /// Clearing the box and re-adding everything would reassign every Hive key,
  /// which breaks any screen holding an old key and silently drops local rows
  /// that have not been uploaded yet. Matching on cloudId instead keeps local
  /// keys stable, and only deletes rows that were previously synced and have
  /// since disappeared from the cloud. Anything still waiting to upload has no
  /// cloudId, so it is always preserved.
  static Future<void> downloadBox(String boxName) async {
    if (!ready || !Hive.isBoxOpen(boxName)) return;

    final snap = await ranch.collection(boxName).get();
    final box = Hive.box(boxName);

    AutoSyncService.beginRemoteWrite();
    try {
      if (boxName == 'settings') {
        for (final doc in snap.docs) {
          if (localOnlySettings.contains(doc.id)) continue;
          final data = Map<String, dynamic>.from(doc.data());
          if (data.containsKey('value')) {
            await box.put(doc.id, data['value']);
          }
        }
        return;
      }

      final keyByCloudId = <String, dynamic>{};
      for (final entry in box.toMap().entries) {
        if (entry.value is Map) {
          final cid = txt(
            Map<String, dynamic>.from(entry.value as Map),
            'cloudId',
          );
          if (cid.isNotEmpty) keyByCloudId[cid] = entry.key;
        }
      }

      for (final doc in snap.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data.remove('updatedAt');
        data.remove('settingKey');
        final cid = txt(data, 'cloudId', doc.id);
        data['cloudId'] = cid;
        final localKey = keyByCloudId[cid];
        if (localKey != null) {
          final local = asMap(box.get(localKey));
          final localMillis = toInt(local['updatedAtMillis']);
          final remoteMillis = toInt(data['updatedAtMillis']);
          if (localMillis > remoteMillis) {
            continue;
          }
          await box.put(localKey, data);
        } else {
          await box.add(data);
        }
      }
    } finally {
      AutoSyncService.endRemoteWrite();
    }
  }

  static Future<Map<String, int>> cloudCounts() async {
    final result = <String, int>{};
    if (!ready) return result;
    for (final boxName in backupBoxNames) {
      result[boxName] = (await ranch.collection(boxName).get()).size;
    }
    return result;
  }
}

class AutoSyncService {
  const AutoSyncService._();

  static Timer? _periodic;
  static Timer? _debounce;
  static bool _started = false;
  static bool _syncing = false;

  /// Depth counter, not a plain flag, because remote writes nest: uploadBox may
  /// stamp a record while downloadBox is already applying a batch. A boolean
  /// would be cleared by the inner call and let the outer one leak change
  /// events back into the dirty tracker.
  static int _remoteDepth = 0;

  static final List<StreamSubscription<dynamic>> _subscriptions = [];

  static void beginRemoteWrite() => _remoteDepth++;
  static void endRemoteWrite() {
    if (_remoteDepth > 0) _remoteDepth--;
  }

  static bool get _applyingRemote => _remoteDepth > 0;

  static void start() {
    if (_started) return;
    _started = true;

    for (final boxName in backupBoxNames) {
      if (!Hive.isBoxOpen(boxName)) continue;
      _subscriptions.add(
        Hive.box(boxName).watch().listen((event) {
          if (boxName == 'settings') return;
          // Only writes we are ourselves making from the cloud are ignored.
          // Edits made at any other moment, including while an upload is in
          // flight, still mark the store dirty so they cannot be lost.
          if (_applyingRemote) return;

          if (event.value is Map) {
            final data = Map<String, dynamic>.from(event.value as Map);
            final now = DateTime.now();
            if (txt(data, 'cloudId').isEmpty) {
              data['cloudId'] = makeRecordId(boxName, '${event.key}', data);
              data['createdAt'] = txt(data, 'createdAt', now.toIso8601String());
            }
            data['updatedAtMillis'] = now.millisecondsSinceEpoch;
            data['updatedAtText'] = now.toIso8601String();
            data['pendingUpload'] = true;
            beginRemoteWrite();
            Hive.box(boxName).put(event.key, data).whenComplete(endRemoteWrite);
          }

          markDirty(reason: 'local change', quiet: true);
        }),
      );
    }

    if (firebaseReady) {
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) scheduleSync(reason: 'login');
      });
    }

    _browserRuntime.start(
      onOnline: () => scheduleSync(reason: 'network back'),
      onFocus: () => scheduleSync(reason: 'app focus'),
    );

    _periodic = Timer.periodic(
      const Duration(hours: 4),
      (_) => scheduleSync(reason: '4 hour auto sync'),
    );
    Timer(const Duration(seconds: 4), () => scheduleSync(reason: 'app open'));
  }

  static void stop() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _periodic?.cancel();
    _debounce?.cancel();
    _browserRuntime.stop();
    _started = false;
  }

  static void markDirty({String reason = 'local change', bool quiet = false}) {
    if (!Hive.isBoxOpen('settings')) return;
    final box = Hive.box('settings');
    box.put('pendingSync', true);
    box.put('pendingSyncCount', pendingSyncCount() + 1);
    box.put('syncStatus', 'Waiting to sync');
    box.put('lastAutoSyncReason', reason);

    if (!quiet) {
      scheduleSync(reason: reason);
    } else if (isOnlineNow()) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 8), () => run(reason: reason));
    }
  }

  static void scheduleSync({String reason = 'auto'}) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => run(reason: reason));
  }

  static Future<void> run({String reason = 'auto'}) async {
    if (_syncing) return;
    if (!autoSyncEnabled()) return;
    if (!firebaseReady) return;
    if (!Hive.isBoxOpen('settings')) return;

    final settings = Hive.box('settings');

    if (!isOnlineNow()) {
      await settings.put('syncStatus', 'Offline - waiting for network');
      await settings.put('lastAutoSyncReason', reason);
      return;
    }
    if (FirebaseAuth.instance.currentUser == null) return;

    _syncing = true;
    try {
      await settings.put('syncStatus', 'Syncing...');
      await settings.put('lastAutoSyncReason', reason);

      await CloudSyncService.uploadAll().timeout(const Duration(seconds: 45));
      await CloudSyncService.downloadAll().timeout(const Duration(seconds: 45));

      await settings.put('pendingSync', false);
      await settings.put('pendingSyncCount', 0);
      await settings.put('lastSyncedAt', DateTime.now().toIso8601String());
      await settings.put('syncStatus', 'Synced');
    } catch (e) {
      await settings.put('syncStatus', 'Sync failed');
      await settings.put('lastSyncError', '$e');
    } finally {
      _syncing = false;
    }
  }
}

// =============================================================================
//  PART 6 — SHARED COMPONENTS
// =============================================================================

/// The ranch scene, artwork only. Carries no lettering, so any wording placed
/// over it is drawn as real text and stays sharp at every size.
const AssetImage heroArtImage = AssetImage(
  'assets/images/vimo_hero_perfect.jpg',
);

/// The VIMO app mark.
const AssetImage vimoIconImage = AssetImage('assets/images/vimo_logo_v3.png');

/// The house cow mark, used wherever a cow or calf needs representing.
class CowMark extends StatelessWidget {
  final double size;
  const CowMark({super.key, this.size = Gold.s21});

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/cow_mark.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    gaplessPlayback: true,
  );
}

/// Reusable cloven cow-hoof mark without its own background. The surrounding
/// control already provides the Liquid Glass surface.
class CowHoofIcon extends StatelessWidget {
  final double size;
  final Color color;

  const CowHoofIcon({
    super.key,
    this.size = Gold.s34,
    this.color = Ink.violetDeep,
  });

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Center(
      child: RanchIcon(type: 'hoof', color: color, size: size * 0.74),
    ),
  );
}

// -----------------------------------------------------------------------------
//  Rosette
// -----------------------------------------------------------------------------

/// The place medal on a ranking card: a ribboned disc carrying the rank number.
class Rosette extends StatelessWidget {
  final int rank;
  final double size;

  const Rosette({super.key, required this.rank, this.size = Gold.s34});

  @override
  Widget build(BuildContext context) {
    final palette = rankPalette(rank);
    return SizedBox(
      width: size,
      height: size * Gold.sqrtPhi,
      child: CustomPaint(
        painter: _RosettePainter(palette: palette),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: size,
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.46,
                  height: 1,
                  shadows: [
                    Shadow(
                      color: palette[2].withValues(alpha: 0.62),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RosettePainter extends CustomPainter {
  final List<Color> palette;
  const _RosettePainter({required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final d = size.width;
    final r = d / 2;
    final center = Offset(r, r);

    // Ribbon tails first, so the disc overlaps them.
    final ribbon = Paint()..color = const Color(0xFFE8743C);
    final ribbonDark = Paint()..color = const Color(0xFFC85A28);

    canvas.drawPath(
      Path()
        ..moveTo(r * 0.55, d * 0.72)
        ..lineTo(r * 0.20, size.height)
        ..lineTo(r * 0.86, size.height * 0.90)
        ..close(),
      ribbonDark,
    );
    canvas.drawPath(
      Path()
        ..moveTo(r * 1.45, d * 0.72)
        ..lineTo(r * 1.80, size.height)
        ..lineTo(r * 1.14, size.height * 0.90)
        ..close(),
      ribbon,
    );

    // Scalloped outer edge — twelve lobes, the classic award silhouette.
    final scallop = Paint()..color = palette[0];
    const lobes = 12;
    for (int i = 0; i < lobes; i++) {
      final a = (i / lobes) * math.pi * 2;
      canvas.drawCircle(
        Offset(
          center.dx + math.cos(a) * r * 0.80,
          center.dy + math.sin(a) * r * 0.80,
        ),
        r * 0.26,
        scallop,
      );
    }

    // Disc.
    canvas.drawCircle(
      center,
      r * 0.84,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette[0], palette[1], palette[2]],
          stops: const [0.0, Gold.invPhi, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r * 0.84)),
    );

    // Inner bevel ring.
    canvas.drawCircle(
      center,
      r * 0.64,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.09
        ..color = Colors.white.withValues(alpha: 0.42),
    );

    // Specular pip at the light-facing shoulder.
    canvas.drawCircle(
      Offset(center.dx - r * 0.30, center.dy - r * 0.34),
      r * 0.16,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _RosettePainter old) => old.palette != palette;
}

// -----------------------------------------------------------------------------
//  Rank texture
// -----------------------------------------------------------------------------

/// Animated sheen and fine grain placed over the user's metallic rank texture.
class RankTexturePainter extends CustomPainter {
  final int rank;
  final double progress;

  const RankTexturePainter({required this.rank, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.12),
          ],
          stops: const [0.0, Gold.invPhi, 1.0],
        ).createShader(rect),
    );

    // Sheen bands drifting across the surface.
    for (int i = 0; i < 2; i++) {
      final phase = (progress + i * Gold.invPhi) % 1.0;
      final x = -size.width + phase * size.width * 2;
      final band = Rect.fromLTWH(x, 0, size.width * Gold.minor, size.height);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.0),
              Colors.white.withValues(alpha: i == 0 ? 0.20 : 0.11),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(band),
      );
    }

    // Fine grain. The golden angle keeps the scatter even at any count.
    final speck = Paint();
    for (int i = 0; i < 34; i++) {
      final a = i * Gold.goldenAngle;
      final radial = math.sqrt(i / 34);
      final x = (size.width * 0.5) + math.cos(a) * radial * size.width * 0.56;
      final y = (size.height * 0.5) + math.sin(a) * radial * size.height * 0.60;
      speck.color = Colors.white.withValues(alpha: i.isEven ? 0.30 : 0.16);
      canvas.drawCircle(Offset(x, y), i % 5 == 0 ? 1.6 : 0.9, speck);
    }
  }

  @override
  bool shouldRepaint(covariant RankTexturePainter old) =>
      old.progress != progress || old.rank != rank;
}

/// A rotating aura for a ranked avatar.
class RankAuraPainter extends CustomPainter {
  final int rank;
  final double progress;

  const RankAuraPainter({required this.rank, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 3;
    if (radius <= 0) return;
    final palette = rankPalette(rank);
    final pulse = 0.62 + math.sin(progress * math.pi * 2) * 0.18;

    // Soft atmospheric bloom, inspired by the user's circular aura reference.
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = palette[1].withValues(alpha: pulse * 0.50)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..shader = SweepGradient(
          colors: [
            palette[0].withValues(alpha: 0.20),
            palette[1],
            Colors.white.withValues(alpha: 0.92),
            palette[2],
            palette[0].withValues(alpha: 0.20),
          ],
          transform: GradientRotation(progress * math.pi * 2),
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    canvas.drawCircle(
      center,
      radius - 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.52),
    );

    for (int i = 0; i < 14; i++) {
      final a = progress * math.pi * 2 + i * math.pi * 2 / 14;
      final orbit = radius + (i % 3 - 1) * 2.2;
      final dotRadius = i % 5 == 0 ? 2.1 : (i.isEven ? 1.3 : 0.8);
      canvas.drawCircle(
        Offset(
          center.dx + math.cos(a) * orbit,
          center.dy + math.sin(a) * orbit,
        ),
        dotRadius,
        Paint()
          ..color = (i % 3 == 0 ? Colors.white : palette[0]).withValues(
            alpha: 0.72 + (i % 4) * 0.07,
          )
          ..maskFilter = i % 5 == 0
              ? const MaskFilter.blur(BlurStyle.normal, 2)
              : null,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RankAuraPainter old) =>
      old.progress != progress || old.rank != rank;
}

/// The gilt wreath drawn around an animal celebrating a birthday.
class BirthdayWreathPainter extends CustomPainter {
  final double progress;
  const BirthdayWreathPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 5;
    if (radius <= 0) return;

    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Ink.violet.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final gilt = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..shader = SweepGradient(
        colors: const [
          Ink.goldLight,
          Ink.goldBase,
          Colors.white,
          Ink.goldDeep,
          Ink.goldLight,
        ],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, gilt);
    canvas.drawCircle(center, radius - 4, gilt..strokeWidth = 1.1);

    final leaf = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Ink.goldLight;

    for (int i = 0; i < 16; i++) {
      final a = i * math.pi * 2 / 16 + progress * 0.18;
      canvas.drawPath(
        Path()
          ..moveTo(
            center.dx + math.cos(a) * (radius + 1),
            center.dy + math.sin(a) * (radius + 1),
          )
          ..quadraticBezierTo(
            center.dx + math.cos(a + 0.05) * (radius + 10),
            center.dy + math.sin(a + 0.05) * (radius + 10),
            center.dx + math.cos(a + 0.10) * (radius + 7),
            center.dy + math.sin(a + 0.10) * (radius + 7),
          ),
        leaf,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BirthdayWreathPainter old) =>
      old.progress != progress;
}

// -----------------------------------------------------------------------------
//  Avatar
// -----------------------------------------------------------------------------

/// An animal portrait. Gains a rotating aura when the cow is ranked and a gilt
/// wreath on its birthday. Both animate only when actually shown, so an
/// ordinary list of animals costs nothing extra to render.
class AnimalAvatar extends StatefulWidget {
  final Map<String, dynamic> animal;
  final double radius;
  final bool decorate;

  const AnimalAvatar({
    super.key,
    required this.animal,
    this.radius = Gold.s34,
    this.decorate = true,
  });

  @override
  State<AnimalAvatar> createState() => _AnimalAvatarState();
}

// TickerProviderStateMixin, not the Single variant: this state disposes and
// recreates its controller as a cow moves on and off the podium, and the Single
// mixin keeps its internal ticker reference after disposal, so the second
// creation would trip its "multiple tickers were created" assertion.
class _AnimalAvatarState extends State<AnimalAvatar>
    with TickerProviderStateMixin {
  AnimationController? _c;

  void _ensureController(bool needed) {
    if (needed && _c == null) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 5),
      )..repeat();
    } else if (!needed && _c != null) {
      _c!.dispose();
      _c = null;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animal = widget.animal;
    final radius = widget.radius;
    final type = txt(animal, 'type');
    final isCow = type == 'cow';

    final rank = widget.decorate && isCow ? cowRank(txt(animal, 'name')) : 0;
    final birthday = widget.decorate && isBirthdayToday(animal);
    final ranked = rank > 0;

    _ensureController(ranked || birthday);

    final portrait = _AnimalPortrait(animal: animal, size: radius * 2);

    if (!ranked && !birthday) return portrait;

    final pad = (birthday ? 11.0 : 10.0) * (radius / 42).clamp(0.62, 1.30);
    final total = radius * 2 + pad * 2;
    final controller = _c;
    if (controller == null) return portrait;

    return SizedBox(
      width: total,
      height: total,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) {
          final t = controller.value;
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (ranked)
                CustomPaint(
                  size: Size(total, total),
                  painter: RankAuraPainter(rank: rank, progress: t),
                ),
              if (birthday)
                CustomPaint(
                  size: Size(total, total),
                  painter: BirthdayWreathPainter(progress: t),
                ),
              Container(
                padding: EdgeInsets.all(pad * Gold.minor),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.50),
                  border: Border.all(
                    color: birthday
                        ? Ink.goldLight
                        : rankColor(rank).withValues(alpha: 0.85),
                    width: birthday ? 2 : 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (birthday ? Ink.violet : rankColor(rank))
                          .withValues(alpha: 0.38),
                      blurRadius: Gold.s21,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: portrait,
              ),
              if (birthday)
                Positioned(
                  top: -2,
                  left: -2,
                  child: Container(
                    width: radius > 34 ? Gold.s21 : Gold.s13,
                    height: radius > 34 ? Gold.s21 : Gold.s13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Ink.goldLight, Ink.goldBase],
                      ),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Icon(
                      Icons.cake_rounded,
                      color: Ink.violetDeep,
                      size: radius > 34 ? 12 : 8,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Small reusable pieces
// -----------------------------------------------------------------------------

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SectionTitle({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gold.s13, left: Gold.s3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: Gold.t21,
                fontWeight: FontWeight.w900,
                color: Ink.navy,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: const TextStyle(
                  color: Ink.violetDeep,
                  fontWeight: FontWeight.w800,
                  fontSize: Gold.t13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget panel(String title, String emptyMessage, List<Widget> children) {
  return Glass(
    radius: Gold.r27,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: Gold.t16,
            fontWeight: FontWeight.w900,
            color: Ink.navy,
          ),
        ),
        const SizedBox(height: Gold.s8),
        if (children.isEmpty)
          Text(
            emptyMessage,
            style: const TextStyle(color: Ink.muted, fontSize: Gold.t13),
          )
        else
          ...children,
      ],
    ),
  );
}

class InfoRow extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const InfoRow({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Gold.r21,
      padding: const EdgeInsets.all(Gold.s13),
      elevation: 0.62,
      child: Row(
        children: [
          Container(
            width: Gold.s34,
            height: Gold.s34,
            decoration: ShapeDecoration(
              shape: SquircleBorder(
                radius: Gold.concentric(Gold.r21, Gold.s13),
              ),
              color: color.withValues(alpha: 0.13),
            ),
            child: Icon(icon, color: color, size: Gold.t16),
          ),
          const SizedBox(width: Gold.s13),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Ink.body,
                fontSize: Gold.t13,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Ink.navy,
              fontSize: Gold.t16,
            ),
          ),
        ],
      ),
    );
  }
}

class DataCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<String> details;

  const DataCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Gold.r27,
      margin: const EdgeInsets.only(bottom: Gold.s13),
      padding: const EdgeInsets.all(Gold.s16),
      elevation: 0.75,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: Gold.s34,
            height: Gold.s34,
            decoration: ShapeDecoration(
              shape: SquircleBorder(
                radius: Gold.concentric(Gold.r27, Gold.s16),
              ),
              color: color.withValues(alpha: 0.13),
            ),
            child: Icon(icon, color: color, size: Gold.t16),
          ),
          const SizedBox(width: Gold.s13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Ink.navy,
                    fontSize: Gold.t16,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Ink.muted, fontSize: Gold.t11),
                ),
                const SizedBox(height: Gold.s8),
                Wrap(
                  spacing: Gold.s8,
                  runSpacing: Gold.s5,
                  children: [
                    for (final d in details)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Gold.s8,
                          vertical: Gold.s5,
                        ),
                        decoration: ShapeDecoration(
                          shape: const SquircleBorder(radius: Gold.r8),
                          color: color.withValues(alpha: 0.09),
                        ),
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontSize: Gold.t11,
                            fontWeight: FontWeight.w700,
                            color: Ink.body,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live sync indicator. Rebuilds off the settings box so it always reflects the
/// real state rather than a snapshot from when the screen was built.
class SyncChip extends StatelessWidget {
  final bool light;
  const SyncChip({super.key, this.light = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box('settings').listenable(
        keys: const ['syncStatus', 'pendingSyncCount', 'autoSyncEnabled'],
      ),
      builder: (_, _, _) {
        final enabled = autoSyncEnabled();
        final pending = pendingSyncCount();
        final status = settingText('syncStatus', 'Waiting');
        final label = enabled
            ? (pending > 0 ? '$pending pending' : status)
            : 'Auto Sync OFF';

        final fg = light ? Colors.white : Ink.violetDeep;

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Gold.s13,
            vertical: Gold.s8,
          ),
          decoration: ShapeDecoration(
            shape: SquircleBorder(
              radius: Gold.r21,
              side: BorderSide(
                color: Colors.white.withValues(alpha: light ? 0.34 : 0.62),
              ),
            ),
            color: light
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.66),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enabled ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                size: Gold.t13,
                color: fg,
              ),
              const SizedBox(width: Gold.s5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: Gold.t11,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Empty-state placeholder, so a screen with no data still feels designed.
class EmptyNote extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyNote({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Gold.r27,
      padding: const EdgeInsets.symmetric(
        horizontal: Gold.s21,
        vertical: Gold.s34,
      ),
      child: Column(
        children: [
          Container(
            width: Gold.s55,
            height: Gold.s55,
            decoration: ShapeDecoration(
              shape: const SquircleBorder(radius: Gold.r21),
              color: Ink.violet.withValues(alpha: 0.10),
            ),
            child: Icon(icon, color: Ink.violet, size: Gold.t27),
          ),
          const SizedBox(height: Gold.s13),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Ink.navy,
              fontSize: Gold.t16,
            ),
          ),
          const SizedBox(height: Gold.s5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Ink.muted,
              fontSize: Gold.t13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
//  PART 7 — APP ROOT, AUTH, SHELL
// =============================================================================

class VimoApp extends StatelessWidget {
  const VimoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final text = GoogleFonts.poppinsTextTheme().apply(
      bodyColor: Ink.body,
      displayColor: Ink.navy,
    );

    return MaterialApp(
      title: 'VIMO',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Ink.canvasLow,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
        child: ColoredBox(
          color: Ink.canvasTop,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      scrollBehavior: const _SmoothScroll(),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Ink.canvasTop,
        textTheme: text,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Ink.violet,
          primary: Ink.violet,
          surface: Ink.canvasTop,
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          foregroundColor: Ink.navy,
          titleTextStyle: TextStyle(
            color: Ink.navy,
            fontWeight: FontWeight.w900,
            fontSize: Gold.t16,
          ),
        ),
        dividerTheme: const DividerThemeData(space: 0, thickness: 0),
      ),
      home: const AuthGate(),
    );
  }
}

/// Keeps momentum scrolling consistent and lets a mouse drag the list on web.
class _SmoothScroll extends MaterialScrollBehavior {
  const _SmoothScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (vimoPreviewMode) return const MainShell();

    // Without Firebase the app still runs fully offline against local storage.
    if (!firebaseReady) return const MainShell();

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _browserRuntime.dismissBootSplash(),
          );
          return const LoginScreen();
        }
        return const RanchAccessGate();
      },
    );
  }
}

class RanchAccessGate extends StatefulWidget {
  const RanchAccessGate({super.key});

  @override
  State<RanchAccessGate> createState() => _RanchAccessGateState();
}

class _RanchAccessGateState extends State<RanchAccessGate> {
  late Future<RanchGateState> _state;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _state = RanchAccessService.resolve().timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException(
        'Ranch access is taking too long. Check your connection and try again.',
      ),
    );
  }

  void _refresh() {
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RanchGateState>(
      future: _state,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AccessLoadingScreen();
        }
        // On web the animated HTML splash stays above this access check. Remove
        // it only after the real destination is ready, avoiding a second
        // full-screen "Checking ranch access" loader between the two screens.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _browserRuntime.dismissBootSplash(),
        );
        if (snapshot.hasError) {
          return _AccessErrorScreen(
            message: '${snapshot.error}'.replaceFirst('Bad state: ', ''),
            onRetry: _refresh,
          );
        }
        final state =
            snapshot.data ?? const RanchGateState(RanchGateMode.onboarding);
        return switch (state.mode) {
          RanchGateMode.active => MemberAwareShell(
            ranch: state.ranchId,
            onAccessChanged: _refresh,
          ),
          RanchGateMode.waiting => WaitingApprovalScreen(
            ranch: state.ranchId,
            onChanged: _refresh,
          ),
          RanchGateMode.onboarding => RanchOnboardingScreen(
            onComplete: _refresh,
          ),
        };
      },
    );
  }
}

class _AccessLoadingScreen extends StatelessWidget {
  const _AccessLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Ink.canvasTop,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: Gold.s89),
            SizedBox(height: Gold.s21),
            CircularProgressIndicator(color: Ink.violet),
            SizedBox(height: Gold.s13),
            Text(
              'Checking ranch access...',
              style: TextStyle(color: Ink.muted, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AccessErrorScreen({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Gold.contentWidth),
            child: Padding(
              padding: const EdgeInsets.all(Gold.s21),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmptyNote(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could not verify ranch access',
                    message: message,
                  ),
                  const SizedBox(height: Gold.s21),
                  LiquidButton(
                    label: 'Try Again',
                    icon: Icons.refresh_rounded,
                    onPressed: onRetry,
                  ),
                  const SizedBox(height: Gold.s13),
                  GhostButton(
                    label: 'Sign Out',
                    icon: Icons.logout_rounded,
                    onPressed: () => FirebaseAuth.instance.signOut(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MemberAwareShell extends StatefulWidget {
  final String ranch;
  final VoidCallback onAccessChanged;

  const MemberAwareShell({
    super.key,
    required this.ranch,
    required this.onAccessChanged,
  });

  @override
  State<MemberAwareShell> createState() => _MemberAwareShellState();
}

class _MemberAwareShellState extends State<MemberAwareShell> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription =
        RanchAccessService.memberRef(
          widget.ranch,
          RanchAccessService.uid,
        ).snapshots().listen((snapshot) async {
          final member = snapshot.data();
          if (!snapshot.exists || member == null || member['active'] == false) {
            await RanchAccessService.clearLocalRanchData();
            if (RanchAccessService.user != null) {
              await RanchAccessService.userRef.set({
                'currentRanchId': '',
                'pendingRanchId': '',
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            }
            if (mounted) widget.onAccessChanged();
            return;
          }
          await setSetting(
            'currentRole',
            normalizeFamilyRole(txt(member, 'role', 'Viewer')),
          );
          await setSetting(
            'currentUser',
            txt(member, 'name', currentUserName()),
          );
        });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const MainShell();
}

class RanchOnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const RanchOnboardingScreen({super.key, required this.onComplete});

  @override
  State<RanchOnboardingScreen> createState() => _RanchOnboardingScreenState();
}

class _RanchOnboardingScreenState extends State<RanchOnboardingScreen> {
  final _farm = TextEditingController();
  final _owner = TextEditingController();
  final _place = TextEditingController();
  final _createId = TextEditingController();
  final _joinName = TextEditingController();
  final _joinId = TextEditingController();
  Timer? _availabilityTimer;
  int _mode = 0;
  bool _busy = false;
  bool? _available;
  String _availabilityText = '';

  @override
  void initState() {
    super.initState();
    final current = FirebaseAuth.instance.currentUser;
    final suggested = current == null
        ? ''
        : RanchAccessService.displayNameFor(current);
    _joinName.text = suggested;
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    _farm.dispose();
    _owner.dispose();
    _place.dispose();
    _createId.dispose();
    _joinName.dispose();
    _joinId.dispose();
    super.dispose();
  }

  void _checkAvailability(String raw) {
    _availabilityTimer?.cancel();
    final id = normalizeRanchId(raw);
    _createId.value = _createId.value.copyWith(
      text: id,
      selection: TextSelection.collapsed(offset: id.length),
      composing: TextRange.empty,
    );
    final error = ranchIdValidationError(id);
    if (error != null) {
      setState(() {
        _available = false;
        _availabilityText = error;
      });
      return;
    }
    setState(() {
      _available = null;
      _availabilityText = 'Checking availability...';
    });
    _availabilityTimer = Timer(const Duration(milliseconds: 500), () async {
      final snap = await FirebaseFirestore.instance
          .collection('ranch_ids')
          .doc(id)
          .get();
      if (!mounted || id != _createId.text) return;
      setState(() {
        _available = !snap.exists;
        _availabilityText = snap.exists
            ? 'This Ranch ID is already taken'
            : 'Ranch ID is available';
      });
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_mode == 0) {
      final farm = _farm.text.trim();
      final owner = _owner.text.trim();
      if (farm.isEmpty || owner.isEmpty) {
        snack(context, 'Enter the ranch name and admin name');
        return;
      }
      final error = ranchIdValidationError(_createId.text);
      if (error != null) {
        snack(context, error);
        return;
      }
      if (_available != true) {
        snack(context, 'Choose an available Ranch ID');
        return;
      }
      setState(() => _busy = true);
      try {
        await RanchAccessService.createRanch(
          requestedId: _createId.text,
          farm: farm,
          owner: owner,
          place: _place.text.trim(),
        );
        widget.onComplete();
      } catch (error) {
        if (mounted) {
          snack(context, '$error'.replaceFirst('Bad state: ', ''));
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    final name = _joinName.text.trim();
    final id = normalizeRanchId(_joinId.text);
    if (name.isEmpty || id.isEmpty) {
      snack(context, 'Enter your name and the Ranch ID');
      return;
    }
    setState(() => _busy = true);
    try {
      await RanchAccessService.requestToJoin(requestedId: id, name: name);
      widget.onComplete();
    } catch (error) {
      if (mounted) snack(context, '$error'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      body: Shell(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Gold.contentWidth),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Gold.s21,
                  Gold.s34,
                  Gold.s21,
                  Gold.s55,
                ),
                children: [
                  const Center(child: BrandMark(size: Gold.s89)),
                  const SizedBox(height: Gold.s13),
                  const Text(
                    'Set up your ranch',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Ink.navy,
                      fontSize: Gold.t27,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: Gold.s5),
                  const Text(
                    'Create a private ranch or request access to an existing one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Ink.muted, height: 1.45),
                  ),
                  const SizedBox(height: Gold.s21),
                  Glass(
                    radius: Gold.r21,
                    padding: const EdgeInsets.all(Gold.s5),
                    child: LiquidSegmentBar(
                      labels: const ['Create New', 'Join Existing'],
                      index: _mode,
                      onChanged: (value) => setState(() => _mode = value),
                    ),
                  ),
                  const SizedBox(height: Gold.s21),
                  if (_mode == 0) ...[
                    TextField(
                      controller: _farm,
                      textCapitalization: TextCapitalization.words,
                      decoration: fieldStyle(
                        'Ranch Name',
                        icon: Icons.home_work_outlined,
                      ),
                    ),
                    const SizedBox(height: Gold.s13),
                    TextField(
                      controller: _owner,
                      textCapitalization: TextCapitalization.words,
                      decoration: fieldStyle(
                        'Admin Name',
                        icon: Icons.admin_panel_settings_outlined,
                      ),
                    ),
                    const SizedBox(height: Gold.s13),
                    TextField(
                      controller: _place,
                      textCapitalization: TextCapitalization.words,
                      decoration: fieldStyle(
                        'Place (optional)',
                        icon: Icons.place_outlined,
                      ),
                    ),
                    const SizedBox(height: Gold.s13),
                    TextField(
                      controller: _createId,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: fieldStyle(
                        'Create Ranch ID',
                        icon: Icons.alternate_email_rounded,
                      ),
                      onChanged: _checkAvailability,
                    ),
                    if (_availabilityText.isNotEmpty) ...[
                      const SizedBox(height: Gold.s8),
                      Text(
                        _availabilityText,
                        style: TextStyle(
                          color: _available == true ? Ink.green : Ink.red,
                          fontSize: Gold.t11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ] else ...[
                    TextField(
                      controller: _joinName,
                      textCapitalization: TextCapitalization.words,
                      decoration: fieldStyle(
                        'Your Name',
                        icon: Icons.person_outline_rounded,
                      ),
                    ),
                    const SizedBox(height: Gold.s13),
                    TextField(
                      controller: _joinId,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: fieldStyle(
                        'Enter Ranch ID',
                        icon: Icons.key_rounded,
                      ),
                      onChanged: (value) {
                        final id = normalizeRanchId(value);
                        if (id != value) {
                          _joinId.value = _joinId.value.copyWith(
                            text: id,
                            selection: TextSelection.collapsed(
                              offset: id.length,
                            ),
                            composing: TextRange.empty,
                          );
                        }
                      },
                    ),
                    const SizedBox(height: Gold.s13),
                    const EmptyNote(
                      icon: Icons.approval_rounded,
                      title: 'Admin approval required',
                      message:
                          'The ranch admin will receive your request. Ranch data stays private until they approve it.',
                    ),
                  ],
                  const SizedBox(height: Gold.s21),
                  LiquidButton(
                    label: _mode == 0 ? 'Create Ranch' : 'Request to Join',
                    icon: _mode == 0
                        ? Icons.add_home_work_rounded
                        : Icons.send_rounded,
                    busy: _busy,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: Gold.s13),
                  GhostButton(
                    label: 'Sign Out',
                    icon: Icons.logout_rounded,
                    onPressed: () => FirebaseAuth.instance.signOut(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WaitingApprovalScreen extends StatefulWidget {
  final String ranch;
  final VoidCallback onChanged;

  const WaitingApprovalScreen({
    super.key,
    required this.ranch,
    required this.onChanged,
  });

  @override
  State<WaitingApprovalScreen> createState() => _WaitingApprovalScreenState();
}

class _WaitingApprovalScreenState extends State<WaitingApprovalScreen> {
  bool _activating = false;
  bool _activationAttempted = false;
  String _activationError = '';

  Future<void> _activate(Map<String, dynamic> request) async {
    if (_activating) return;
    setState(() {
      _activating = true;
      _activationAttempted = true;
      _activationError = '';
    });
    try {
      final member = await RanchAccessService.memberRef(
        widget.ranch,
        RanchAccessService.uid,
      ).get();
      if (member.exists && member.data() != null) {
        await RanchAccessService.activate(widget.ranch, member.data()!);
        widget.onChanged();
      } else {
        throw StateError(
          'Approval is incomplete. Ask the admin to approve again',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _activationError = '$error'.replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const SquircleBorder(radius: Gold.r27),
        title: const Text(
          'Cancel join request?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'You will return to the create or join ranch screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Waiting'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancel Request',
              style: TextStyle(color: Ink.red, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await RanchAccessService.cancelJoinRequest(widget.ranch);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: RanchAccessService.requestRef(
        widget.ranch,
        RanchAccessService.uid,
      ).snapshots(),
      builder: (context, snapshot) {
        final request = snapshot.data?.data() ?? <String, dynamic>{};
        final status = txt(request, 'status', 'pending');
        if (status == 'approved' && !_activationAttempted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _activate(request);
          });
        }
        if (status == 'rejected') {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await RanchAccessService.cancelJoinRequest(widget.ranch);
            if (mounted) widget.onChanged();
          });
        }
        return Scaffold(
          backgroundColor: Ink.canvasTop,
          body: Shell(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: Gold.contentWidth,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Gold.s21),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BrandMark(size: Gold.s89),
                        const SizedBox(height: Gold.s21),
                        Glass(
                          radius: Gold.r34,
                          padding: const EdgeInsets.all(Gold.s34),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.hourglass_top_rounded,
                                color: Ink.violet,
                                size: Gold.t34,
                              ),
                              const SizedBox(height: Gold.s13),
                              const Text(
                                'Waiting for admin approval',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Ink.navy,
                                  fontSize: Gold.t21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: Gold.s8),
                              Text(
                                'Ranch ID  ${widget.ranch}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Ink.violetDeep,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: Gold.s8),
                              const Text(
                                'You will automatically enter the ranch after an admin accepts your request.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Ink.muted,
                                  height: 1.45,
                                ),
                              ),
                              if (_activating) ...[
                                const SizedBox(height: Gold.s21),
                                const CircularProgressIndicator(
                                  color: Ink.violet,
                                ),
                              ],
                              if (_activationError.isNotEmpty) ...[
                                const SizedBox(height: Gold.s13),
                                Text(
                                  _activationError,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Ink.red,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: Gold.s13),
                                GhostButton(
                                  label: 'Try Again',
                                  icon: Icons.refresh_rounded,
                                  onPressed: () {
                                    setState(
                                      () => _activationAttempted = false,
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: Gold.s21),
                        GhostButton(
                          label: 'Cancel Request',
                          icon: Icons.close_rounded,
                          color: Ink.red,
                          onPressed: _cancel,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The VIMO app mark.
///
/// The icon asset has a transparent outer edge, so it can be displayed directly
/// without adding another pale board, crop, or frame around the artwork.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = Gold.s55});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image(
        image: vimoIconImage,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Login
// -----------------------------------------------------------------------------

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _remember = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address does not look right';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect';
      case 'email-already-in-use':
        return 'That email already has an account. Try signing in';
      case 'weak-password':
        return 'Please choose a stronger password';
      case 'network-request-failed':
        return 'No network. Check your connection and try again';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment';
      default:
        return e.message ?? 'Sign in failed';
    }
  }

  Future<void> _authenticate({required bool createAccount}) async {
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || !email.contains('@')) {
      snack(context, 'Please enter a valid email');
      return;
    }
    if (password.length < 6) {
      snack(context, 'Password needs at least 6 characters');
      return;
    }

    setState(() => _busy = true);
    try {
      // "Remember me" chooses whether the session survives a browser restart.
      await FirebaseAuth.instance.setPersistence(
        _remember ? Persistence.LOCAL : Persistence.SESSION,
      );

      if (createAccount) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
      if (mounted) {
        snack(context, createAccount ? 'Account created' : 'Welcome back');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) snack(context, _friendlyError(e));
    } catch (_) {
      if (mounted) snack(context, 'Sign in failed. Please try again');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      snack(context, 'Enter your email first, then tap Forgot password');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) snack(context, 'Reset link sent to $email');
    } on FirebaseAuthException catch (e) {
      if (mounted) snack(context, _friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Backdrop: a soft landscape wash rather than a full-strength photo.
          // The artwork carries no lettering, so nothing competes with the
          // brand lockup, and the veil keeps the sign-in card legible.
          const Positioned.fill(child: ColoredBox(color: Ink.canvasTop)),
          Positioned.fill(
            child: Opacity(
              opacity: 0.42,
              child: Image(
                image: heroArtImage,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Ink.canvasTop.withValues(alpha: 0.24),
                    Ink.canvasTop.withValues(alpha: 0.78),
                    Ink.canvasTop,
                  ],
                  stops: const [0.0, Gold.minor, Gold.invPhi],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Gold.contentWidth),
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gold.s21,
                    vertical: Gold.s34,
                  ),
                  children: [
                    const Reveal(
                      index: 0,
                      child: Center(child: BrandMark(size: Gold.s89)),
                    ),
                    const SizedBox(height: Gold.s21),
                    Reveal(
                      index: 1,
                      child: Column(
                        children: [
                          Text(
                            appName(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: Gold.t34,
                              fontWeight: FontWeight.w900,
                              color: Ink.navy,
                              letterSpacing: 3,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            farmName(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: Gold.t16,
                              fontWeight: FontWeight.w600,
                              color: Ink.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Gold.s34),
                    Reveal(
                      index: 2,
                      child: Glass(
                        radius: Gold.r34,
                        padding: const EdgeInsets.all(Gold.s21),
                        elevation: 1.3,
                        child: Column(
                          children: [
                            const Text(
                              'Welcome Back!',
                              style: TextStyle(
                                fontSize: Gold.t21,
                                fontWeight: FontWeight.w900,
                                color: Ink.navy,
                              ),
                            ),
                            const SizedBox(height: Gold.s3),
                            const Text(
                              'Sign in to continue',
                              style: TextStyle(
                                color: Ink.muted,
                                fontSize: Gold.t13,
                              ),
                            ),
                            const SizedBox(height: Gold.s21),
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              decoration: fieldStyle(
                                'Email',
                                icon: Icons.mail_outline_rounded,
                              ),
                            ),
                            const SizedBox(height: Gold.s13),
                            TextField(
                              controller: _password,
                              obscureText: _obscure,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) =>
                                  _authenticate(createAccount: false),
                              decoration: fieldStyle(
                                'Password',
                                icon: Icons.lock_outline_rounded,
                                suffix: IconButton(
                                  splashRadius: Gold.s21,
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: Ink.muted,
                                    size: Gold.t21,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                            ),
                            const SizedBox(height: Gold.s5),
                            Row(
                              children: [
                                SizedBox(
                                  width: Gold.s21,
                                  height: Gold.s21,
                                  child: Checkbox(
                                    value: _remember,
                                    activeColor: Ink.violet,
                                    shape: const SquircleBorder(
                                      radius: Gold.r8,
                                    ),
                                    side: BorderSide(
                                      color: Ink.muted.withValues(alpha: 0.62),
                                      width: 1.4,
                                    ),
                                    onChanged: (v) =>
                                        setState(() => _remember = v ?? true),
                                  ),
                                ),
                                const SizedBox(width: Gold.s8),
                                const Text(
                                  'Remember me',
                                  style: TextStyle(
                                    fontSize: Gold.t11,
                                    color: Ink.body,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: _resetPassword,
                                  child: const Text(
                                    'Forgot password?',
                                    style: TextStyle(
                                      fontSize: Gold.t11,
                                      color: Ink.violetDeep,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: Gold.s21),
                            LiquidButton(
                              label: 'Sign In',
                              busy: _busy,
                              onPressed: () =>
                                  _authenticate(createAccount: false),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: Gold.s21),
                    Reveal(
                      index: 3,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'New here? ',
                            style: TextStyle(
                              color: Ink.muted,
                              fontSize: Gold.t13,
                            ),
                          ),
                          GestureDetector(
                            onTap: _busy
                                ? null
                                : () => _authenticate(createAccount: true),
                            child: const Text(
                              'Create Account',
                              style: TextStyle(
                                color: Ink.violetDeep,
                                fontWeight: FontWeight.w900,
                                fontSize: Gold.t13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Main shell
// -----------------------------------------------------------------------------

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  /// Height reserved under every scroll view so the floating bar and the action
  /// button never sit on top of content.
  static const double bottomInset = Gold.s89 + Gold.s34;

  void _openCard(String type) {
    switch (type) {
      case 'cows':
        push(context, const AnimalsScreen(initialTab: 0, standalone: true));
        break;
      case 'calves':
        push(context, const AnimalsScreen(initialTab: 1, standalone: true));
        break;
      case 'milk':
        push(
          context,
          const RecordListScreen(title: 'Milk Details', recordType: 'milk'),
        );
        break;
      default:
        push(
          context,
          const RecordListScreen(
            title: 'Expense Details',
            recordType: 'expense',
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardScreen(onOpenCard: _openCard),
      const AnimalsScreen(),
      const SellScreen(),
      const ReportsScreen(),
    ];
    final tab = _tab.clamp(0, pages.length - 1);

    return Scaffold(
      extendBody: true,
      backgroundColor: Ink.canvasTop,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: Gold.base,
              switchInCurve: Gold.ease,
              switchOutCurve: Gold.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.018),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(key: ValueKey<int>(tab), child: pages[tab]),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: Gold.s89 + Gold.s5,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Gold.contentWidth + Gold.s55,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(right: Gold.s21),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: _QuickAddButton(
                      onTap: () => guardedPush(
                        context,
                        allowed: canRecordEntries,
                        message:
                            'Your ranch role does not allow adding entries',
                        page: const AddEntryScreen(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gold.s21, 0, Gold.s21, Gold.s13),
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: Gold.contentWidth + Gold.s89,
              ),
              child: _NavBar(
                index: tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _QuickAddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      radius: Gold.s55,
      onTap: onTap,
      child: Container(
        width: Gold.s55,
        height: Gold.s55,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF9366FF), Ink.violetDeep],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.80),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Ink.violet.withValues(alpha: 0.44),
              blurRadius: Gold.s34,
              offset: const Offset(0, Gold.s13),
            ),
          ],
        ),
        child: const Icon(
          Icons.add_rounded,
          size: Gold.t27,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _NavBar({required this.index, required this.onChanged});

  static const List<_NavItem> _items = [
    _NavItem('Home', Icons.home_rounded, Icons.home_outlined),
    _NavItem('Cows', null, null),
    _NavItem('Sell', Icons.sell_rounded, Icons.sell_outlined),
    _NavItem('Reports', Icons.bar_chart_rounded, Icons.bar_chart_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Gold.r27,
      blur: Gold.s34,
      opacity: 0.72,
      elevation: 1.1,
      padding: const EdgeInsets.symmetric(
        horizontal: Gold.s8,
        vertical: Gold.s8,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = constraints.maxWidth / _items.length;
          return SizedBox(
            height: Gold.s55,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutBack,
                  left: index.clamp(0, _items.length - 1) * cellWidth,
                  width: cellWidth,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Glass(
                      radius: Gold.r21,
                      blur: Gold.s21,
                      opacity: 0.58,
                      specular: 1.2,
                      elevation: 0.72,
                      padding: EdgeInsets.zero,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.82),
                          Ink.violet.withValues(alpha: 0.20),
                          Colors.white.withValues(alpha: 0.44),
                        ],
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (int i = 0; i < _items.length; i++)
                      Expanded(
                        child: _NavCell(
                          item: _items[i],
                          active: index == i,
                          onTap: () => onChanged(i),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData? active;
  final IconData? idle;
  const _NavItem(this.label, this.active, this.idle);
}

class _NavCell extends StatelessWidget {
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  const _NavCell({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Ink.violetDeep : Ink.faint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Gold.base,
        curve: Gold.ease,
        padding: const EdgeInsets.symmetric(vertical: Gold.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: Gold.s27,
              child: item.label == 'Cows'
                  ? CowHoofIcon(
                      size: Gold.s27,
                      color: active ? Ink.violetDeep : Ink.faint,
                    )
                  : Icon(
                      active ? item.active : item.idle,
                      size: Gold.t21,
                      color: color,
                    ),
            ),
            const SizedBox(height: Gold.s3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Gold.t10,
                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
//  PART 8 — DASHBOARD
// =============================================================================

class DashboardScreen extends StatelessWidget {
  final void Function(String type) onOpenCard;
  const DashboardScreen({super.key, required this.onOpenCard});

  @override
  Widget build(BuildContext context) {
    // One listenable per box the dashboard actually reads, so unrelated writes
    // never trigger a rebuild of the whole screen.
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box('animals').listenable(),
      builder: (_, _, _) => ValueListenableBuilder<Box<dynamic>>(
        valueListenable: Hive.box('milk_records').listenable(),
        builder: (_, _, _) => ValueListenableBuilder<Box<dynamic>>(
          valueListenable: Hive.box('sale_records').listenable(),
          builder: (_, _, _) => ValueListenableBuilder<Box<dynamic>>(
            valueListenable: Hive.box('food_records').listenable(),
            builder: (_, _, _) => ValueListenableBuilder<Box<dynamic>>(
              valueListenable: Hive.box('stock_records').listenable(),
              builder: (_, _, _) => ValueListenableBuilder<Box<dynamic>>(
                valueListenable: Hive.box('expense_records').listenable(),
                builder: (_, _, _) => _build(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _build(BuildContext context) {
    final birthday = birthdayHeroAnimal();

    final tiles = <Widget>[
      _StatTile(
        type: 'cows',
        label: 'Total Cows',
        value: '${animalsBy('cow').length}',
        icon: const CowMark(size: Gold.s21),
        ghost: const CowMark(size: Gold.s89),
        accent: Ink.violet,
        onTap: onOpenCard,
      ),
      _StatTile(
        type: 'milk',
        label: "Today's Milk",
        value: '${milkTotal('Today').toStringAsFixed(1)} L',
        icon: const RanchIcon(type: 'bottle', size: Gold.s21, color: Ink.blue),
        ghost: const RanchIcon(type: 'milk', size: Gold.s89, color: Ink.blue),
        accent: Ink.blue,
        onTap: onOpenCard,
      ),
      _StatTile(
        type: 'calves',
        label: 'Calves',
        value: '${animalsBy('calf').length}',
        icon: const CowMark(size: Gold.s21),
        ghost: const CowMark(size: Gold.s89),
        accent: Ink.amber,
        onTap: onOpenCard,
      ),
      _StatTile(
        type: 'expenses',
        label: 'Expense',
        value: money(totalExpense('Today')),
        icon: const Icon(
          Icons.account_balance_wallet_outlined,
          size: Gold.t21,
          color: Ink.amber,
        ),
        ghost: const Icon(
          Icons.account_balance_wallet_outlined,
          size: Gold.s89,
          color: Ink.amber,
        ),
        accent: Ink.amber,
        onTap: onOpenCard,
      ),
      _StatTile(
        type: 'cows',
        label: 'Pregnant Cows',
        value: '${pregnantCowCount()}',
        icon: const Icon(
          Icons.favorite_border_rounded,
          size: Gold.t21,
          color: Ink.violetDeep,
        ),
        ghost: const Icon(
          Icons.favorite_border_rounded,
          size: Gold.s89,
          color: Ink.violetDeep,
        ),
        accent: Ink.violetDeep,
        onTap: onOpenCard,
      ),
      _StatTile(
        type: 'expenses',
        label: 'Today Sales',
        value: money(saleIncome('Today')),
        icon: const Icon(Icons.sell_outlined, size: Gold.t21, color: Ink.green),
        ghost: const Icon(
          Icons.sell_outlined,
          size: Gold.s89,
          color: Ink.green,
        ),
        accent: Ink.green,
        onTap: onOpenCard,
      ),
    ];

    final activity = recentActivities(limit: 4);

    return Shell(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Gold.s21,
          Gold.s21,
          Gold.s21,
          _MainShellState.bottomInset,
        ),
        children: [
          Reveal(
            index: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dashboard',
                        style: TextStyle(
                          fontSize: Gold.t34,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          color: Ink.navy,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: Gold.s3),
                      Text(
                        farmName(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Ink.muted,
                          fontSize: Gold.t13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gold.s13),
                Glass(
                  radius: Gold.r21,
                  blur: Gold.s13,
                  padding: const EdgeInsets.all(Gold.s13),
                  elevation: 0.8,
                  onTap: () => push(context, const SettingsScreen()),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Ink.violetDeep,
                    size: Gold.t21,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gold.s21),
          if (canManageRanch) ...[
            const PendingJoinRequestsBanner(),
            const SizedBox(height: Gold.s13),
          ],
          Reveal(
            index: 1,
            child: birthday == null
                ? const _RanchHero()
                : _BirthdayHero(animal: birthday),
          ),
          const SizedBox(height: Gold.s21),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 800 ? 3 : 2;
              return GridView.builder(
                itemCount: tiles.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: Gold.s13,
                  crossAxisSpacing: Gold.s13,
                  mainAxisExtent: 142,
                ),
                itemBuilder: (_, i) => Reveal(index: 2 + i, child: tiles[i]),
              );
            },
          ),
          if (activity.isNotEmpty) ...[
            const SizedBox(height: Gold.s34),
            Reveal(
              index: 8,
              child: const SectionTitle(title: 'Recent Activity'),
            ),
            Reveal(
              index: 9,
              child: Glass(
                radius: Gold.r27,
                padding: const EdgeInsets.symmetric(
                  horizontal: Gold.s16,
                  vertical: Gold.s8,
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < activity.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: Gold.s16,
                          thickness: 1,
                          color: Ink.violet.withValues(alpha: 0.08),
                        ),
                      _ActivityRow(entry: activity[i]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PendingJoinRequestsBanner extends StatelessWidget {
  const PendingJoinRequestsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final id = ranchId();
    if (!canManageRanch || id.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: RanchAccessService.ranchRef(
        id,
      ).collection('join_requests').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Glass(
            radius: Gold.r21,
            padding: const EdgeInsets.all(Gold.s13),
            onTap: () => push(context, const FamilyUsersScreen()),
            child: const Row(
              children: [
                Icon(Icons.sync_problem_rounded, color: Ink.amber),
                SizedBox(width: Gold.s13),
                Expanded(
                  child: Text(
                    'Could not check join requests — tap to retry',
                    style: TextStyle(
                      color: Ink.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final count =
            snapshot.data?.docs
                .where((doc) => txt(doc.data(), 'status') == 'pending')
                .length ??
            0;
        if (count == 0) return const SizedBox.shrink();
        return Glass(
          radius: Gold.r21,
          padding: const EdgeInsets.all(Gold.s13),
          gradient: LinearGradient(
            colors: [
              Ink.violet.withValues(alpha: 0.18),
              Colors.white.withValues(alpha: 0.80),
            ],
          ),
          onTap: () => push(context, const FamilyUsersScreen()),
          child: Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded, color: Ink.violetDeep),
              const SizedBox(width: Gold.s13),
              Expanded(
                child: Text(
                  '$count ${count == 1 ? 'person wants' : 'people want'} to join your ranch',
                  style: const TextStyle(
                    color: Ink.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Text(
                'Review',
                style: TextStyle(
                  color: Ink.violetDeep,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _ActivityRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = entry['color'] as Color? ?? Ink.violet;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gold.s5),
      child: Row(
        children: [
          Container(
            width: Gold.s34,
            height: Gold.s34,
            decoration: ShapeDecoration(
              shape: const SquircleBorder(radius: Gold.r13),
              color: color.withValues(alpha: 0.13),
            ),
            child: Icon(
              entry['icon'] as IconData? ?? Icons.circle,
              size: Gold.t16,
              color: color,
            ),
          ),
          const SizedBox(width: Gold.s13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry['title']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: Gold.t13,
                    color: Ink.navy,
                  ),
                ),
                Text(
                  '${entry['sub']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Ink.muted, fontSize: Gold.t10),
                ),
              ],
            ),
          ),
          const SizedBox(width: Gold.s8),
          Text(
            '${entry['value']}',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: Gold.t13,
              color: Ink.navy,
            ),
          ),
        ],
      ),
    );
  }
}

/// The standard hero: ranch art with the brand lockup and a live sync pill.
class _RanchHero extends StatelessWidget {
  const _RanchHero();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: Gold.phi,
      child: Container(
        decoration: ShapeDecoration(
          shape: const SquircleBorder(radius: Gold.r34),
          shadows: [
            BoxShadow(
              color: Ink.violetDeep.withValues(alpha: 0.28),
              blurRadius: Gold.s34,
              offset: const Offset(0, Gold.s16),
            ),
          ],
        ),
        child: ClipPath(
          clipper: const SquircleClipper(Gold.r34),
          child: CustomPaint(
            foregroundPainter: const _GlassSkinPainter(
              radius: Gold.r34,
              strength: 0.85,
              sheen: false,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(
                  image: heroArtImage,
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
                // Legibility wash: opaque on the text side, clear on the art.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Ink.violetDeep.withValues(alpha: 0.94),
                        Ink.violet.withValues(alpha: 0.58),
                        Ink.violet.withValues(alpha: 0.06),
                      ],
                      stops: const [0.0, Gold.minor, Gold.invPhi],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Gold.s21),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        farmName(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: Gold.t27,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: Gold.s3),
                      const Text(
                        'Manage. Care. Grow.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: Gold.t13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: Gold.s13),
                      const SyncChip(light: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Birthday takeover. Only active animals reach this, so a sold or died animal
/// can never appear here.
class _BirthdayHero extends StatefulWidget {
  final Map<String, dynamic> animal;
  const _BirthdayHero({required this.animal});

  @override
  State<_BirthdayHero> createState() => _BirthdayHeroState();
}

class _BirthdayHeroState extends State<_BirthdayHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 7))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animal = widget.animal;
    final name = txt(animal, 'name');
    final years = birthdayAgeYears(animal);
    final others = birthdayAnimalsToday().length - 1;
    final portrait = animalImage(animal);

    return Pressable(
      radius: Gold.r34,
      onTap: () => push(context, AnimalProfileScreen(animalKey: animal['key'])),
      child: AspectRatio(
        aspectRatio: Gold.phi,
        child: Container(
          decoration: ShapeDecoration(
            shape: const SquircleBorder(radius: Gold.r34),
            shadows: [
              BoxShadow(
                color: Ink.violet.withValues(alpha: 0.34),
                blurRadius: Gold.s34,
                offset: const Offset(0, Gold.s16),
              ),
            ],
          ),
          child: ClipPath(
            clipper: const SquircleClipper(Gold.r34),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (portrait != null)
                  Image(
                    image: portrait,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  )
                else
                  Image(
                    image: heroArtImage,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    gaplessPlayback: true,
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Ink.violetDeep.withValues(alpha: 0.95),
                        Ink.violet.withValues(alpha: 0.46),
                        Ink.violet.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.52, 1.0],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _c,
                        builder: (_, _) =>
                            CustomPaint(painter: _ConfettiPainter(_c.value)),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Gold.s21),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Gold.s13,
                          vertical: Gold.s5,
                        ),
                        decoration: ShapeDecoration(
                          shape: const SquircleBorder(radius: Gold.r13),
                          gradient: const LinearGradient(
                            colors: [Ink.goldLight, Ink.goldBase],
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cake_rounded,
                              size: Gold.t13,
                              color: Ink.violetDark,
                            ),
                            SizedBox(width: Gold.s5),
                            Text(
                              'Happy Birthday!',
                              style: TextStyle(
                                color: Ink.violetDark,
                                fontWeight: FontWeight.w900,
                                fontSize: Gold.t11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Gold.s8),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: Gold.t27,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        years > 0
                            ? 'Turns $years today'
                            : 'Born today \u2022 welcome',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: Gold.t13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (others > 0) ...[
                        const SizedBox(height: Gold.s8),
                        Text(
                          others == 1
                              ? '+1 more birthday today'
                              : '+$others more birthdays today',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.86),
                            fontSize: Gold.t11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  const _ConfettiPainter(this.t);

  static const List<Color> _colors = [
    Ink.goldLight,
    Colors.white,
    Ink.rankPurpleLight,
    Ink.rankGreenLight,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint();

    for (int i = 0; i < 21; i++) {
      // Golden-angle placement keeps the drift from forming visible columns.
      final a = i * Gold.goldenAngle;
      final x = ((math.cos(a) * 0.5 + 0.5) * size.width);
      final fall = ((t + i / 21) % 1.0);
      final y = fall * size.height;
      final sway = math.sin((t * 2 + i) * math.pi) * 5;

      paint.color = _colors[i % _colors.length].withValues(
        alpha: 0.62 * (1 - fall).clamp(0.0, 1.0),
      );

      canvas.save();
      canvas.translate(x + sway, y);
      canvas.rotate(a + t * math.pi * 2);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 4, height: 6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

class _StatTile extends StatelessWidget {
  final String type;
  final String label;
  final String value;
  final Widget icon;
  final Widget ghost;
  final Color accent;
  final void Function(String) onTap;

  const _StatTile({
    required this.type,
    required this.label,
    required this.value,
    required this.icon,
    required this.ghost,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Gold.r27,
      blur: Gold.s21,
      opacity: 0.66,
      padding: EdgeInsets.zero,
      onTap: () => onTap(type),
      child: Stack(
        children: [
          // Watermark illustration, clipped and anchored to the low corner.
          Positioned(
            right: -Gold.s13,
            bottom: -Gold.s13,
            child: Opacity(opacity: 0.07, child: ghost),
          ),
          Padding(
            padding: const EdgeInsets.all(Gold.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: Gold.s34,
                  height: Gold.s34,
                  decoration: ShapeDecoration(
                    shape: SquircleBorder(
                      radius: Gold.concentric(Gold.r27, Gold.s16),
                    ),
                    color: Colors.white.withValues(alpha: 0.72),
                    shadows: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.16),
                        blurRadius: Gold.s13,
                        offset: const Offset(0, Gold.s5),
                      ),
                    ],
                  ),
                  child: Center(child: icon),
                ),
                const Spacer(),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: Gold.t11,
                    color: Ink.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Gold.s2),
                FlowText(
                  value,
                  style: const TextStyle(
                    fontSize: Gold.t27,
                    fontWeight: FontWeight.w900,
                    color: Ink.navy,
                    height: 1,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
//  PART 9 — ANIMALS AND RANKING
// =============================================================================

class AnimalsScreen extends StatefulWidget {
  final int initialTab;
  final bool standalone;

  const AnimalsScreen({
    super.key,
    this.initialTab = 0,
    this.standalone = false,
  });

  @override
  State<AnimalsScreen> createState() => _AnimalsScreenState();
}

class _AnimalsScreenState extends State<AnimalsScreen> {
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final body = ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box('animals').listenable(),
      builder: (_, _, _) => ValueListenableBuilder<Box<dynamic>>(
        valueListenable: Hive.box('milk_records').listenable(),
        builder: (_, _, _) => _content(context),
      ),
    );

    if (!widget.standalone) return body;

    return Scaffold(
      backgroundColor: Ink.canvasTop,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(_tab == 0 ? 'All Cows' : 'All Calves'),
        leading: const _BackButton(),
      ),
      body: body,
    );
  }

  Widget _content(BuildContext context) {
    final type = _tab == 0 ? 'cow' : 'calf';
    final list = animalsBy(type);
    final isCow = type == 'cow';

    // Rank is only meaningful for cows, and only for the current month.
    final ranked = isCow ? topCowRankings() : const <Map<String, dynamic>>[];
    final rankByName = <String, int>{};
    for (int i = 0; i < ranked.length; i++) {
      rankByName[txt(ranked[i], 'name')] = i + 1;
    }

    final podium = <Map<String, dynamic>>[];
    final rest = <Map<String, dynamic>>[];
    for (final a in list) {
      if (rankByName.containsKey(txt(a, 'name'))) {
        podium.add(a);
      } else {
        rest.add(a);
      }
    }
    podium.sort(
      (a, b) =>
          rankByName[txt(a, 'name')]!.compareTo(rankByName[txt(b, 'name')]!),
    );

    int reveal = 0;

    return Shell(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          Gold.s21,
          widget.standalone ? Gold.s55 : Gold.s21,
          Gold.s21,
          _MainShellState.bottomInset,
        ),
        children: [
          Reveal(
            index: reveal++,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cows & Calves',
                        style: TextStyle(
                          fontSize: Gold.t27,
                          fontWeight: FontWeight.w900,
                          color: Ink.navy,
                          height: 1.1,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: Gold.s2),
                      Text(
                        isCow
                            ? 'Top performing cows this month'
                            : 'Every calf on the ranch',
                        style: const TextStyle(
                          color: Ink.muted,
                          fontSize: Gold.t13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gold.s13),
                Glass(
                  radius: Gold.r21,
                  blur: Gold.s13,
                  padding: const EdgeInsets.all(Gold.s13),
                  elevation: 0.8,
                  onTap: () => guardedPush(
                    context,
                    allowed: canEditAnimals,
                    message: 'Only admins and editors can add cows or calves',
                    page: AddAnimalScreen(type: type),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Ink.violetDeep,
                    size: Gold.t21,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gold.s21),
          Reveal(
            index: reveal++,
            child: Glass(
              radius: Gold.r27,
              blur: Gold.s13,
              padding: const EdgeInsets.all(Gold.s5),
              elevation: 0.62,
              child: LiquidSegmentBar(
                labels: const ['Cows', 'Calves'],
                index: _tab,
                onChanged: (value) => setState(() => _tab = value),
              ),
            ),
          ),
          const SizedBox(height: Gold.s21),
          if (list.isEmpty)
            Reveal(
              index: reveal++,
              child: EmptyNote(
                icon: Icons.add_circle_outline_rounded,
                title: isCow ? 'No cows yet' : 'No calves yet',
                message: isCow
                    ? 'Add your first cow to start tracking milk, health and ranking.'
                    : 'Calves appear here once you add one or record a birth.',
              ),
            ),
          for (final a in podium)
            Reveal(
              index: reveal++,
              child: RankedCowCard(
                animal: a,
                rank: rankByName[txt(a, 'name')]!,
              ),
            ),
          if (podium.isNotEmpty && rest.isNotEmpty) ...[
            const SizedBox(height: Gold.s8),
            Reveal(
              index: reveal++,
              child: const SectionTitle(title: 'All Animals'),
            ),
          ],
          for (final a in rest)
            Reveal(
              index: reveal++,
              child: PlainAnimalCard(animal: a),
            ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: Gold.s8),
      child: SizedBox.square(
        dimension: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.74),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.84),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Ink.violetDeep.withValues(alpha: 0.13),
                blurRadius: Gold.s13,
                offset: const Offset(0, Gold.s5),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: const Icon(
                Icons.arrow_back_rounded,
                size: Gold.t21,
                color: Ink.violetDeep,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Ranked card
// -----------------------------------------------------------------------------

/// The podium card: metallic wash, ribboned rosette, portrait, and a stat strip
/// splitting milk, lactation and age into equal thirds.
class RankedCowCard extends StatefulWidget {
  final Map<String, dynamic> animal;
  final int rank;

  const RankedCowCard({super.key, required this.animal, required this.rank});

  @override
  State<RankedCowCard> createState() => _RankedCowCardState();
}

class _RankedCowCardState extends State<RankedCowCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 9))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.animal;
    final rank = widget.rank;
    final name = txt(a, 'name');
    final palette = rankPalette(rank);
    final birthday = isBirthdayToday(a);

    const photo = Gold.s89;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gold.s13),
      child: Pressable(
        radius: Gold.r27,
        onTap: () => push(context, AnimalProfileScreen(animalKey: a['key'])),
        child: Container(
          decoration: ShapeDecoration(
            shape: const SquircleBorder(radius: Gold.r27),
            image: DecorationImage(
              image: AssetImage(rankBackgroundAsset(rank)),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
            shadows: [
              BoxShadow(
                color: palette[2].withValues(alpha: 0.34),
                blurRadius: Gold.s21,
                offset: const Offset(0, Gold.s8),
              ),
            ],
          ),
          child: ClipPath(
            clipper: const SquircleClipper(Gold.r27),
            child: CustomPaint(
              foregroundPainter: const _GlassSkinPainter(
                radius: Gold.r27,
                strength: 0.72,
                sheen: false,
              ),
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => CustomPaint(
                    painter: RankTexturePainter(rank: rank, progress: _c.value),
                    child: Padding(
                      padding: const EdgeInsets.all(Gold.s16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: photo,
                                height: photo,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withValues(
                                          alpha: 0.62,
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.86,
                                          ),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: palette[2].withValues(
                                              alpha: 0.30,
                                            ),
                                            blurRadius: Gold.s13,
                                            offset: const Offset(0, Gold.s5),
                                          ),
                                        ],
                                      ),
                                      child: _AnimalPortrait(
                                        animal: a,
                                        size: photo - 8,
                                      ),
                                    ),
                                    Positioned(
                                      left: -Gold.s8,
                                      top: -Gold.s5,
                                      child: Rosette(
                                        rank: rank,
                                        size: Gold.s34,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: Gold.s16),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Gold.s13,
                                    vertical: Gold.s8,
                                  ),
                                  decoration: ShapeDecoration(
                                    shape: SquircleBorder(
                                      radius: Gold.r13,
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.74,
                                        ),
                                      ),
                                    ),
                                    color: Colors.white.withValues(alpha: 0.84),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: Gold.t21,
                                          fontWeight: FontWeight.w900,
                                          color: Ink.navy,
                                          height: 1.15,
                                          letterSpacing: -0.4,
                                        ),
                                      ),
                                      Text(
                                        '#${txt(a, 'id')}',
                                        style: const TextStyle(
                                          fontSize: Gold.t13,
                                          fontWeight: FontWeight.w800,
                                          color: Ink.navy,
                                        ),
                                      ),
                                      if (birthday) ...[
                                        const SizedBox(height: Gold.s5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: Gold.s8,
                                            vertical: Gold.s2,
                                          ),
                                          decoration: ShapeDecoration(
                                            shape: const SquircleBorder(
                                              radius: Gold.r8,
                                            ),
                                            color: Ink.lavender,
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.cake_rounded,
                                                size: 11,
                                                color: Ink.violetDeep,
                                              ),
                                              SizedBox(width: Gold.s3),
                                              Text(
                                                'Birthday today',
                                                style: TextStyle(
                                                  fontSize: Gold.t10,
                                                  fontWeight: FontWeight.w900,
                                                  color: Ink.violetDeep,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Gold.s13),
                          _StatStrip(
                            entries: [
                              _StatEntry(
                                'Milk',
                                '${cowMilkForPeriod(name, 'This Month').toStringAsFixed(1)} L',
                              ),
                              _StatEntry(
                                'Lactation',
                                '${lactationCount(name)}',
                              ),
                              _StatEntry('Age', ageShort(a)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatEntry {
  final String label;
  final String value;
  const _StatEntry(this.label, this.value);
}

class _StatStrip extends StatelessWidget {
  final List<_StatEntry> entries;
  const _StatStrip({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Gold.s8),
      decoration: ShapeDecoration(
        shape: SquircleBorder(
          radius: Gold.r13,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
        ),
        color: Colors.white.withValues(alpha: 0.84),
      ),
      child: Row(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: Gold.s21,
                color: Ink.navy.withValues(alpha: 0.13),
              ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    entries[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Gold.t10,
                      fontWeight: FontWeight.w700,
                      color: Ink.navy.withValues(alpha: 0.78),
                    ),
                  ),
                  const SizedBox(height: Gold.s2),
                  Text(
                    entries[i].value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: Gold.t13,
                      fontWeight: FontWeight.w900,
                      color: Ink.navy,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The unranked list row.
class PlainAnimalCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  const PlainAnimalCard({super.key, required this.animal});

  @override
  Widget build(BuildContext context) {
    final a = animal;
    final isCow = txt(a, 'type') == 'cow';
    final status = displayStatus(a);

    return Glass(
      radius: Gold.r27,
      margin: const EdgeInsets.only(bottom: Gold.s13),
      padding: const EdgeInsets.all(Gold.s16),
      elevation: 0.8,
      onTap: () => push(context, AnimalProfileScreen(animalKey: a['key'])),
      child: Row(
        children: [
          AnimalAvatar(animal: a, radius: Gold.s27),
          const SizedBox(width: Gold.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        txt(a, 'name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: Gold.t16,
                          fontWeight: FontWeight.w900,
                          color: Ink.navy,
                        ),
                      ),
                    ),
                    const SizedBox(width: Gold.s5),
                    Text(
                      '#${txt(a, 'id')}',
                      style: const TextStyle(
                        fontSize: Gold.t11,
                        fontWeight: FontWeight.w700,
                        color: Ink.faint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gold.s2),
                Text(
                  txt(a, 'breed', 'Unknown breed'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Ink.muted,
                    fontSize: Gold.t11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Gold.s2),
                Text(
                  isCow
                      ? 'Age ${ageShort(a)} \u2022 In farm ${durationText(txt(a, 'arrivalDate'))}'
                      : 'Age ${ageShort(a)} \u2022 Mother ${txt(a, 'mother', 'Unknown')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Ink.muted,
                    fontSize: Gold.t10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Gold.s8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gold.s8,
                  vertical: Gold.s3,
                ),
                decoration: ShapeDecoration(
                  shape: const SquircleBorder(radius: Gold.r8),
                  color: statusColor(status).withValues(alpha: 0.14),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: Gold.t10,
                    fontWeight: FontWeight.w900,
                    color: statusColor(status),
                  ),
                ),
              ),
              const SizedBox(height: Gold.s5),
              const Icon(
                Icons.chevron_right_rounded,
                color: Ink.faint,
                size: Gold.t21,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
//  PART 10 — ANIMAL PROFILE
// =============================================================================

class AnimalProfileScreen extends StatefulWidget {
  final dynamic animalKey;
  const AnimalProfileScreen({super.key, required this.animalKey});

  @override
  State<AnimalProfileScreen> createState() => _AnimalProfileScreenState();
}

class _AnimalProfileScreenState extends State<AnimalProfileScreen> {
  int _tab = 0;
  static const List<String> _tabs = ['Overview', 'Health', 'Milk', 'History'];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box('animals').listenable(),
      builder: (_, _, _) {
        final raw = Hive.box('animals').get(widget.animalKey);
        if (raw == null) {
          return Scaffold(
            appBar: AppBar(leading: const _BackButton()),
            body: const Shell(
              child: Center(
                child: EmptyNote(
                  icon: Icons.search_off_rounded,
                  title: 'Animal not found',
                  message: 'This record may have been removed or synced away.',
                ),
              ),
            ),
          );
        }

        final a = withKey(widget.animalKey, raw);
        final isCow = txt(a, 'type') == 'cow';
        final name = txt(a, 'name');
        final pregnantDate = txt(a, 'pregnancyStartDate');
        final stopDate = txt(a, 'milkingStopDate');

        return ValueListenableBuilder<Box<dynamic>>(
          valueListenable: Hive.box('milk_records').listenable(),
          builder: (_, _, _) => ValueListenableBuilder<Box<dynamic>>(
            valueListenable: Hive.box('doctor_records').listenable(),
            builder: (_, _, _) {
              Widget content;
              if (_tab == 0) {
                content = _overview(
                  context,
                  a,
                  isCow,
                  name,
                  pregnantDate,
                  stopDate,
                );
              } else if (_tab == 1) {
                content = _health(
                  name,
                  pregnantDate,
                  stopDate,
                  txt(a, 'pregnancyInjection'),
                );
              } else if (_tab == 2) {
                content = _milk(name);
              } else {
                content = _history(name);
              }

              return Scaffold(
                backgroundColor: Ink.canvasTop,
                extendBodyBehindAppBar: true,
                appBar: AppBar(
                  title: Text(isCow ? 'Cow Profile' : 'Calf Profile'),
                  leading: const _BackButton(),
                  actions: [
                    _ProfileMenu(
                      animalKey: widget.animalKey,
                      type: txt(a, 'type'),
                    ),
                    const SizedBox(width: Gold.s8),
                  ],
                ),
                body: Shell(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Gold.s21,
                      Gold.s55,
                      Gold.s21,
                      Gold.s55,
                    ),
                    children: [
                      Reveal(index: 0, child: _header(context, a, isCow, name)),
                      const SizedBox(height: Gold.s16),
                      Reveal(index: 1, child: _tabBar()),
                      const SizedBox(height: Gold.s16),
                      Reveal(index: 2, child: content),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _header(
    BuildContext context,
    Map<String, dynamic> a,
    bool isCow,
    String name,
  ) {
    final rank = isCow ? cowRank(name) : 0;
    final status = displayStatus(a);

    return Glass(
      radius: Gold.r34,
      padding: const EdgeInsets.all(Gold.s16),
      elevation: 1.1,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimalAvatar(animal: a, radius: Gold.s34),
          const SizedBox(width: Gold.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: Gold.t21,
                          fontWeight: FontWeight.w900,
                          color: Ink.navy,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gold.s8,
                        vertical: Gold.s3,
                      ),
                      decoration: ShapeDecoration(
                        shape: const SquircleBorder(radius: Gold.r8),
                        color: Ink.violet.withValues(alpha: 0.13),
                      ),
                      child: Text(
                        '#${txt(a, 'id')}',
                        style: const TextStyle(
                          color: Ink.violetDeep,
                          fontWeight: FontWeight.w900,
                          fontSize: Gold.t10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gold.s3),
                Text(
                  '${txt(a, 'breed', 'Unknown breed')} \u2022 ${txt(a, 'gender', isCow ? 'Female' : 'Not set')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Ink.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: Gold.t11,
                  ),
                ),
                Text(
                  'Age ${ageText(a)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: Gold.t11,
                    color: Ink.body,
                  ),
                ),
                const SizedBox(height: Gold.s5),
                Wrap(
                  spacing: Gold.s5,
                  runSpacing: Gold.s5,
                  children: [
                    _Chip(label: status, color: statusColor(status)),
                    if (rank > 0)
                      _Chip(
                        label: 'Rank #$rank \u2022 ${rankLabel(rank)}',
                        color: rankColor(rank),
                      ),
                    if (isBirthdayToday(a))
                      const _Chip(label: 'Birthday today', color: Ink.violet),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Glass(
      radius: Gold.r21,
      blur: Gold.s13,
      padding: const EdgeInsets.all(Gold.s5),
      elevation: 0.62,
      child: LiquidSegmentBar(
        labels: _tabs,
        index: _tab,
        onChanged: (value) => setState(() => _tab = value),
      ),
    );
  }

  Widget _metric(String title, String value, IconData icon, Color color) {
    return Glass(
      radius: Gold.r21,
      padding: const EdgeInsets.all(Gold.s13),
      elevation: 0.62,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: Gold.s27,
            height: Gold.s27,
            decoration: ShapeDecoration(
              shape: SquircleBorder(
                radius: Gold.concentric(Gold.r21, Gold.s13),
              ),
              color: color.withValues(alpha: 0.13),
            ),
            child: Icon(icon, color: color, size: Gold.t13),
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Ink.muted,
              fontSize: Gold.t10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Gold.s2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: Gold.t16,
              fontWeight: FontWeight.w900,
              color: Ink.navy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _overview(
    BuildContext context,
    Map<String, dynamic> a,
    bool isCow,
    String name,
    String pregnantDate,
    String stopDate,
  ) {
    final milkForCow = milkRows().where((r) => txt(r, 'cow') == name).toList();
    final lastMilk = milkForCow.isEmpty
        ? 0.0
        : numv(milkForCow.first, 'quantity');

    return Column(
      children: [
        if (isCow) ...[
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: Gold.s13,
            mainAxisSpacing: Gold.s13,
            childAspectRatio: Gold.phi,
            children: [
              _metric(
                'Today Milk',
                '${cowMilkToday(name).toStringAsFixed(1)} L',
                Icons.water_drop_rounded,
                Ink.violet,
              ),
              _metric(
                'Last Entry',
                milkForCow.isEmpty
                    ? 'No record'
                    : '${lastMilk.toStringAsFixed(1)} L',
                Icons.history_rounded,
                Ink.amber,
              ),
              _metric(
                'This Month',
                '${cowMilkForPeriod(name, 'This Month').toStringAsFixed(1)} L',
                Icons.calendar_month_rounded,
                Ink.green,
              ),
              _metric(
                'Lactation',
                '${lactationCount(name)}',
                Icons.child_care_rounded,
                Ink.violetDeep,
              ),
            ],
          ),
          const SizedBox(height: Gold.s16),
        ],
        InfoRow(
          title: 'Last Doctor Visit',
          value: lastDoctor(name),
          icon: Icons.medical_services_rounded,
          color: Ink.blue,
        ),
        if (pregnantDate.isNotEmpty) ...[
          const SizedBox(height: Gold.s13),
          InfoRow(
            title: 'Pregnancy Duration',
            value: '${daysSince(pregnantDate)} days',
            icon: Icons.favorite_rounded,
            color: Ink.amber,
          ),
        ],
        if (stopDate.isNotEmpty) ...[
          const SizedBox(height: Gold.s13),
          InfoRow(
            title: 'Milking Stopped',
            value: '${daysSince(stopDate)} days ago',
            icon: Icons.pause_circle_rounded,
            color: Ink.red,
          ),
        ],
        if (txt(a, 'notes').isNotEmpty) ...[
          const SizedBox(height: Gold.s13),
          Glass(
            radius: Gold.r21,
            padding: const EdgeInsets.all(Gold.s16),
            elevation: 0.62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notes',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Ink.navy,
                    fontSize: Gold.t13,
                  ),
                ),
                const SizedBox(height: Gold.s5),
                Text(
                  txt(a, 'notes'),
                  style: const TextStyle(
                    color: Ink.body,
                    fontSize: Gold.t13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Gold.s21),
        if (isCow) ...[
          LiquidButton(
            label: 'Add Milk Record',
            icon: Icons.add_rounded,
            onPressed: () => guardedPush(
              context,
              allowed: canRecordEntries,
              message: 'Your ranch role does not allow adding milk records',
              page: AddEntryScreen(initialCow: name),
            ),
          ),
          const SizedBox(height: Gold.s13),
        ],
        LiquidButton(
          label: 'Add Doctor Visit',
          icon: Icons.medical_services_rounded,
          start: Ink.blue,
          end: Ink.violetDeep,
          onPressed: () => guardedPush(
            context,
            allowed: canRecordEntries,
            message: 'Your ranch role does not allow adding doctor visits',
            page: DoctorScreen(animalKey: widget.animalKey),
          ),
        ),
        if (isCow && pregnantDate.isNotEmpty && stopDate.isEmpty) ...[
          const SizedBox(height: Gold.s13),
          LiquidButton(
            label: 'Stop Milking',
            icon: Icons.pause_rounded,
            start: Ink.red,
            end: const Color(0xFFA82638),
            onPressed: () {
              if (!canRecordEntries) {
                snack(
                  context,
                  'Your ranch role does not allow pregnancy updates',
                );
                return;
              }
              updateAnimal(a, {'milkingStopDate': todayDate()});
              snack(context, 'Milking stopped for $name');
            },
          ),
        ],
        if (txt(a, 'gender', 'Female') == 'Female' &&
            pregnantDate.isNotEmpty) ...[
          const SizedBox(height: Gold.s13),
          LiquidButton(
            label: 'Calf Born',
            icon: Icons.child_care_rounded,
            start: Ink.green,
            end: const Color(0xFF1B7A4A),
            onPressed: () => guardedPush(
              context,
              allowed: canEditAnimals,
              message: 'Only admins and editors can register a newborn calf',
              page: CalfBornScreen(motherKey: widget.animalKey),
            ),
          ),
        ],
      ],
    );
  }

  Widget _health(
    String name,
    String pregnantDate,
    String stopDate,
    String injection,
  ) {
    final doctors = doctorRows()
        .where((r) => txt(r, 'cow') == name)
        .take(20)
        .toList();

    return Column(
      children: [
        if (pregnantDate.isNotEmpty) ...[
          InfoRow(
            title: 'Pregnancy Injection',
            value: injection.isEmpty ? 'Not recorded' : injection,
            icon: Icons.vaccines_rounded,
            color: Ink.amber,
          ),
          const SizedBox(height: Gold.s13),
          InfoRow(
            title: 'Pregnancy Duration',
            value: '${daysSince(pregnantDate)} days',
            icon: Icons.favorite_rounded,
            color: Ink.violet,
          ),
        ],
        if (stopDate.isNotEmpty) ...[
          const SizedBox(height: Gold.s13),
          InfoRow(
            title: 'Milking Stop Duration',
            value: '${daysSince(stopDate)} days',
            icon: Icons.pause_circle_rounded,
            color: Ink.red,
          ),
        ],
        const SizedBox(height: Gold.s16),
        panel('Health Records', 'No doctor records yet.', [
          for (final r in doctors)
            _RecordLine(
              icon: Icons.medical_services_rounded,
              color: Ink.blue,
              title: '${txt(r, 'type')} \u2022 ${money(numv(r, 'cost'))}',
              subtitle:
                  '${txt(r, 'problem')}${txt(r, 'injection').isEmpty ? '' : ' \u2022 ${txt(r, 'injection')}'}\n${txt(r, 'date')} \u2022 ${txt(r, 'time')}',
            ),
        ]),
      ],
    );
  }

  Widget _milk(String name) {
    final milk = milkRows()
        .where((r) => txt(r, 'cow') == name)
        .take(30)
        .toList();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: InfoRow(
                title: 'Today',
                value: '${cowMilkToday(name).toStringAsFixed(1)} L',
                icon: Icons.water_drop_rounded,
                color: Ink.violet,
              ),
            ),
            const SizedBox(width: Gold.s13),
            Expanded(
              child: InfoRow(
                title: 'Month',
                value:
                    '${cowMilkForPeriod(name, 'This Month').toStringAsFixed(1)} L',
                icon: Icons.calendar_month_rounded,
                color: Ink.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gold.s16),
        panel('Milk History', 'No milk records yet.', [
          for (final r in milk)
            _RecordLine(
              icon: Icons.water_drop_rounded,
              color: Ink.violet,
              title:
                  '${numv(r, 'quantity').toStringAsFixed(1)} L \u2022 ${txt(r, 'session')}',
              subtitle: '${txt(r, 'date')} \u2022 ${txt(r, 'time')}',
            ),
        ]),
      ],
    );
  }

  Widget _history(String name) {
    final births = calvingRows()
        .where((r) => txt(r, 'mother') == name || txt(r, 'calfName') == name)
        .take(20)
        .toList();
    final sales = saleRows()
        .where((r) => txt(r, 'animal') == name)
        .take(20)
        .toList();
    final deaths = deathRows().where((r) => txt(r, 'animal') == name).toList();

    return Column(
      children: [
        panel('Birth / Calving History', 'No calving records.', [
          for (final r in births)
            _RecordLine(
              icon: Icons.child_care_rounded,
              color: Ink.amber,
              title: '${txt(r, 'calfName')} \u2022 ${txt(r, 'gender')}',
              subtitle: '${txt(r, 'date')} \u2022 Mother ${txt(r, 'mother')}',
            ),
        ]),
        const SizedBox(height: Gold.s16),
        panel('Sale History', 'No sale records.', [
          for (final r in sales)
            _RecordLine(
              icon: Icons.sell_rounded,
              color: Ink.green,
              title: '${txt(r, 'category')} \u2022 ${money(numv(r, 'amount'))}',
              subtitle: '${txt(r, 'date')} \u2022 ${txt(r, 'notes', '-')}',
            ),
        ]),
        if (deaths.isNotEmpty) ...[
          const SizedBox(height: Gold.s16),
          panel('Loss Record', '', [
            for (final r in deaths)
              _RecordLine(
                icon: Icons.warning_amber_rounded,
                color: Ink.red,
                title: '${txt(r, 'reason')} \u2022 ${money(numv(r, 'cost'))}',
                subtitle: '${txt(r, 'date')} \u2022 ${txt(r, 'notes', '-')}',
              ),
          ]),
        ],
      ],
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  final dynamic animalKey;
  final String type;

  const _ProfileMenu({required this.animalKey, required this.type});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded, color: Ink.violetDeep),
      shape: const SquircleBorder(radius: Gold.r21),
      color: Colors.white,
      onSelected: (value) {
        switch (value) {
          case 'edit':
            guardedPush(
              context,
              allowed: canEditAnimals,
              message: 'Only admins and editors can edit animals',
              page: AddAnimalScreen(type: type, animalKey: animalKey),
            );
            break;
          case 'sell':
            guardedPush(
              context,
              allowed: canEditAnimals,
              message: 'Only admins and editors can sell animals',
              page: SellAnimalScreen(animalKey: animalKey),
            );
            break;
          case 'died':
            guardedPush(
              context,
              allowed: canEditAnimals,
              message: 'Only admins and editors can update animal status',
              page: DeathScreen(animalKey: animalKey),
            );
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: Gold.t16, color: Ink.violetDeep),
              SizedBox(width: Gold.s8),
              Text('Edit details'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'sell',
          child: Row(
            children: [
              Icon(Icons.sell_rounded, size: Gold.t16, color: Ink.green),
              SizedBox(width: Gold.s8),
              Text('Record sale'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'died',
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: Gold.t16, color: Ink.red),
              SizedBox(width: Gold.s8),
              Text('Record death'),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Gold.s8,
        vertical: Gold.s3,
      ),
      decoration: ShapeDecoration(
        shape: const SquircleBorder(radius: Gold.r8),
        color: color.withValues(alpha: 0.14),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: Gold.t10,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _RecordLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _RecordLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gold.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: Gold.s27,
            height: Gold.s27,
            decoration: ShapeDecoration(
              shape: const SquircleBorder(radius: Gold.r8),
              color: color.withValues(alpha: 0.13),
            ),
            child: Icon(icon, size: Gold.t13, color: color),
          ),
          const SizedBox(width: Gold.s13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: Gold.t13,
                    color: Ink.navy,
                  ),
                ),
                const SizedBox(height: Gold.s2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Ink.muted,
                    fontSize: Gold.t10,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
//  PART 11 — FORMS
// =============================================================================

/// Shared chrome for every data-entry screen.
class FormPage extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const FormPage({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(title), leading: const _BackButton()),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Gold.s21,
            Gold.s55,
            Gold.s21,
            Gold.s55,
          ),
          children: [
            for (int i = 0; i < children.length; i++)
              Reveal(index: i, child: children[i]),
          ],
        ),
      ),
    );
  }
}

/// A read-only date field that opens the picker on tap.
class SuggestionField extends StatefulWidget {
  final TextEditingController controller;
  final List<String> suggestions;
  final String label;
  final IconData icon;
  final ValueChanged<String>? onSelected;

  const SuggestionField({
    super.key,
    required this.controller,
    required this.suggestions,
    required this.label,
    required this.icon,
    this.onSelected,
  });

  @override
  State<SuggestionField> createState() => _SuggestionFieldState();
}

class _SuggestionFieldState extends State<SuggestionField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (option) => option,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        return widget.suggestions.where(
          (option) => query.isEmpty || option.toLowerCase().contains(query),
        );
      },
      onSelected: (value) {
        widget.controller.text = value;
        widget.controller.selection = TextSelection.collapsed(
          offset: value.length,
        );
        widget.onSelected?.call(value);
      },
      fieldViewBuilder: (_, controller, focusNode, onSubmitted) => TextField(
        controller: controller,
        focusNode: focusNode,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => onSubmitted(),
        decoration: fieldStyle(widget.label, icon: widget.icon),
      ),
      optionsViewBuilder: (_, onSelected, options) {
        final choices = options.take(6).toList();
        if (choices.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 260),
              child: Glass(
                radius: Gold.r21,
                blur: Gold.s21,
                opacity: 0.92,
                padding: const EdgeInsets.symmetric(vertical: Gold.s5),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: choices.length,
                  itemBuilder: (_, index) => ListTile(
                    dense: true,
                    leading: Icon(
                      widget.icon,
                      color: Ink.violet,
                      size: Gold.t16,
                    ),
                    title: Text(
                      choices[index],
                      style: const TextStyle(
                        color: Ink.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => onSelected(choices[index]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class DateField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool clearable;
  final VoidCallback onChanged;

  const DateField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.clearable = false,
  });

  @override
  Widget build(BuildContext context) {
    Future<void> pick() async {
      final picked = await chooseDate(context, controller.text);
      if (picked != null) {
        controller.text = picked;
        onChanged();
      }
    }

    return TextField(
      controller: controller,
      readOnly: true,
      onTap: pick,
      decoration: fieldStyle(
        label,
        icon: Icons.event_rounded,
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (clearable && controller.text.isNotEmpty)
              IconButton(
                splashRadius: Gold.s21,
                icon: const Icon(
                  Icons.close_rounded,
                  size: Gold.t16,
                  color: Ink.muted,
                ),
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
              ),
            IconButton(
              splashRadius: Gold.s21,
              icon: const Icon(
                Icons.calendar_month_rounded,
                size: Gold.t21,
                color: Ink.violet,
              ),
              onPressed: pick,
            ),
          ],
        ),
      ),
    );
  }
}

/// Age entry for animals with no known date of birth.
class AgeSelector extends StatelessWidget {
  final bool enabled;
  final int years;
  final int months;
  final int days;
  final void Function(int y, int m, int d) onChanged;

  const AgeSelector({
    super.key,
    required this.enabled,
    required this.years,
    required this.months,
    required this.days,
    required this.onChanged,
  });

  String get _current {
    if (years > 0) return '$years Years';
    if (months > 0) return '$months Months';
    if (days > 0) return '$days Days';
    return 'Not set';
  }

  List<String> get _options {
    final list = <String>[
      'Not set',
      'New born',
      ...List<String>.generate(24, (i) => '${i + 1} Months'),
      ...List<String>.generate(30, (i) => '${i + 1} Years'),
    ];
    if (!list.contains(_current)) list.add(_current);
    return list;
  }

  void _apply(String value) {
    if (value == 'Not set') return onChanged(0, 0, 0);
    if (value == 'New born') return onChanged(0, 0, 1);
    final n = int.tryParse(value.split(' ').first) ?? 0;
    if (value.contains('Year')) return onChanged(n, 0, 0);
    if (value.contains('Month')) return onChanged(0, n, 0);
    onChanged(0, 0, n);
  }

  @override
  Widget build(BuildContext context) {
    final values = _options;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: IgnorePointer(
        ignoring: !enabled,
        child: DropdownButtonFormField<String>(
          initialValue: values.contains(_current) ? _current : 'Not set',
          isExpanded: true,
          borderRadius: BorderRadius.circular(Gold.r21),
          decoration: fieldStyle(
            enabled ? 'Age' : 'Age calculated from date of birth',
            icon: Icons.cake_outlined,
          ),
          items: [
            for (final v in values)
              DropdownMenuItem<String>(value: v, child: Text(v)),
          ],
          onChanged: (v) {
            if (v != null) _apply(v);
          },
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Add / edit animal
// -----------------------------------------------------------------------------

class AddAnimalScreen extends StatefulWidget {
  final String type;
  final dynamic animalKey;

  const AddAnimalScreen({super.key, required this.type, this.animalKey});

  @override
  State<AddAnimalScreen> createState() => _AddAnimalScreenState();
}

class _AddAnimalScreenState extends State<AddAnimalScreen> {
  final _name = TextEditingController();
  final _dob = TextEditingController();
  final _purchase = TextEditingController();
  final _arrival = TextEditingController(text: todayDate());
  final _notes = TextEditingController();
  final _imageUrl = TextEditingController();

  String _imageData = '';
  String _breed = breeds.first;
  String _mother = 'Unknown Mother';
  String _source = 'Existing';
  String _gender = 'Female';
  int _y = 0, _m = 0, _d = 0;
  bool _saving = false;
  bool _pickingPhoto = false;

  bool get _edit => widget.animalKey != null;

  @override
  void initState() {
    super.initState();

    if (widget.type == 'calf') {
      _source = 'Born';
      _dob.text = todayDate();
      _arrival.text = todayDate();
    }

    if (_edit) {
      final raw = Hive.box('animals').get(widget.animalKey);
      if (raw != null) {
        final a = asMap(raw);
        _name.text = txt(a, 'name');
        _breed = breeds.contains(txt(a, 'breed'))
            ? txt(a, 'breed')
            : breeds.first;
        _dob.text = txt(a, 'dob');
        _y = toInt(a['ageYears']);
        _m = toInt(a['ageMonths']);
        _d = toInt(a['ageDays']);
        _mother = motherNames().contains(txt(a, 'mother'))
            ? txt(a, 'mother')
            : 'Unknown Mother';
        _source = txt(a, 'source', widget.type == 'calf' ? 'Born' : 'Existing');
        final storedGender = txt(a, 'gender', 'Female');
        _gender = const ['Female', 'Male'].contains(storedGender)
            ? storedGender
            : 'Female';
        _arrival.text = txt(a, 'arrivalDate', todayDate());
        _purchase.text = numv(a, 'purchaseAmount') > 0
            ? numv(a, 'purchaseAmount').toStringAsFixed(0)
            : '';
        _notes.text = txt(a, 'notes');
        _imageUrl.text = txt(a, 'imageUrl');
        _imageData = txt(a, 'imageData');
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dob.dispose();
    _purchase.dispose();
    _arrival.dispose();
    _notes.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  bool _isDuplicate(String candidate) {
    for (final a in animals(all: true)) {
      if (_edit && a['key'] == widget.animalKey) continue;
      if (txt(a, 'name').toLowerCase() == candidate.toLowerCase()) return true;
    }
    return false;
  }

  Future<void> _save() async {
    if (!canEditAnimals) {
      snack(context, 'Only admins and editors can save animal details');
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      snack(context, 'Please enter a name');
      return;
    }
    if (_isDuplicate(name)) {
      snack(context, 'An animal named "$name" already exists');
      return;
    }

    setState(() => _saving = true);
    try {
      final raw = _edit
          ? asMap(Hive.box('animals').get(widget.animalKey))
          : <String, dynamic>{};
      final amount = toDouble(_purchase.text);
      final arrival = _arrival.text.trim().isEmpty
          ? todayDate()
          : _arrival.text.trim();
      final hasDob = _dob.text.trim().isNotEmpty;

      final data = <String, dynamic>{
        'type': widget.type,
        'name': name,
        'id': _edit ? txt(raw, 'id') : nextId(widget.type),
        'breed': _breed,
        'dob': _dob.text.trim(),
        'ageYears': hasDob ? 0 : _y,
        'ageMonths': hasDob ? 0 : _m,
        'ageDays': hasDob ? 0 : _d,
        'status': _edit ? txt(raw, 'status', 'Active') : 'Active',
        'mother': widget.type == 'calf' ? _mother : '',
        'arrivalDate': arrival,
        'source': _source,
        'purchaseAmount': amount,
        'gender': widget.type == 'calf' ? _gender : 'Female',
        'pregnancyStartDate': _edit ? txt(raw, 'pregnancyStartDate') : '',
        'pregnancyInjection': _edit ? txt(raw, 'pregnancyInjection') : '',
        'milkingStopDate': _edit ? txt(raw, 'milkingStopDate') : '',
        'notes': _notes.text.trim(),
        'imageUrl': _imageUrl.text.trim(),
        'imageData': _imageData,
        // Keep the original author on an edit rather than reassigning the record.
        'addedBy': _edit
            ? txt(raw, 'addedBy', currentUserName())
            : currentUserName(),
      };

      if (_edit) {
        // Merge, so sync bookkeeping this form knows nothing about survives.
        await Hive.box('animals').put(widget.animalKey, {...raw, ...data});
      } else {
        await Hive.box('animals').add(data);
        if (_source == 'Purchased' && amount > 0) {
          await Hive.box('purchase_records').add({
            'animal': name,
            'type': widget.type == 'cow' ? 'Cow Purchase' : 'Calf Purchase',
            'amount': amount,
            'date': arrival,
            'notes': _notes.text.trim(),
            'addedBy': currentUserName(),
            'createdAt': DateTime.now().toIso8601String(),
          });
        }
      }

      AutoSyncService.scheduleSync(reason: 'animal saved');
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) snack(context, 'Could not save animal. Please try again');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _photoPicker(bool isCow) {
    Widget preview;
    final url = _imageUrl.text.trim();

    if (_imageData.startsWith('data:image')) {
      preview = ClipPath(
        clipper: const SquircleClipper(Gold.r21),
        child: Image.memory(
          base64Decode(_imageData.split(',').last),
          width: Gold.s89,
          height: Gold.s89,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const CowMark(size: Gold.s89),
        ),
      );
    } else if (url.startsWith('http://') || url.startsWith('https://')) {
      preview = ClipPath(
        clipper: const SquircleClipper(Gold.r21),
        child: Image.network(
          url,
          width: Gold.s89,
          height: Gold.s89,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const CowMark(size: Gold.s89),
        ),
      );
    } else {
      preview = const CowMark(size: Gold.s89);
    }

    return Glass(
      radius: Gold.r27,
      padding: const EdgeInsets.all(Gold.s16),
      elevation: 0.62,
      child: Row(
        children: [
          SizedBox(width: Gold.s89, height: Gold.s89, child: preview),
          const SizedBox(width: Gold.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCow ? 'Cow Photo' : 'Calf Photo',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Ink.navy,
                    fontSize: Gold.t13,
                  ),
                ),
                const SizedBox(height: Gold.s8),
                GhostButton(
                  label: _pickingPhoto ? 'Opening Photos...' : 'Select Photo',
                  icon: _pickingPhoto
                      ? Icons.hourglass_top_rounded
                      : Icons.photo_camera_rounded,
                  onPressed: _pickingPhoto
                      ? null
                      : () async {
                          setState(() => _pickingPhoto = true);
                          try {
                            final picked = await pickImageDataUrl();
                            if (!mounted) return;
                            if (picked == null) {
                              snack(
                                context,
                                'No photo selected. Please allow Photos access and try again',
                              );
                              return;
                            }
                            setState(() {
                              _imageData = picked;
                              _imageUrl.clear();
                            });
                            snack(context, 'Photo selected');
                          } catch (_) {
                            if (mounted) {
                              snack(
                                context,
                                'Could not open Photos. Please try again',
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _pickingPhoto = false);
                            }
                          }
                        },
                ),
                if (_imageData.isNotEmpty || _imageUrl.text.isNotEmpty) ...[
                  const SizedBox(height: Gold.s5),
                  GestureDetector(
                    onTap: () => setState(() {
                      _imageData = '';
                      _imageUrl.clear();
                    }),
                    child: const Text(
                      'Remove photo',
                      style: TextStyle(
                        color: Ink.red,
                        fontWeight: FontWeight.w800,
                        fontSize: Gold.t11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCow = widget.type == 'cow';
    final sources = isCow
        ? const ['Existing', 'Purchased']
        : const ['Born', 'Purchased'];
    if (!sources.contains(_source)) _source = sources.first;
    final hasDob = _dob.text.trim().isNotEmpty;

    final currentId = _edit
        ? txt(asMap(Hive.box('animals').get(widget.animalKey) ?? {}), 'id')
        : nextId(widget.type);

    return FormPage(
      title: _edit
          ? (isCow ? 'Edit Cow' : 'Edit Calf')
          : (isCow ? 'Add Cow' : 'Add Calf'),
      children: [
        Glass(
          radius: Gold.r21,
          padding: const EdgeInsets.all(Gold.s16),
          elevation: 0.62,
          child: Row(
            children: [
              const Icon(
                Icons.badge_outlined,
                color: Ink.violet,
                size: Gold.t21,
              ),
              const SizedBox(width: Gold.s13),
              Text(
                'ID  $currentId',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Ink.navy,
                  fontSize: Gold.t13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: fieldStyle(
            isCow ? 'Cow Name' : 'Calf Name',
            icon: Icons.drive_file_rename_outline_rounded,
          ),
        ),
        const SizedBox(height: Gold.s13),
        DropdownButtonFormField<String>(
          initialValue: _breed,
          isExpanded: true,
          borderRadius: BorderRadius.circular(Gold.r21),
          decoration: fieldStyle('Breed', icon: Icons.category_outlined),
          items: [
            for (final b in breeds)
              DropdownMenuItem<String>(value: b, child: Text(b)),
          ],
          onChanged: (v) => setState(() => _breed = v ?? _breed),
        ),
        const SizedBox(height: Gold.s13),
        Glass(
          radius: Gold.r21,
          blur: Gold.s13,
          padding: const EdgeInsets.all(Gold.s5),
          elevation: 0.62,
          child: LiquidSegmentBar(
            labels: sources,
            index: math.max(0, sources.indexOf(_source)),
            onChanged: (value) => setState(() {
              _source = sources[value];
              if (widget.type == 'calf' &&
                  _source == 'Born' &&
                  _dob.text.isEmpty) {
                _dob.text = todayDate();
              }
            }),
          ),
        ),
        const SizedBox(height: Gold.s13),
        DateField(
          controller: _dob,
          label: 'Date of Birth',
          clearable: true,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: Gold.s13),
        AgeSelector(
          enabled: !hasDob,
          years: _y,
          months: _m,
          days: _d,
          onChanged: (y, m, d) => setState(() {
            _y = y;
            _m = m;
            _d = d;
          }),
        ),
        if (!isCow) ...[
          const SizedBox(height: Gold.s13),
          DropdownButtonFormField<String>(
            initialValue: motherNames().contains(_mother)
                ? _mother
                : 'Unknown Mother',
            isExpanded: true,
            borderRadius: BorderRadius.circular(Gold.r21),
            decoration: fieldStyle(
              'Mother Cow',
              icon: Icons.family_restroom_rounded,
            ),
            items: [
              for (final n in motherNames())
                DropdownMenuItem<String>(value: n, child: Text(n)),
            ],
            onChanged: (v) => setState(() => _mother = v ?? _mother),
          ),
          const SizedBox(height: Gold.s13),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            isExpanded: true,
            borderRadius: BorderRadius.circular(Gold.r21),
            decoration: fieldStyle('Gender', icon: Icons.wc_rounded),
            items: const [
              DropdownMenuItem<String>(value: 'Female', child: Text('Female')),
              DropdownMenuItem<String>(value: 'Male', child: Text('Male')),
            ],
            onChanged: (v) => setState(() => _gender = v ?? _gender),
          ),
        ],
        const SizedBox(height: Gold.s13),
        DateField(
          controller: _arrival,
          label: 'Farm Arrival / Purchase Date',
          onChanged: () => setState(() {}),
        ),
        if (_source == 'Purchased') ...[
          const SizedBox(height: Gold.s13),
          TextField(
            controller: _purchase,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fieldStyle(
              'Purchase Amount',
              icon: Icons.payments_outlined,
            ),
          ),
        ],
        const SizedBox(height: Gold.s13),
        _photoPicker(isCow),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _imageUrl,
          decoration: fieldStyle(
            'Photo URL (optional)',
            icon: Icons.link_rounded,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _notes,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldStyle('Notes (optional)'),
        ),
        const SizedBox(height: Gold.s21),
        LiquidButton(
          label: _edit ? 'Save Changes' : (isCow ? 'Save Cow' : 'Save Calf'),
          icon: Icons.check_rounded,
          busy: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
//  Milk / feed entry
// -----------------------------------------------------------------------------

class AddEntryScreen extends StatefulWidget {
  final String? initialCow;
  const AddEntryScreen({super.key, this.initialCow});

  @override
  State<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<AddEntryScreen> {
  int _mode = 0;
  int _feedTarget = 0;
  int _stockItem = 0;
  String _session = 'Morning';
  String _cow = '';
  bool _saving = false;

  final _date = TextEditingController(text: todayDate());
  final _time = TextEditingController(text: currentTime());
  final _milk = TextEditingController();
  final _qty = TextEditingController();
  final _expenseName = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();

  static const List<String> _stockItems = ['Vaikol', 'Thavudu'];
  static const List<String> _stockIcons = ['dryGrass', 'bag'];

  @override
  void initState() {
    super.initState();
    final cows = cowNames();
    _cow = widget.initialCow ?? (cows.isEmpty ? '' : cows.first);
  }

  @override
  void dispose() {
    _date.dispose();
    _time.dispose();
    _milk.dispose();
    _qty.dispose();
    _expenseName.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!canRecordEntries) {
      snack(context, 'Your ranch role does not allow adding entries');
      return;
    }
    if (_mode == 0) {
      final quantity = toDouble(_milk.text);
      if (_cow.isEmpty) {
        snack(context, 'Please select a cow');
        return;
      }
      if (quantity <= 0) {
        snack(context, 'Please enter the milk quantity');
        return;
      }
      setState(() => _saving = true);
      await Hive.box('milk_records').add({
        'cow': _cow,
        'date': _date.text,
        'time': _time.text,
        'session': _session,
        'quantity': quantity,
        'notes': _notes.text.trim(),
        'addedBy': currentUserName(),
        'createdAt': DateTime.now().toIso8601String(),
      });
    } else if (_mode == 1) {
      final quantity = toDouble(_qty.text);
      if (quantity <= 0) {
        snack(context, 'Please enter the quantity');
        return;
      }
      final item = _stockItems[_stockItem];
      final available = stockBalance(item);
      if (quantity > available) {
        snack(
          context,
          'Only ${available.toStringAsFixed(1)} kg of $item is available',
        );
        return;
      }
      setState(() => _saving = true);
      await Hive.box('stock_records').add({
        'movement': 'Usage',
        'item': item,
        'target': _feedTarget == 0 ? 'Cows' : 'Calves',
        'quantityKg': quantity,
        'unit': 'kg',
        'amount': 0.0,
        'date': _date.text,
        'time': _time.text,
        'notes': _notes.text.trim(),
        'addedBy': currentUserName(),
        'createdAt': DateTime.now().toIso8601String(),
      });
    } else {
      final name = _expenseName.text.trim();
      final amount = toDouble(_amount.text);
      if (name.isEmpty) {
        snack(context, 'Please enter the expense name');
        return;
      }
      if (amount <= 0) {
        snack(context, 'Please enter the expense amount');
        return;
      }
      setState(() => _saving = true);
      await Hive.box('expense_records').add({
        'category': 'Others',
        'name': name,
        'amount': amount,
        'date': _date.text,
        'time': _time.text,
        'notes': _notes.text.trim(),
        'addedBy': currentUserName(),
        'createdAt': DateTime.now().toIso8601String(),
      });
    }

    if (mounted) Navigator.of(context).pop();
  }

  Widget _milkForm() {
    final cows = cowNames();
    if (cows.isNotEmpty && !cows.contains(_cow)) _cow = cows.first;

    return Column(
      children: [
        if (cows.isEmpty)
          const EmptyNote(
            icon: Icons.info_outline_rounded,
            title: 'No cows yet',
            message: 'Add a cow before recording milk.',
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _cow,
            isExpanded: true,
            borderRadius: BorderRadius.circular(Gold.r21),
            decoration: fieldStyle(
              'Cow',
              prefix: const Padding(
                padding: EdgeInsets.only(left: Gold.s13, right: Gold.s8),
                child: CowHoofIcon(size: Gold.s34),
              ),
            ),
            items: [
              for (final c in cows)
                DropdownMenuItem<String>(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _cow = v ?? _cow),
          ),
        const SizedBox(height: Gold.s13),
        DateField(
          controller: _date,
          label: 'Date',
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _time,
          decoration: fieldStyle('Time', icon: Icons.schedule_rounded),
        ),
        const SizedBox(height: Gold.s13),
        Glass(
          radius: Gold.r21,
          blur: Gold.s13,
          padding: const EdgeInsets.all(Gold.s5),
          elevation: 0.62,
          child: LiquidSegmentBar(
            labels: const ['Morning', 'Afternoon', 'Evening'],
            index: const [
              'Morning',
              'Afternoon',
              'Evening',
            ].indexOf(_session).clamp(0, 2),
            onChanged: (value) => setState(
              () => _session = const ['Morning', 'Afternoon', 'Evening'][value],
            ),
          ),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _milk,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldStyle(
            'Milk Quantity (Liter)',
            icon: Icons.water_drop_outlined,
          ),
        ),
      ],
    );
  }

  Widget _stockUseForm() {
    return Column(
      children: [
        Glass(
          radius: Gold.r21,
          blur: Gold.s13,
          padding: const EdgeInsets.all(Gold.s5),
          elevation: 0.62,
          child: LiquidSegmentBar(
            labels: const ['Cows', 'Calves'],
            index: _feedTarget,
            onChanged: (value) => setState(() => _feedTarget = value),
          ),
        ),
        const SizedBox(height: Gold.s13),
        for (int i = 0; i < _stockItems.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Gold.s8),
            child: Pressable(
              radius: Gold.r21,
              onTap: () => setState(() => _stockItem = i),
              child: AnimatedContainer(
                duration: Gold.base,
                curve: Gold.ease,
                padding: const EdgeInsets.all(Gold.s13),
                decoration: ShapeDecoration(
                  shape: SquircleBorder(
                    radius: Gold.r21,
                    side: BorderSide(
                      color: _stockItem == i
                          ? Colors.transparent
                          : Colors.white.withValues(alpha: 0.80),
                    ),
                  ),
                  gradient: _stockItem == i
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Ink.violet, Ink.violetDeep],
                        )
                      : LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.72),
                            Colors.white.withValues(alpha: 0.48),
                          ],
                        ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: Gold.s34,
                      height: Gold.s34,
                      decoration: ShapeDecoration(
                        shape: const SquircleBorder(radius: Gold.r13),
                        color: _stockItem == i
                            ? Colors.white.withValues(alpha: 0.20)
                            : Ink.violet.withValues(alpha: 0.10),
                      ),
                      child: Center(
                        child: RanchIcon(
                          type: _stockIcons[i],
                          size: Gold.s21,
                          color: _stockItem == i ? Colors.white : Ink.violet,
                        ),
                      ),
                    ),
                    const SizedBox(width: Gold.s13),
                    Expanded(
                      child: Text(
                        _stockItems[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _stockItem == i ? Colors.white : Ink.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: Gold.t13,
                        ),
                      ),
                    ),
                    Text(
                      '${stockBalance(_stockItems[i]).toStringAsFixed(1)} kg left',
                      style: TextStyle(
                        color: _stockItem == i
                            ? Colors.white.withValues(alpha: 0.80)
                            : Ink.muted,
                        fontSize: Gold.t10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: Gold.s5),
        DateField(
          controller: _date,
          label: 'Date',
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _time,
          decoration: fieldStyle('Time', icon: Icons.schedule_rounded),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _qty,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldStyle(
            'Quantity used (kg)',
            icon: Icons.inventory_2_outlined,
          ),
        ),
      ],
    );
  }

  Widget _otherExpenseForm() {
    return Column(
      children: [
        SuggestionField(
          controller: _expenseName,
          suggestions: frequentNameSuggestions(expenseRows(), 'name'),
          label: 'Expense Name',
          icon: Icons.receipt_long_outlined,
        ),
        const SizedBox(height: Gold.s13),
        DateField(
          controller: _date,
          label: 'Date',
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _time,
          decoration: fieldStyle('Time', icon: Icons.schedule_rounded),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldStyle('Amount', icon: Icons.payments_outlined),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'Add Entry',
      children: [
        Glass(
          radius: Gold.r21,
          blur: Gold.s13,
          padding: const EdgeInsets.all(Gold.s5),
          elevation: 0.62,
          child: LiquidSegmentBar(
            labels: const ['Milk', 'Stock Use', 'Others'],
            icons: const [
              Icons.water_drop_rounded,
              Icons.inventory_2_rounded,
              Icons.receipt_long_rounded,
            ],
            index: _mode,
            onChanged: (value) => setState(() => _mode = value),
          ),
        ),
        const SizedBox(height: Gold.s21),
        AnimatedSize(
          duration: Gold.base,
          curve: Gold.ease,
          alignment: Alignment.topCenter,
          child: switch (_mode) {
            0 => _milkForm(),
            1 => _stockUseForm(),
            _ => _otherExpenseForm(),
          },
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _notes,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldStyle('Notes (optional)'),
        ),
        const SizedBox(height: Gold.s21),
        LiquidButton(
          label: switch (_mode) {
            0 => 'Save Milk Entry',
            1 => 'Use Stock',
            _ => 'Save Other Expense',
          },
          icon: Icons.check_rounded,
          busy: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

// =============================================================================
//  PART 12 — DOCTOR, CALVING, SALE, DEATH
// =============================================================================

class DoctorScreen extends StatefulWidget {
  final dynamic animalKey;
  const DoctorScreen({super.key, required this.animalKey});

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  int _visit = 0;
  String _semen = semenTypes.first;
  bool _saving = false;

  final _problem = TextEditingController();
  final _medicine = TextEditingController();
  final _cost = TextEditingController();
  final _date = TextEditingController(text: todayDate());
  final _time = TextEditingController(text: currentTime());
  final _notes = TextEditingController();

  @override
  void dispose() {
    _problem.dispose();
    _medicine.dispose();
    _cost.dispose();
    _date.dispose();
    _time.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!canRecordEntries) {
      snack(context, 'Your ranch role does not allow doctor entries');
      return;
    }
    final raw = Hive.box('animals').get(widget.animalKey);
    if (raw == null) {
      snack(context, 'Animal not found');
      return;
    }
    if (_visit == 0 && _problem.text.trim().isEmpty) {
      snack(context, 'Please describe the problem');
      return;
    }
    final animal = withKey(widget.animalKey, raw);
    if (_visit == 1 && txt(animal, 'gender', 'Female') != 'Female') {
      snack(context, 'Pregnancy can only be recorded for a female animal');
      return;
    }

    setState(() => _saving = true);
    try {
      await Hive.box('doctor_records').add({
        'cow': txt(animal, 'name'),
        'type': _visit == 0 ? 'Problem / Treatment' : 'Pregnancy Injection',
        'problem': _visit == 0 ? _problem.text.trim() : 'Pregnancy injection',
        'injection': _visit == 0 ? _medicine.text.trim() : _semen,
        'cost': toDouble(_cost.text),
        'date': _date.text,
        'time': _time.text,
        'notes': _notes.text.trim(),
        'addedBy': currentUserName(),
        'createdAt': DateTime.now().toIso8601String(),
      });

      if (_visit == 1) {
        await Hive.box('animals').put(widget.animalKey, {
          ...asMap(raw),
          'pregnancyStartDate': _date.text,
          'pregnancyInjection': _semen,
          'milkingStopDate': '',
        });
      }
      AutoSyncService.scheduleSync(reason: 'doctor visit saved');
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) snack(context, 'Could not save: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = Hive.box('animals').get(widget.animalKey);
    if (raw == null) {
      return const FormPage(
        title: 'Doctor Visit',
        children: [
          EmptyNote(
            icon: Icons.search_off_rounded,
            title: 'Animal not found',
            message: 'This record is no longer available.',
          ),
        ],
      );
    }
    final animal = asMap(raw);

    return FormPage(
      title: 'Add Doctor Visit',
      children: [
        Glass(
          radius: Gold.r21,
          padding: const EdgeInsets.all(Gold.s16),
          elevation: 0.62,
          child: Row(
            children: [
              const CowHoofIcon(size: Gold.t21, color: Ink.violet),
              const SizedBox(width: Gold.s13),
              Expanded(
                child: Text(
                  txt(animal, 'name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Ink.navy,
                    fontSize: Gold.t16,
                  ),
                ),
              ),
              Text(
                '#${txt(animal, 'id')}',
                style: const TextStyle(
                  color: Ink.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: Gold.t11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gold.s13),
        Glass(
          radius: Gold.r21,
          blur: Gold.s13,
          padding: const EdgeInsets.all(Gold.s5),
          elevation: 0.62,
          child: LiquidSegmentBar(
            labels: const ['Problem', 'Pregnancy Injection'],
            index: _visit,
            onChanged: (value) => setState(() => _visit = value),
          ),
        ),
        const SizedBox(height: Gold.s16),
        DateField(
          controller: _date,
          label: 'Date',
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _time,
          decoration: fieldStyle('Time', icon: Icons.schedule_rounded),
        ),
        const SizedBox(height: Gold.s13),
        if (_visit == 0) ...[
          TextField(
            controller: _problem,
            textCapitalization: TextCapitalization.sentences,
            decoration: fieldStyle('Problem', icon: Icons.healing_rounded),
          ),
          const SizedBox(height: Gold.s13),
          TextField(
            controller: _medicine,
            decoration: fieldStyle(
              'Injection / Medicine',
              icon: Icons.vaccines_rounded,
            ),
          ),
        ] else
          DropdownButtonFormField<String>(
            initialValue: _semen,
            isExpanded: true,
            borderRadius: BorderRadius.circular(Gold.r21),
            decoration: fieldStyle(
              'Breed Injection Name',
              icon: Icons.science_outlined,
            ),
            items: [
              for (final s in semenTypes)
                DropdownMenuItem<String>(value: s, child: Text(s)),
            ],
            onChanged: (v) => setState(() => _semen = v ?? _semen),
          ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _cost,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldStyle('Cost', icon: Icons.payments_outlined),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _notes,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldStyle('Notes (optional)'),
        ),
        const SizedBox(height: Gold.s21),
        LiquidButton(
          label: 'Save Doctor Visit',
          icon: Icons.check_rounded,
          busy: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
//  Calf born
// -----------------------------------------------------------------------------

class CalfBornScreen extends StatefulWidget {
  final dynamic motherKey;
  const CalfBornScreen({super.key, required this.motherKey});

  @override
  State<CalfBornScreen> createState() => _CalfBornScreenState();
}

class _CalfBornScreenState extends State<CalfBornScreen> {
  final _name = TextEditingController();
  final _dob = TextEditingController(text: todayDate());
  final _birthTime = TextEditingController(text: currentTime());
  final _notes = TextEditingController();
  String _breed = breeds.first;
  String _gender = 'Female';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final raw = Hive.box('animals').get(widget.motherKey);
    if (raw is Map) {
      final motherBreed = txt(asMap(raw), 'breed');
      if (breeds.contains(motherBreed)) _breed = motherBreed;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dob.dispose();
    _birthTime.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!canEditAnimals) {
      snack(context, 'Only admins and editors can register a calf birth');
      return;
    }
    final raw = Hive.box('animals').get(widget.motherKey);
    if (raw == null) {
      snack(context, 'Mother not found');
      return;
    }

    final mother = withKey(widget.motherKey, raw);
    if (txt(mother, 'pregnancyStartDate').isEmpty) {
      snack(context, 'No active pregnancy is recorded for this animal');
      return;
    }
    // Compute the id once; calling nextId twice would allocate two numbers and
    // leave a gap, or worse, disagree with the name that was defaulted from it.
    final calfId = nextId('calf');
    final calfName = _name.text.trim().isEmpty ? calfId : _name.text.trim();

    final taken = animals(
      all: true,
    ).any((a) => txt(a, 'name').toLowerCase() == calfName.toLowerCase());
    if (taken) {
      snack(context, 'An animal named "$calfName" already exists');
      return;
    }

    setState(() => _saving = true);
    final animalsBox = Hive.box('animals');
    final calvingBox = Hive.box('calving_records');
    dynamic calfKey;
    dynamic calvingKey;
    try {
      final wasCalf = txt(mother, 'type') == 'calf';
      final motherCowId = wasCalf ? nextId('cow') : txt(mother, 'id');
      final newborn = <String, dynamic>{
        'type': 'calf',
        'name': calfName,
        'id': calfId,
        'breed': _breed,
        'dob': _dob.text,
        'ageYears': 0,
        'ageMonths': 0,
        'ageDays': 0,
        'status': 'Active',
        'mother': txt(mother, 'name'),
        'motherId': motherCowId,
        'arrivalDate': _dob.text,
        'source': 'Born',
        'purchaseAmount': 0.0,
        'gender': _gender,
        'birthTime': _birthTime.text.trim(),
        'pregnancyStartDate': '',
        'pregnancyInjection': '',
        'milkingStopDate': '',
        'notes': _notes.text.trim(),
        'imageUrl': '',
        'imageData': '',
        'addedBy': currentUserName(),
        'createdAt': DateTime.now().toIso8601String(),
      };
      calfKey = await animalsBox.add(newborn);

      calvingKey = await calvingBox.add({
        'mother': txt(mother, 'name'),
        'motherId': motherCowId,
        'calfName': calfName,
        'calfId': calfId,
        'date': _dob.text,
        'time': _birthTime.text.trim(),
        'gender': _gender,
        'breed': _breed,
        'notes': _notes.text.trim(),
        'addedBy': currentUserName(),
        'createdAt': DateTime.now().toIso8601String(),
      });

      // First calving promotes a heifer from Calves to Cows and starts her
      // lactation. A cow remains a cow and simply begins the next lactation.
      await animalsBox.put(
        widget.motherKey,
        motherAfterCalving(
          asMap(raw),
          cowId: motherCowId,
          calfName: calfName,
          calfId: calfId,
          birthDate: _dob.text,
          birthTime: _birthTime.text.trim(),
        ),
      );

      AutoSyncService.scheduleSync(reason: 'calf birth saved');
      if (!mounted) return;
      snack(
        context,
        wasCalf
            ? '${txt(mother, 'name')} moved to Cows and milking started'
            : 'Newborn calf saved and milking restarted',
      );
      Navigator.of(context).pop();
      Navigator.of(context).maybePop();
    } catch (error) {
      // Keep mother/newborn/calving history consistent if any write fails.
      if (calvingKey != null) await calvingBox.delete(calvingKey);
      if (calfKey != null) await animalsBox.delete(calfKey);
      await animalsBox.put(widget.motherKey, asMap(raw));
      if (mounted) snack(context, 'Birth was not saved. Please try again');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = Hive.box('animals').get(widget.motherKey);
    final motherName = raw == null ? '' : txt(asMap(raw), 'name');

    return FormPage(
      title: 'Calf Born',
      children: [
        Glass(
          radius: Gold.r21,
          padding: const EdgeInsets.all(Gold.s16),
          elevation: 0.62,
          child: Row(
            children: [
              const Icon(
                Icons.family_restroom_rounded,
                color: Ink.violet,
                size: Gold.t21,
              ),
              const SizedBox(width: Gold.s13),
              Expanded(
                child: Text(
                  'Mother  $motherName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Ink.navy,
                    fontSize: Gold.t13,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: fieldStyle(
            'Calf Name (auto if blank)',
            icon: Icons.drive_file_rename_outline_rounded,
          ),
        ),
        const SizedBox(height: Gold.s13),
        DateField(
          controller: _dob,
          label: 'Birth Date',
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _birthTime,
          keyboardType: TextInputType.datetime,
          decoration: fieldStyle('Birth Time', icon: Icons.schedule_rounded),
        ),
        const SizedBox(height: Gold.s13),
        DropdownButtonFormField<String>(
          initialValue: _breed,
          isExpanded: true,
          borderRadius: BorderRadius.circular(Gold.r21),
          decoration: fieldStyle('Breed', icon: Icons.category_outlined),
          items: [
            for (final b in breeds)
              DropdownMenuItem<String>(value: b, child: Text(b)),
          ],
          onChanged: (v) => setState(() => _breed = v ?? _breed),
        ),
        const SizedBox(height: Gold.s13),
        DropdownButtonFormField<String>(
          initialValue: _gender,
          isExpanded: true,
          borderRadius: BorderRadius.circular(Gold.r21),
          decoration: fieldStyle('Gender', icon: Icons.wc_rounded),
          items: const [
            DropdownMenuItem<String>(value: 'Female', child: Text('Female')),
            DropdownMenuItem<String>(value: 'Male', child: Text('Male')),
          ],
          onChanged: (v) => setState(() => _gender = v ?? _gender),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _notes,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldStyle('Notes (optional)'),
        ),
        const SizedBox(height: Gold.s21),
        LiquidButton(
          label: 'Save Newborn Calf',
          icon: Icons.check_rounded,
          start: Ink.green,
          end: const Color(0xFF1B7A4A),
          busy: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
//  Sell an animal
// -----------------------------------------------------------------------------

class SellAnimalScreen extends StatefulWidget {
  final dynamic animalKey;
  const SellAnimalScreen({super.key, required this.animalKey});

  @override
  State<SellAnimalScreen> createState() => _SellAnimalScreenState();
}

class _SellAnimalScreenState extends State<SellAnimalScreen> {
  final _amount = TextEditingController();
  final _date = TextEditingController(text: todayDate());
  final _notes = TextEditingController();
  bool _withCalves = false;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _date.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!canEditAnimals) {
      snack(context, 'Only admins and editors can sell animals');
      return;
    }
    final raw = Hive.box('animals').get(widget.animalKey);
    if (raw == null) {
      snack(context, 'Animal not found');
      return;
    }

    final animal = withKey(widget.animalKey, raw);
    final price = toDouble(_amount.text);
    if (price <= 0) {
      snack(context, 'Please enter the sale amount');
      return;
    }

    setState(() => _saving = true);
    final isCow = txt(animal, 'type') == 'cow';

    await Hive.box('sale_records').add({
      'category': isCow ? 'Cow Sale' : 'Calf Sale',
      'animal': txt(animal, 'name'),
      // Capitalised to match the Sell screen, so milk-sale filtering and any
      // report grouping see one consistent vocabulary.
      'type': isCow ? 'Cow' : 'Calf',
      'quantity': 1.0,
      'unit': 'Animal',
      'pricePerUnit': price,
      'amount': price,
      'date': _date.text,
      'time': currentTime(),
      'notes': _notes.text.trim(),
      'withCalves': _withCalves,
      'addedBy': currentUserName(),
      'createdAt': DateTime.now().toIso8601String(),
    });

    updateAnimal(animal, {'status': 'Sold'});
    if (_withCalves) {
      for (final calf in calvesOf(txt(animal, 'name'))) {
        updateAnimal(calf, {'status': 'Sold'});
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final raw = Hive.box('animals').get(widget.animalKey);
    if (raw == null) {
      return const FormPage(
        title: 'Sell Animal',
        children: [
          EmptyNote(
            icon: Icons.search_off_rounded,
            title: 'Animal not found',
            message: 'This record is no longer available.',
          ),
        ],
      );
    }

    final animal = withKey(widget.animalKey, raw);
    final calfCount = calvesOf(txt(animal, 'name')).length;

    return FormPage(
      title: 'Sell Animal',
      children: [
        Glass(
          radius: Gold.r21,
          padding: const EdgeInsets.all(Gold.s16),
          elevation: 0.62,
          child: Row(
            children: [
              AnimalAvatar(animal: animal, radius: Gold.s21, decorate: false),
              const SizedBox(width: Gold.s13),
              Expanded(
                child: Text(
                  txt(animal, 'name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Ink.navy,
                    fontSize: Gold.t16,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gold.s13),
        DateField(
          controller: _date,
          label: 'Sale Date',
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldStyle(
            'Sale Price / Income',
            icon: Icons.payments_outlined,
          ),
        ),
        if (calfCount > 0) ...[
          const SizedBox(height: Gold.s13),
          Glass(
            radius: Gold.r21,
            padding: const EdgeInsets.symmetric(
              horizontal: Gold.s16,
              vertical: Gold.s5,
            ),
            elevation: 0.62,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _withCalves,
              activeThumbColor: Ink.violet,
              title: Text(
                calfCount == 1
                    ? 'Sell 1 calf together'
                    : 'Sell $calfCount calves together',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: Gold.t13,
                  color: Ink.navy,
                ),
              ),
              onChanged: (v) => setState(() => _withCalves = v),
            ),
          ),
        ],
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _notes,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldStyle('Notes (optional)'),
        ),
        const SizedBox(height: Gold.s21),
        LiquidButton(
          label: 'Save Sale',
          icon: Icons.check_rounded,
          start: Ink.green,
          end: const Color(0xFF1B7A4A),
          busy: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
//  Death record
// -----------------------------------------------------------------------------

class DeathScreen extends StatefulWidget {
  final dynamic animalKey;
  const DeathScreen({super.key, required this.animalKey});

  @override
  State<DeathScreen> createState() => _DeathScreenState();
}

class _DeathScreenState extends State<DeathScreen> {
  String _reason = deathReasons.first;
  final _cost = TextEditingController();
  final _date = TextEditingController(text: todayDate());
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _cost.dispose();
    _date.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!canEditAnimals) {
      snack(context, 'Only admins and editors can update animal status');
      return;
    }
    final raw = Hive.box('animals').get(widget.animalKey);
    if (raw == null) {
      snack(context, 'Animal not found');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const SquircleBorder(radius: Gold.r27),
        backgroundColor: Colors.white,
        title: const Text(
          'Record this death?',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: Gold.t16),
        ),
        content: const Text(
          'The animal will be marked as died and removed from active lists. '
          'Its records stay in your reports.',
          style: TextStyle(fontSize: Gold.t13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Confirm',
              style: TextStyle(color: Ink.red, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final animal = withKey(widget.animalKey, raw);

    await Hive.box('death_records').add({
      'animal': txt(animal, 'name'),
      'type': txt(animal, 'type'),
      'reason': _reason,
      'cost': toDouble(_cost.text),
      'date': _date.text,
      'time': currentTime(),
      'notes': _notes.text.trim(),
      'addedBy': currentUserName(),
      'createdAt': DateTime.now().toIso8601String(),
    });

    updateAnimal(animal, {'status': 'Died'});

    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final raw = Hive.box('animals').get(widget.animalKey);
    if (raw == null) {
      return const FormPage(
        title: 'Death Record',
        children: [
          EmptyNote(
            icon: Icons.search_off_rounded,
            title: 'Animal not found',
            message: 'This record is no longer available.',
          ),
        ],
      );
    }
    final animal = asMap(raw);

    return FormPage(
      title: 'Death Record',
      children: [
        Glass(
          radius: Gold.r21,
          padding: const EdgeInsets.all(Gold.s16),
          elevation: 0.62,
          child: Row(
            children: [
              const CowHoofIcon(size: Gold.t21, color: Ink.red),
              const SizedBox(width: Gold.s13),
              Expanded(
                child: Text(
                  txt(animal, 'name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Ink.navy,
                    fontSize: Gold.t16,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gold.s13),
        DateField(
          controller: _date,
          label: 'Date',
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: Gold.s13),
        DropdownButtonFormField<String>(
          initialValue: _reason,
          isExpanded: true,
          borderRadius: BorderRadius.circular(Gold.r21),
          decoration: fieldStyle('Reason', icon: Icons.help_outline_rounded),
          items: [
            for (final r in deathReasons)
              DropdownMenuItem<String>(value: r, child: Text(r)),
          ],
          onChanged: (v) => setState(() => _reason = v ?? _reason),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _cost,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldStyle(
            'Cost / Expense',
            icon: Icons.payments_outlined,
          ),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _notes,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldStyle('Notes (optional)'),
        ),
        const SizedBox(height: Gold.s21),
        LiquidButton(
          label: 'Save Death Record',
          icon: Icons.check_rounded,
          start: Ink.red,
          end: const Color(0xFFA82638),
          busy: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

// =============================================================================
//  PART 13 — SELL, RECORDS, REPORTS
// =============================================================================

class SellScreen extends StatefulWidget {
  const SellScreen({super.key});

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  static const List<String> _types = ['Milk', 'Cow', 'Calf', 'Manure'];
  static const List<String> _stockItems = ['Vaikol', 'Thavudu'];

  int _section = 0;
  int _type = 0;
  int _stockItem = 0;
  String _animal = '';
  bool _saving = false;

  final _date = TextEditingController(text: todayDate());
  final _customer = TextEditingController();
  final _qty = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();
  final _stockQty = TextEditingController();
  final _stockAmount = TextEditingController();
  final _stockNotes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _qty.addListener(_refresh);
    _price.addListener(_refresh);
    _price.text = defaultMilkPrice().toStringAsFixed(0);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _qty.removeListener(_refresh);
    _price.removeListener(_refresh);
    _date.dispose();
    _customer.dispose();
    _qty.dispose();
    _price.dispose();
    _notes.dispose();
    _stockQty.dispose();
    _stockAmount.dispose();
    _stockNotes.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _sellable {
    if (_type == 1) return animalsBy('cow');
    if (_type == 2) return animalsBy('calf');
    return const [];
  }

  String get _unit => _type == 0 ? 'Liter' : (_type == 3 ? 'Load' : 'Animal');

  bool get _isAnimalSale => _type == 1 || _type == 2;

  double get _amount => _isAnimalSale
      ? toDouble(_price.text)
      : toDouble(_qty.text) * toDouble(_price.text);

  Future<void> _save() async {
    if (_isAnimalSale && !canEditAnimals) {
      snack(context, 'Only admins and editors can sell cows or calves');
      return;
    }
    if (!_isAnimalSale && !canRecordEntries) {
      snack(context, 'Your ranch role does not allow recording sales');
      return;
    }
    final amount = _amount;
    if (amount <= 0) {
      snack(context, 'Please enter an amount');
      return;
    }

    String item = _types[_type];
    double quantity = toDouble(_qty.text);
    double perUnit = toDouble(_price.text);

    if (_type == 0) {
      if (_customer.text.trim().isEmpty) {
        snack(context, 'Please enter the customer name');
        return;
      }
      if (quantity <= 0) {
        snack(context, 'Please enter the milk quantity');
        return;
      }
      if (quantity > availableMilk('Today')) {
        snack(context, 'Cannot sell more than the milk available today');
        return;
      }
    }

    Map<String, dynamic>? animal;
    if (_isAnimalSale) {
      final list = _sellable;
      if (list.isEmpty) {
        snack(context, 'No animals available to sell');
        return;
      }
      final selected = _animal.isEmpty ? '${list.first['key']}' : _animal;
      final matches = list.where((a) => '${a['key']}' == selected).toList();
      if (matches.isEmpty) {
        snack(context, 'Please choose an animal');
        return;
      }
      animal = matches.first;
      item = txt(animal, 'name');
      quantity = 1;
      perUnit = amount;
    }

    setState(() => _saving = true);

    await Hive.box('sale_records').add({
      'category': '${_types[_type]} Sale',
      'animal': item,
      'customerName': _type == 0 ? _customer.text.trim() : '',
      'type': _types[_type],
      'quantity': quantity,
      'unit': _unit,
      'pricePerUnit': perUnit,
      'amount': amount,
      'date': _date.text,
      'time': currentTime(),
      'notes': _notes.text.trim(),
      'addedBy': currentUserName(),
      'createdAt': DateTime.now().toIso8601String(),
    });

    if (animal != null) updateAnimal(animal, {'status': 'Sold'});

    if (!mounted) return;
    snack(context, '${_types[_type]} sale saved');
    setState(() {
      _saving = false;
      _qty.clear();
      _customer.clear();
      _notes.clear();
      _animal = '';
      _price.text = _type == 0 ? defaultMilkPrice().toStringAsFixed(0) : '';
    });
  }

  Widget _milkBalance() {
    final collected = milkTotal('Today');
    final sold = milkSold('Today');
    final available = availableMilk('Today');
    final selling = toDouble(_qty.text);
    final after = (available - selling).clamp(0.0, double.infinity);
    final over = selling > available;

    return Glass(
      radius: Gold.r27,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's Milk Balance",
            style: TextStyle(
              fontSize: Gold.t16,
              fontWeight: FontWeight.w900,
              color: Ink.navy,
            ),
          ),
          const SizedBox(height: Gold.s13),
          _BalanceRow(
            label: 'Collected',
            value: '${collected.toStringAsFixed(1)} L',
            color: Ink.violet,
          ),
          _BalanceRow(
            label: 'Already sold',
            value: '${sold.toStringAsFixed(1)} L',
            color: Ink.amber,
          ),
          _BalanceRow(
            label: 'Available',
            value: '${available.toStringAsFixed(1)} L',
            color: Ink.green,
            emphasise: true,
          ),
          if (selling > 0) ...[
            Divider(
              height: Gold.s21,
              color: Ink.violet.withValues(alpha: 0.10),
            ),
            _BalanceRow(
              label: 'Selling now',
              value: '${selling.toStringAsFixed(1)} L',
              color: Ink.violetDeep,
            ),
            _BalanceRow(
              label: over ? 'Not enough milk' : 'Balance after sale',
              value: '${after.toStringAsFixed(1)} L',
              color: over ? Ink.red : Ink.blue,
              emphasise: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionSwitcher() => Glass(
    radius: Gold.r27,
    blur: Gold.s21,
    padding: const EdgeInsets.all(Gold.s5),
    elevation: 0.72,
    child: LiquidSegmentBar(
      labels: const ['Sell', 'Stock'],
      icons: const [Icons.sell_rounded, Icons.inventory_2_rounded],
      index: _section,
      onChanged: (value) => setState(() => _section = value),
    ),
  );

  Future<void> _saveStockPurchase() async {
    if (!canRecordEntries) {
      snack(context, 'Your ranch role does not allow adding stock');
      return;
    }
    final quantity = toDouble(_stockQty.text);
    final amount = toDouble(_stockAmount.text);
    if (quantity <= 0) {
      snack(context, 'Please enter the purchased quantity');
      return;
    }
    if (amount <= 0) {
      snack(context, 'Please enter the purchase amount');
      return;
    }
    setState(() => _saving = true);
    await Hive.box('stock_records').add({
      'movement': 'Purchase',
      'item': _stockItems[_stockItem],
      'quantityKg': quantity,
      'unit': 'kg',
      'amount': amount,
      'date': _date.text,
      'time': currentTime(),
      'notes': _stockNotes.text.trim(),
      'addedBy': currentUserName(),
      'createdAt': DateTime.now().toIso8601String(),
    });
    if (!mounted) return;
    snack(context, '${_stockItems[_stockItem]} stock added');
    setState(() {
      _saving = false;
      _stockQty.clear();
      _stockAmount.clear();
      _stockNotes.clear();
    });
  }

  Widget _stockScreen() => ValueListenableBuilder<Box<dynamic>>(
    valueListenable: Hive.box('stock_records').listenable(),
    builder: (_, _, _) {
      final recent = stockRows().take(8).toList();
      return Shell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Gold.s21,
            Gold.s21,
            Gold.s21,
            _MainShellState.bottomInset,
          ),
          children: [
            _sectionSwitcher(),
            const SizedBox(height: Gold.s21),
            const Text(
              'Stock',
              style: TextStyle(
                fontSize: Gold.t34,
                fontWeight: FontWeight.w900,
                color: Ink.navy,
                height: 1.05,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: Gold.s3),
            const Text(
              'Track Vaikol and Thavudu without double-counting expenses',
              style: TextStyle(
                color: Ink.muted,
                fontSize: Gold.t13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Gold.s21),
            Row(
              children: [
                for (int i = 0; i < _stockItems.length; i++) ...[
                  if (i > 0) const SizedBox(width: Gold.s13),
                  Expanded(
                    child: Glass(
                      radius: Gold.r27,
                      gradient: LinearGradient(
                        colors: [
                          (i == 0 ? Ink.amber : Ink.violet).withValues(
                            alpha: 0.19,
                          ),
                          Colors.white.withValues(alpha: 0.55),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            i == 0
                                ? Icons.grass_rounded
                                : Icons.inventory_2_rounded,
                            color: i == 0 ? Ink.amber : Ink.violet,
                          ),
                          const SizedBox(height: Gold.s13),
                          Text(
                            _stockItems[i],
                            style: const TextStyle(
                              color: Ink.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${stockBalance(_stockItems[i]).toStringAsFixed(1)} kg',
                            style: const TextStyle(
                              color: Ink.navy,
                              fontSize: Gold.t21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Gold.s21),
            const SectionTitle(title: 'Add Purchased Stock'),
            Glass(
              radius: Gold.r27,
              blur: Gold.s21,
              child: Column(
                children: [
                  LiquidSegmentBar(
                    labels: _stockItems,
                    index: _stockItem,
                    onChanged: (value) => setState(() => _stockItem = value),
                  ),
                  const SizedBox(height: Gold.s13),
                  DateField(
                    controller: _date,
                    label: 'Purchase Date',
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: Gold.s13),
                  TextField(
                    controller: _stockQty,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: fieldStyle(
                      'Purchased Quantity (kg)',
                      icon: Icons.scale_rounded,
                    ),
                  ),
                  const SizedBox(height: Gold.s13),
                  TextField(
                    controller: _stockAmount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: fieldStyle(
                      'Total Purchase Amount',
                      icon: Icons.payments_outlined,
                    ),
                  ),
                  const SizedBox(height: Gold.s13),
                  TextField(
                    controller: _stockNotes,
                    maxLines: 2,
                    decoration: fieldStyle('Notes (optional)'),
                  ),
                  const SizedBox(height: Gold.s21),
                  LiquidButton(
                    label: 'Add to Stock',
                    icon: Icons.add_box_rounded,
                    busy: _saving,
                    onPressed: _saveStockPurchase,
                  ),
                ],
              ),
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: Gold.s21),
              const SectionTitle(title: 'Recent Stock Movements'),
              for (final record in recent)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gold.s8),
                  child: Glass(
                    radius: Gold.r21,
                    padding: const EdgeInsets.all(Gold.s13),
                    child: Row(
                      children: [
                        Icon(
                          txt(record, 'movement') == 'Usage'
                              ? Icons.remove_circle_outline_rounded
                              : Icons.add_circle_outline_rounded,
                          color: txt(record, 'movement') == 'Usage'
                              ? Ink.red
                              : Ink.green,
                        ),
                        const SizedBox(width: Gold.s13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${txt(record, 'item')} · ${txt(record, 'movement')}',
                                style: const TextStyle(
                                  color: Ink.navy,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${txt(record, 'date')} · ${txt(record, 'target', txt(record, 'addedBy'))}',
                                style: const TextStyle(color: Ink.muted),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${txt(record, 'movement') == 'Usage' ? '-' : '+'}${numv(record, 'quantityKg').toStringAsFixed(1)} kg',
                          style: TextStyle(
                            color: txt(record, 'movement') == 'Usage'
                                ? Ink.red
                                : Ink.green,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (_section == 1) return _stockScreen();
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box('sale_records').listenable(),
      builder: (_, _, _) => ValueListenableBuilder<Box<dynamic>>(
        valueListenable: Hive.box('milk_records').listenable(),
        builder: (_, _, _) {
          final list = _sellable;
          if (_isAnimalSale &&
              list.isNotEmpty &&
              !list.any((a) => '${a['key']}' == _animal)) {
            _animal = '${list.first['key']}';
          }

          return Shell(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Gold.s21,
                Gold.s21,
                Gold.s21,
                _MainShellState.bottomInset,
              ),
              children: [
                _sectionSwitcher(),
                const SizedBox(height: Gold.s21),
                const Reveal(
                  index: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sell',
                        style: TextStyle(
                          fontSize: Gold.t34,
                          fontWeight: FontWeight.w900,
                          color: Ink.navy,
                          height: 1.05,
                          letterSpacing: -1,
                        ),
                      ),
                      SizedBox(height: Gold.s3),
                      Text(
                        'Milk, cow, calf and manure sales',
                        style: TextStyle(
                          color: Ink.muted,
                          fontSize: Gold.t13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gold.s21),
                Reveal(
                  index: 1,
                  child: Glass(
                    radius: Gold.r27,
                    blur: Gold.s13,
                    padding: const EdgeInsets.all(Gold.s5),
                    elevation: 0.62,
                    child: LiquidSegmentBar(
                      labels: _types,
                      index: _type,
                      onChanged: (value) {
                        if ((value == 1 || value == 2) && !canEditAnimals) {
                          snack(
                            context,
                            'Only admins and editors can sell cows or calves',
                          );
                          return;
                        }
                        setState(() {
                          _type = value;
                          _animal = '';
                          _customer.clear();
                          _qty.clear();
                          _price.text = value == 0
                              ? defaultMilkPrice().toStringAsFixed(0)
                              : '';
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: Gold.s21),
                Reveal(
                  index: 2,
                  child: DateField(
                    controller: _date,
                    label: 'Date',
                    onChanged: () => setState(() {}),
                  ),
                ),
                const SizedBox(height: Gold.s13),
                if (_type == 0) ...[
                  Reveal(index: 3, child: _milkBalance()),
                  const SizedBox(height: Gold.s13),
                ],
                if (_isAnimalSale) ...[
                  Reveal(
                    index: 4,
                    child: list.isEmpty
                        ? EmptyNote(
                            icon: Icons.inbox_rounded,
                            title: 'Nothing to sell',
                            message: _type == 1
                                ? 'There are no active cows on the ranch.'
                                : 'There are no active calves on the ranch.',
                          )
                        : DropdownButtonFormField<String>(
                            initialValue: _animal.isEmpty ? null : _animal,
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(Gold.r21),
                            decoration: fieldStyle(
                              _type == 1 ? 'Select Cow' : 'Select Calf',
                              prefix: const Padding(
                                padding: EdgeInsets.only(
                                  left: Gold.s13,
                                  right: Gold.s8,
                                ),
                                child: CowHoofIcon(size: Gold.s34),
                              ),
                            ),
                            items: [
                              for (final a in list)
                                DropdownMenuItem<String>(
                                  value: '${a['key']}',
                                  child: Text(
                                    '${txt(a, 'name')}  #${txt(a, 'id')}',
                                  ),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _animal = v ?? _animal),
                          ),
                  ),
                  const SizedBox(height: Gold.s13),
                  Reveal(
                    index: 5,
                    child: TextField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: fieldStyle(
                        'Sale Amount',
                        icon: Icons.payments_outlined,
                      ),
                    ),
                  ),
                ] else ...[
                  if (_type == 0) ...[
                    Reveal(
                      index: 4,
                      child: SuggestionField(
                        controller: _customer,
                        suggestions: frequentNameSuggestions(
                          saleRows(),
                          'customerName',
                          where: (record) => txt(record, 'type') == 'Milk',
                        ),
                        label: 'Customer Name',
                        icon: Icons.person_outline_rounded,
                        onSelected: (name) {
                          final previous = lastMilkQuantityForCustomer(name);
                          if (previous == null) return;
                          _qty.text = previous.toStringAsFixed(1);
                          snack(
                            context,
                            'Last quantity ${previous.toStringAsFixed(1)} L added',
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: Gold.s13),
                  ],
                  Reveal(
                    index: 5,
                    child: TextField(
                      controller: _qty,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: fieldStyle(
                        'Quantity ($_unit)',
                        icon: Icons.inventory_2_outlined,
                      ),
                    ),
                  ),
                  const SizedBox(height: Gold.s13),
                  Reveal(
                    index: 6,
                    child: TextField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: fieldStyle(
                        _type == 0 ? 'Price per Liter' : 'Price per Load',
                        icon: Icons.sell_outlined,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: Gold.s13),
                Reveal(
                  index: 6,
                  child: Glass(
                    radius: Gold.r27,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Ink.green.withValues(alpha: 0.20),
                        Ink.green.withValues(alpha: 0.08),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: Gold.s34,
                          height: Gold.s34,
                          decoration: ShapeDecoration(
                            shape: const SquircleBorder(radius: Gold.r13),
                            color: Ink.green.withValues(alpha: 0.18),
                          ),
                          child: const Icon(
                            Icons.calculate_rounded,
                            color: Ink.green,
                            size: Gold.t16,
                          ),
                        ),
                        const SizedBox(width: Gold.s13),
                        const Expanded(
                          child: Text(
                            'Calculated Amount',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Ink.navy,
                              fontSize: Gold.t13,
                            ),
                          ),
                        ),
                        FlowText(
                          money(_amount),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: Gold.t21,
                            color: Ink.navy,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Gold.s13),
                Reveal(
                  index: 7,
                  child: TextField(
                    controller: _notes,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: fieldStyle('Notes (optional)'),
                  ),
                ),
                const SizedBox(height: Gold.s21),
                Reveal(
                  index: 8,
                  child: LiquidButton(
                    label: 'Save ${_types[_type]} Sale',
                    icon: Icons.check_circle_rounded,
                    start: Ink.green,
                    end: const Color(0xFF1B7A4A),
                    busy: _saving,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool emphasise;

  const _BalanceRow({
    required this.label,
    required this.value,
    required this.color,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gold.s5),
      child: Row(
        children: [
          Container(
            width: Gold.s8,
            height: Gold.s8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Gold.s13),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600,
                fontSize: Gold.t13,
                color: emphasise ? Ink.navy : Ink.body,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: emphasise ? Gold.t16 : Gold.t13,
              color: emphasise ? color : Ink.navy,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Record list
// -----------------------------------------------------------------------------

class RecordListScreen extends StatelessWidget {
  final String title;
  final String recordType;

  const RecordListScreen({
    super.key,
    required this.title,
    required this.recordType,
  });

  @override
  Widget build(BuildContext context) {
    final isMilk = recordType == 'milk';

    final list = isMilk
        ? milkRows()
        : <Map<String, dynamic>>[
            ...foodRows().map((r) => {...r, 'cat': 'Food'}),
            ...stockRows()
                .where((r) => txt(r, 'movement') == 'Purchase')
                .map((r) => {...r, 'cat': 'Stock'}),
            ...expenseRows().map((r) => {...r, 'cat': 'Others'}),
            ...doctorRows().map((r) => {...r, 'cat': 'Doctor'}),
            ...purchaseRows().map((r) => {...r, 'cat': 'Purchase'}),
            ...deathRows().map((r) => {...r, 'cat': 'Death'}),
          ].where((r) => matchPeriod(txt(r, 'date'), 'This Month')).toList();

    if (!isMilk) {
      // Four separately-ordered sources were concatenated above, so without
      // this the list shows every food record, then every doctor record, and
      // so on, instead of the most recent activity first.
      list.sort((a, b) => activityDate(b).compareTo(activityDate(a)));
    }

    double amountOf(Map<String, dynamic> r) {
      switch (txt(r, 'cat')) {
        case 'Food':
          return numv(r, 'price');
        case 'Purchase':
        case 'Stock':
        case 'Others':
          return numv(r, 'amount');
        default:
          return numv(r, 'cost');
      }
    }

    return Scaffold(
      backgroundColor: Ink.canvasTop,
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(title), leading: const _BackButton()),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Gold.s21,
            Gold.s55,
            Gold.s21,
            Gold.s55,
          ),
          children: [
            Reveal(
              index: 0,
              child: Row(
                children: [
                  for (final p in const ['Today', 'This Week', 'This Month'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: Gold.s8),
                        child: _MiniStat(
                          label: p,
                          value: isMilk
                              ? '${milkTotal(p).toStringAsFixed(1)} L'
                              : money(totalExpense(p)),
                          color: isMilk ? Ink.violet : Ink.red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Gold.s21),
            if (list.isEmpty)
              const Reveal(
                index: 1,
                child: EmptyNote(
                  icon: Icons.receipt_long_rounded,
                  title: 'No records',
                  message: 'Entries you add will appear here.',
                ),
              ),
            for (int i = 0; i < list.length; i++)
              Reveal(
                index: 1 + i,
                child: isMilk
                    ? DataCard(
                        title: txt(list[i], 'cow'),
                        subtitle:
                            '${txt(list[i], 'date')} \u2022 ${txt(list[i], 'time')}',
                        icon: Icons.water_drop_rounded,
                        color: Ink.violet,
                        details: [
                          'Session: ${txt(list[i], 'session')}',
                          'Milk: ${numv(list[i], 'quantity').toStringAsFixed(1)} L',
                          'Notes: ${txt(list[i], 'notes', '-')}',
                        ],
                      )
                    : DataCard(
                        title: txt(list[i], 'cat'),
                        subtitle:
                            '${txt(list[i], 'date')} \u2022 ${txt(list[i], 'time', '--')}',
                        icon: Icons.payments_rounded,
                        color: Ink.red,
                        details: [
                          'Details: ${cleanFoodLabel(txt(list[i], 'foodLabel', txt(list[i], 'type', txt(list[i], 'reason', '-'))))}',
                          'Amount: ${money(amountOf(list[i]))}',
                          'Notes: ${txt(list[i], 'notes', '-')}',
                        ],
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Gold.r21,
      padding: const EdgeInsets.all(Gold.s13),
      elevation: 0.62,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: Gold.t10,
              color: Ink.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Gold.s3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: Gold.t16,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
//  PART 14 — REPORTS
// =============================================================================

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _period = 'This Month';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box('milk_records').listenable(),
      builder: (_, _, _) => ValueListenableBuilder<Box<dynamic>>(
        valueListenable: Hive.box('sale_records').listenable(),
        builder: (_, _, _) => ValueListenableBuilder<Box<dynamic>>(
          valueListenable: Hive.box('food_records').listenable(),
          builder: (_, _, _) => ValueListenableBuilder<Box<dynamic>>(
            valueListenable: Hive.box('stock_records').listenable(),
            builder: (_, _, _) => ValueListenableBuilder<Box<dynamic>>(
              valueListenable: Hive.box('expense_records').listenable(),
              builder: (_, _, _) => _content(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final income = saleIncome(_period);
    final expense = totalExpense(_period);
    final net = income - expense;

    return Shell(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Gold.s21,
          Gold.s21,
          Gold.s21,
          _MainShellState.bottomInset,
        ),
        children: [
          Reveal(
            index: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reports',
                        style: TextStyle(
                          fontSize: Gold.t34,
                          fontWeight: FontWeight.w900,
                          color: Ink.navy,
                          height: 1.05,
                          letterSpacing: -1,
                        ),
                      ),
                      SizedBox(height: Gold.s3),
                      Text(
                        'Track, analyze and grow your ranch',
                        style: TextStyle(
                          color: Ink.muted,
                          fontSize: Gold.t13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gold.s13),
                Glass(
                  radius: Gold.r21,
                  blur: Gold.s13,
                  padding: const EdgeInsets.all(Gold.s13),
                  elevation: 0.8,
                  onTap: () => push(context, const ExportReportScreen()),
                  child: const Icon(
                    Icons.file_download_outlined,
                    color: Ink.violetDeep,
                    size: Gold.t21,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gold.s21),
          Reveal(
            index: 1,
            child: Glass(
              radius: Gold.r27,
              blur: Gold.s13,
              padding: const EdgeInsets.all(Gold.s5),
              elevation: 0.62,
              child: LiquidSegmentBar(
                labels: const ['Today', 'Week', 'Month', 'Year'],
                index: periods.indexOf(_period).clamp(0, periods.length - 1),
                onChanged: (value) => setState(() => _period = periods[value]),
              ),
            ),
          ),
          const SizedBox(height: Gold.s21),
          Reveal(
            index: 2,
            child: LayoutBuilder(
              builder: (context, constraints) => GridView.count(
                crossAxisCount: constraints.maxWidth >= 800 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: Gold.s13,
                mainAxisSpacing: Gold.s13,
                childAspectRatio: Gold.sqrtPhi,
                children: [
                  _SummaryTile(
                    label: 'Milk Collected',
                    value: '${milkTotal(_period).toStringAsFixed(1)} L',
                    icon: Icons.water_drop_rounded,
                    color: Ink.violet,
                  ),
                  _SummaryTile(
                    label: 'Milk Sold',
                    value: '${milkSold(_period).toStringAsFixed(1)} L',
                    icon: Icons.local_shipping_rounded,
                    color: Ink.blue,
                  ),
                  _SummaryTile(
                    label: 'Income',
                    value: money(income),
                    icon: Icons.trending_up_rounded,
                    color: Ink.green,
                  ),
                  _SummaryTile(
                    label: 'Expense',
                    value: money(expense),
                    icon: Icons.trending_down_rounded,
                    color: Ink.red,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gold.s16),
          Reveal(
            index: 3,
            child: Glass(
              radius: Gold.r27,
              elevation: 1.1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Net Result',
                          style: TextStyle(
                            fontSize: Gold.t16,
                            fontWeight: FontWeight.w900,
                            color: Ink.navy,
                          ),
                        ),
                      ),
                      FlowText(
                        money(net),
                        style: TextStyle(
                          fontSize: Gold.t27,
                          fontWeight: FontWeight.w900,
                          color: net >= 0 ? Ink.green : Ink.red,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gold.s13),
                  ProfitBar(income: income, expense: expense),
                  const SizedBox(height: Gold.s8),
                  Text(
                    net >= 0
                        ? 'Profit for ${_period.toLowerCase()}'
                        : 'Loss for ${_period.toLowerCase()}',
                    style: const TextStyle(
                      color: Ink.muted,
                      fontSize: Gold.t11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gold.s34),
          Reveal(
            index: 4,
            child: const SectionTitle(title: 'Detailed Reports'),
          ),
          Reveal(
            index: 5,
            child: _ReportLink(
              title: 'Daily Totals',
              subtitle: 'Day by day milk, expense, feed and sales',
              icon: Icons.calendar_today_rounded,
              color: Ink.violet,
              onTap: () =>
                  push(context, const ReportDetailScreen(kind: 'daily')),
            ),
          ),
          Reveal(
            index: 6,
            child: _ReportLink(
              title: 'Monthly Totals',
              subtitle: 'Full month milk, expense and profit',
              icon: Icons.bar_chart_rounded,
              color: Ink.blue,
              onTap: () =>
                  push(context, const ReportDetailScreen(kind: 'monthly')),
            ),
          ),
          Reveal(
            index: 7,
            child: _ReportLink(
              title: 'Business Summary',
              subtitle: 'Overall performance across the whole ranch',
              icon: Icons.pie_chart_rounded,
              color: Ink.green,
              onTap: () =>
                  push(context, const ReportDetailScreen(kind: 'business')),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Gold.r27,
      padding: const EdgeInsets.all(Gold.s16),
      elevation: 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: Gold.s34,
            height: Gold.s34,
            decoration: ShapeDecoration(
              shape: SquircleBorder(
                radius: Gold.concentric(Gold.r27, Gold.s16),
              ),
              color: color.withValues(alpha: 0.13),
            ),
            child: Icon(icon, color: color, size: Gold.t16),
          ),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: Gold.t11,
              color: Ink.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Gold.s2),
          FlowText(
            value,
            style: const TextStyle(
              fontSize: Gold.t21,
              fontWeight: FontWeight.w900,
              color: Ink.navy,
              height: 1,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Income versus expense as a single proportional bar.
class ProfitBar extends StatelessWidget {
  final double income;
  final double expense;

  const ProfitBar({super.key, required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    final total = income + expense;
    // With no activity at all, show a neutral split rather than dividing by 0.
    final incomeShare = total <= 0 ? 0.5 : income / total;

    return Column(
      children: [
        ClipPath(
          clipper: const SquircleClipper(Gold.r8),
          child: SizedBox(
            height: Gold.s13,
            child: Row(
              children: [
                Expanded(
                  flex: math.max(1, (incomeShare * 1000).round()),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Ink.green, Color(0xFF1B7A4A)],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: math.max(1, ((1 - incomeShare) * 1000).round()),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Ink.red.withValues(alpha: 0.86),
                          const Color(0xFFA82638),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gold.s8),
        Row(
          children: [
            const _Dot(color: Ink.green),
            const SizedBox(width: Gold.s5),
            Text(
              'Income ${money(income)}',
              style: const TextStyle(
                fontSize: Gold.t10,
                fontWeight: FontWeight.w700,
                color: Ink.body,
              ),
            ),
            const Spacer(),
            const _Dot(color: Ink.red),
            const SizedBox(width: Gold.s5),
            Text(
              'Expense ${money(expense)}',
              style: const TextStyle(
                fontSize: Gold.t10,
                fontWeight: FontWeight.w700,
                color: Ink.body,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: Gold.s8,
    height: Gold.s8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _ReportLink extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ReportLink({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Gold.r27,
      margin: const EdgeInsets.only(bottom: Gold.s13),
      padding: const EdgeInsets.all(Gold.s16),
      elevation: 0.8,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: Gold.s34,
            height: Gold.s34,
            decoration: ShapeDecoration(
              shape: SquircleBorder(
                radius: Gold.concentric(Gold.r27, Gold.s16),
              ),
              color: color.withValues(alpha: 0.13),
            ),
            child: Icon(icon, color: color, size: Gold.t16),
          ),
          const SizedBox(width: Gold.s13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Ink.navy,
                    fontSize: Gold.t16,
                  ),
                ),
                const SizedBox(height: Gold.s2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Ink.muted,
                    fontSize: Gold.t10,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Ink.faint,
            size: Gold.t21,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Report detail
// -----------------------------------------------------------------------------

class ReportDetailScreen extends StatelessWidget {
  final String kind;
  const ReportDetailScreen({super.key, required this.kind});

  String get _title {
    if (kind == 'daily') return 'Daily Totals';
    if (kind == 'monthly') return 'Monthly Totals';
    return 'Business Summary';
  }

  /// Groups every dated record into buckets keyed by day or by month.
  List<MapEntry<String, Map<String, double>>> _buckets(bool byMonth) {
    final map = <String, Map<String, double>>{};

    Map<String, double> bucket(String date) {
      if (date.isEmpty) return {};
      final key = byMonth
          ? (date.length >= 7 ? date.substring(0, 7) : date)
          : date;
      return map.putIfAbsent(
        key,
        () => {'milk': 0, 'income': 0, 'expense': 0, 'feed': 0},
      );
    }

    for (final r in milkRows()) {
      bucket(txt(r, 'date'))['milk'] =
          (bucket(txt(r, 'date'))['milk'] ?? 0) + numv(r, 'quantity');
    }
    for (final r in saleRows()) {
      bucket(txt(r, 'date'))['income'] =
          (bucket(txt(r, 'date'))['income'] ?? 0) + numv(r, 'amount');
    }
    for (final r in foodRows()) {
      final b = bucket(txt(r, 'date'));
      b['feed'] = (b['feed'] ?? 0) + numv(r, 'price');
      b['expense'] = (b['expense'] ?? 0) + numv(r, 'price');
    }
    for (final r in stockRows().where(
      (record) => txt(record, 'movement') == 'Purchase',
    )) {
      final b = bucket(txt(r, 'date'));
      b['feed'] = (b['feed'] ?? 0) + numv(r, 'amount');
      b['expense'] = (b['expense'] ?? 0) + numv(r, 'amount');
    }
    for (final r in expenseRows()) {
      bucket(txt(r, 'date'))['expense'] =
          (bucket(txt(r, 'date'))['expense'] ?? 0) + numv(r, 'amount');
    }
    for (final r in doctorRows()) {
      bucket(txt(r, 'date'))['expense'] =
          (bucket(txt(r, 'date'))['expense'] ?? 0) + numv(r, 'cost');
    }
    for (final r in purchaseRows()) {
      bucket(txt(r, 'date'))['expense'] =
          (bucket(txt(r, 'date'))['expense'] ?? 0) + numv(r, 'amount');
    }
    for (final r in deathRows()) {
      bucket(txt(r, 'date'))['expense'] =
          (bucket(txt(r, 'date'))['expense'] ?? 0) + numv(r, 'cost');
    }

    final entries = map.entries.toList();
    // Newest first, so the most useful rows need no scrolling.
    entries.sort((a, b) => b.key.compareTo(a.key));
    return entries.take(60).toList();
  }

  Widget _business(BuildContext context) {
    final cows = animalsBy('cow').length;
    final calves = animalsBy('calf').length;
    final sold = animals(
      all: true,
    ).where((a) => txt(a, 'status') == 'Sold').length;
    final died = animals(
      all: true,
    ).where((a) => txt(a, 'status') == 'Died').length;

    final lifeIncome = saleIncome('All');
    final lifeExpense = totalExpense('All');

    return Column(
      children: [
        Glass(
          radius: Gold.r27,
          elevation: 1.1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                farmName(),
                style: const TextStyle(
                  fontSize: Gold.t21,
                  fontWeight: FontWeight.w900,
                  color: Ink.navy,
                ),
              ),
              Text(
                '${ownerName()} \u2022 ${placeName()}',
                style: const TextStyle(color: Ink.muted, fontSize: Gold.t11),
              ),
              const SizedBox(height: Gold.s16),
              ProfitBar(income: lifeIncome, expense: lifeExpense),
            ],
          ),
        ),
        const SizedBox(height: Gold.s16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: Gold.s13,
          mainAxisSpacing: Gold.s13,
          childAspectRatio: Gold.sqrtPhi,
          children: [
            _SummaryTile(
              label: 'Active Cows',
              value: '$cows',
              icon: Icons.pets_rounded,
              color: Ink.violet,
            ),
            _SummaryTile(
              label: 'Active Calves',
              value: '$calves',
              icon: Icons.child_care_rounded,
              color: Ink.amber,
            ),
            _SummaryTile(
              label: 'Sold',
              value: '$sold',
              icon: Icons.sell_rounded,
              color: Ink.green,
            ),
            _SummaryTile(
              label: 'Lost',
              value: '$died',
              icon: Icons.warning_amber_rounded,
              color: Ink.red,
            ),
          ],
        ),
        const SizedBox(height: Gold.s16),
        InfoRow(
          title: 'Lifetime Milk',
          value: '${milkTotal('All').toStringAsFixed(1)} L',
          icon: Icons.water_drop_rounded,
          color: Ink.violet,
        ),
        const SizedBox(height: Gold.s13),
        InfoRow(
          title: 'Lifetime Income',
          value: money(lifeIncome),
          icon: Icons.trending_up_rounded,
          color: Ink.green,
        ),
        const SizedBox(height: Gold.s13),
        InfoRow(
          title: 'Lifetime Expense',
          value: money(lifeExpense),
          icon: Icons.trending_down_rounded,
          color: Ink.red,
        ),
        const SizedBox(height: Gold.s13),
        InfoRow(
          title: 'Net Result',
          value: money(lifeIncome - lifeExpense),
          icon: Icons.account_balance_rounded,
          color: lifeIncome - lifeExpense >= 0 ? Ink.green : Ink.red,
        ),
        const SizedBox(height: Gold.s21),
        LiquidButton(
          label: 'Export Reports',
          icon: Icons.file_download_outlined,
          onPressed: () => push(context, const ExportReportScreen()),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kind == 'business') {
      return Scaffold(
        backgroundColor: Ink.canvasTop,
        extendBodyBehindAppBar: true,
        appBar: AppBar(title: Text(_title), leading: const _BackButton()),
        body: Shell(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Gold.s21,
              Gold.s55,
              Gold.s21,
              Gold.s55,
            ),
            children: [Reveal(index: 0, child: _business(context))],
          ),
        ),
      );
    }
    final byMonth = kind == 'monthly';
    final buckets = _buckets(byMonth);

    return Scaffold(
      backgroundColor: Ink.canvasTop,
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(_title), leading: const _BackButton()),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Gold.s21,
            Gold.s55,
            Gold.s21,
            Gold.s55,
          ),
          children: [
            if (buckets.isEmpty)
              const Reveal(
                index: 0,
                child: EmptyNote(
                  icon: Icons.insights_rounded,
                  title: 'Nothing to report yet',
                  message: 'Totals appear here once you record milk or money.',
                ),
              ),
            for (int i = 0; i < buckets.length; i++)
              Reveal(
                index: i,
                child: Builder(
                  builder: (_) {
                    final b = buckets[i].value;
                    final income = b['income'] ?? 0;
                    final expense = b['expense'] ?? 0;
                    final net = income - expense;

                    return Glass(
                      radius: Gold.r27,
                      margin: const EdgeInsets.only(bottom: Gold.s13),
                      padding: const EdgeInsets.all(Gold.s16),
                      elevation: 0.8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  buckets[i].key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: Ink.navy,
                                    fontSize: Gold.t16,
                                  ),
                                ),
                              ),
                              Text(
                                money(net),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: Gold.t16,
                                  color: net >= 0 ? Ink.green : Ink.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Gold.s13),
                          Row(
                            children: [
                              _Cell(
                                label: 'Milk',
                                value:
                                    '${(b['milk'] ?? 0).toStringAsFixed(1)} L',
                              ),
                              _Cell(label: 'Income', value: money(income)),
                              _Cell(label: 'Expense', value: money(expense)),
                              _Cell(
                                label: 'Stock',
                                value: money(b['feed'] ?? 0),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String label;
  final String value;

  const _Cell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: Gold.t10,
              color: Ink.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Gold.s2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: Gold.t11,
              fontWeight: FontWeight.w900,
              color: Ink.navy,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Export
// -----------------------------------------------------------------------------

class ExportReportScreen extends StatelessWidget {
  const ExportReportScreen({super.key});

  String _milkCsv() {
    final b = StringBuffer(
      'Date,Time,Session,Cow,Quantity (L),Notes,Added By\n',
    );
    for (final r in milkRows()) {
      b.writeln(
        [
          csv(txt(r, 'date')),
          csv(txt(r, 'time')),
          csv(txt(r, 'session')),
          csv(txt(r, 'cow')),
          csv(numv(r, 'quantity').toStringAsFixed(2)),
          csv(txt(r, 'notes')),
          csv(txt(r, 'addedBy')),
        ].join(','),
      );
    }
    return b.toString();
  }

  String _expenseCsv() {
    final b = StringBuffer('Date,Category,Details,Amount,Notes,Added By\n');

    void line(
      String date,
      String cat,
      String detail,
      double amount,
      String notes,
      String by,
    ) {
      b.writeln(
        [
          csv(date),
          csv(cat),
          csv(detail),
          csv(amount.toStringAsFixed(2)),
          csv(notes),
          csv(by),
        ].join(','),
      );
    }

    for (final r in foodRows()) {
      line(
        txt(r, 'date'),
        'Feed',
        cleanFoodLabel(txt(r, 'foodLabel')),
        numv(r, 'price'),
        txt(r, 'notes'),
        txt(r, 'addedBy'),
      );
    }
    for (final r in stockRows().where(
      (record) => txt(record, 'movement') == 'Purchase',
    )) {
      line(
        txt(r, 'date'),
        'Stock Purchase',
        '${txt(r, 'item')} - ${numv(r, 'quantityKg').toStringAsFixed(2)} kg',
        numv(r, 'amount'),
        txt(r, 'notes'),
        txt(r, 'addedBy'),
      );
    }
    for (final r in expenseRows()) {
      line(
        txt(r, 'date'),
        'Others',
        txt(r, 'name'),
        numv(r, 'amount'),
        txt(r, 'notes'),
        txt(r, 'addedBy'),
      );
    }
    for (final r in doctorRows()) {
      line(
        txt(r, 'date'),
        'Doctor',
        '${txt(r, 'cow')} - ${txt(r, 'problem')}',
        numv(r, 'cost'),
        txt(r, 'notes'),
        txt(r, 'addedBy'),
      );
    }
    for (final r in purchaseRows()) {
      line(
        txt(r, 'date'),
        'Purchase',
        txt(r, 'animal'),
        numv(r, 'amount'),
        txt(r, 'notes'),
        txt(r, 'addedBy'),
      );
    }
    for (final r in deathRows()) {
      line(
        txt(r, 'date'),
        'Loss',
        '${txt(r, 'animal')} - ${txt(r, 'reason')}',
        numv(r, 'cost'),
        txt(r, 'notes'),
        txt(r, 'addedBy'),
      );
    }
    return b.toString();
  }

  String _saleCsv() {
    final b = StringBuffer(
      'Date,Time,Category,Customer,Item,Quantity,Unit,Price Per Unit,Amount,Notes,Added By\n',
    );
    for (final r in saleRows()) {
      b.writeln(
        [
          csv(txt(r, 'date')),
          csv(txt(r, 'time')),
          csv(txt(r, 'category')),
          csv(txt(r, 'customerName')),
          csv(txt(r, 'animal')),
          csv(numv(r, 'quantity').toStringAsFixed(2)),
          csv(txt(r, 'unit')),
          csv(numv(r, 'pricePerUnit').toStringAsFixed(2)),
          csv(numv(r, 'amount').toStringAsFixed(2)),
          csv(txt(r, 'notes')),
          csv(txt(r, 'addedBy')),
        ].join(','),
      );
    }
    return b.toString();
  }

  String _animalCsv() {
    final b = StringBuffer(
      'ID,Name,Type,Breed,Gender,Date of Birth,Age,Status,Mother,Source,Arrival Date,Purchase Amount,Notes\n',
    );
    for (final a in animals(all: true)) {
      b.writeln(
        [
          csv(txt(a, 'id')),
          csv(txt(a, 'name')),
          csv(txt(a, 'type')),
          csv(txt(a, 'breed')),
          csv(txt(a, 'gender')),
          csv(txt(a, 'dob')),
          csv(ageText(a)),
          csv(displayStatus(a)),
          csv(txt(a, 'mother')),
          csv(txt(a, 'source')),
          csv(txt(a, 'arrivalDate')),
          csv(numv(a, 'purchaseAmount').toStringAsFixed(2)),
          csv(txt(a, 'notes')),
        ].join(','),
      );
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final stamp = safeFileName('${farmName()}_${todayDate()}');

    return FormPage(
      title: 'Export',
      children: [
        const EmptyNote(
          icon: Icons.table_view_rounded,
          title: 'Open everything in Excel',
          message:
              'Download one workbook with separate sheets for every ranch record, or use the individual CSV files below.',
        ),
        const SizedBox(height: Gold.s21),
        _ExportTile(
          title: 'All Data - Excel Workbook',
          subtitle:
              'Animals, milk, stock, sales, expenses, visits and settings in one file',
          icon: Icons.dataset_rounded,
          color: Ink.green,
          onTap: () async {
            if (await downloadExcelFile(
                  'vimo_all_data_$stamp.xls',
                  buildCompleteExcelWorkbook(),
                ) &&
                context.mounted) {
              snack(context, 'Complete Excel workbook downloaded');
            }
          },
        ),
        const SizedBox(height: Gold.s8),
        const SectionTitle(title: 'Individual files'),
        _ExportTile(
          title: 'Milk Records',
          subtitle: '${milkRows().length} entries',
          icon: Icons.water_drop_rounded,
          color: Ink.violet,
          onTap: () async {
            if (await downloadCsvFile('milk_$stamp.csv', _milkCsv()) &&
                context.mounted) {
              snack(context, 'Milk records downloaded');
            }
          },
        ),
        _ExportTile(
          title: 'Expenses',
          subtitle: 'Stock, others, doctor, purchase and loss',
          icon: Icons.payments_rounded,
          color: Ink.red,
          onTap: () async {
            if (await downloadCsvFile('expenses_$stamp.csv', _expenseCsv()) &&
                context.mounted) {
              snack(context, 'Expenses downloaded');
            }
          },
        ),
        _ExportTile(
          title: 'Sales',
          subtitle: '${saleRows().length} entries',
          icon: Icons.sell_rounded,
          color: Ink.green,
          onTap: () async {
            if (await downloadCsvFile('sales_$stamp.csv', _saleCsv()) &&
                context.mounted) {
              snack(context, 'Sales downloaded');
            }
          },
        ),
        _ExportTile(
          title: 'Animals',
          subtitle: '${animals(all: true).length} cows and calves',
          icon: Icons.pets_rounded,
          color: Ink.blue,
          onTap: () async {
            if (await downloadCsvFile('animals_$stamp.csv', _animalCsv()) &&
                context.mounted) {
              snack(context, 'Animal list downloaded');
            }
          },
        ),
        const SizedBox(height: Gold.s8),
        _ExportTile(
          title: 'Full Backup',
          subtitle: 'Everything, as a JSON file you can restore later',
          icon: Icons.backup_rounded,
          color: Ink.violetDeep,
          onTap: () async {
            if (await downloadJsonFile(
                  'vimo_backup_$stamp.json',
                  buildBackupJson(),
                ) &&
                context.mounted) {
              snack(context, 'Backup downloaded');
            }
          },
        ),
      ],
    );
  }
}

class _ExportTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ExportTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Gold.r27,
      margin: const EdgeInsets.only(bottom: Gold.s13),
      padding: const EdgeInsets.all(Gold.s16),
      elevation: 0.8,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: Gold.s34,
            height: Gold.s34,
            decoration: ShapeDecoration(
              shape: SquircleBorder(
                radius: Gold.concentric(Gold.r27, Gold.s16),
              ),
              color: color.withValues(alpha: 0.13),
            ),
            child: Icon(icon, color: color, size: Gold.t16),
          ),
          const SizedBox(width: Gold.s13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Ink.navy,
                    fontSize: Gold.t13,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Ink.muted,
                    fontSize: Gold.t10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.file_download_outlined,
            color: Ink.faint,
            size: Gold.t21,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
//  PART 15 — SETTINGS, FAMILY, SYNC
// =============================================================================

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box('settings').listenable(),
      builder: (_, _, _) => Scaffold(
        backgroundColor: Ink.canvasTop,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('Settings'),
          leading: const _BackButton(),
        ),
        body: Shell(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Gold.s21,
              Gold.s55,
              Gold.s21,
              Gold.s55,
            ),
            children: [
              Reveal(
                index: 0,
                child: Glass(
                  radius: Gold.r34,
                  elevation: 1.3,
                  padding: const EdgeInsets.all(Gold.s21),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const BrandMark(size: Gold.s89),
                      const SizedBox(width: Gold.s21),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              appName(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: Gold.t27,
                                fontWeight: FontWeight.w900,
                                color: Ink.navy,
                                letterSpacing: 1.8,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: Gold.s5),
                            Text(
                              farmName(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: Gold.t16,
                                fontWeight: FontWeight.w800,
                                color: Ink.body,
                              ),
                            ),
                            Text(
                              '${ownerName()} \u2022 ${placeName()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: Gold.t13,
                                color: Ink.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: Gold.s13),
                            const SyncChip(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gold.s21),
              Reveal(index: 1, child: const SectionTitle(title: 'Ranch')),
              Reveal(
                index: 2,
                child: _SettingLink(
                  title: 'App Settings',
                  subtitle: 'Farm name, owner, currency and milk price',
                  icon: Icons.tune_rounded,
                  color: Ink.violet,
                  onTap: () => push(context, const AppSettingsScreen()),
                ),
              ),
              Reveal(
                index: 3,
                child: _SettingLink(
                  title: 'Family Users',
                  subtitle: 'Admin, Editor, Basic Entry and Viewer access',
                  icon: Icons.groups_rounded,
                  color: Ink.blue,
                  onTap: () => push(context, const FamilyUsersScreen()),
                ),
              ),
              const SizedBox(height: Gold.s16),
              Reveal(index: 4, child: const SectionTitle(title: 'Data')),
              Reveal(
                index: 5,
                child: _SettingLink(
                  title: 'Cloud Sync',
                  subtitle: 'Sync status, manual upload and download',
                  icon: Icons.cloud_sync_rounded,
                  color: Ink.green,
                  onTap: () => push(context, const FirebaseSyncScreen()),
                ),
              ),
              Reveal(
                index: 6,
                child: _SettingLink(
                  title: 'Works Offline',
                  subtitle: 'How your data is kept safe without a network',
                  icon: Icons.wifi_off_rounded,
                  color: Ink.amber,
                  onTap: () => push(context, const WorksOfflineScreen()),
                ),
              ),
              Reveal(
                index: 7,
                child: _SettingLink(
                  title: 'Export and Backup',
                  subtitle: 'Excel workbook, CSV reports or a full backup',
                  icon: Icons.file_download_outlined,
                  color: Ink.violetDeep,
                  onTap: () => push(context, const ExportReportScreen()),
                ),
              ),
              Reveal(
                index: 8,
                child: _SettingLink(
                  title: 'Restore Backup',
                  subtitle: 'Load a previously downloaded backup file',
                  icon: Icons.restore_rounded,
                  color: Ink.red,
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: const SquircleBorder(radius: Gold.r27),
                        backgroundColor: Colors.white,
                        title: const Text(
                          'Restore from backup?',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: Gold.t16,
                          ),
                        ),
                        content: const Text(
                          'This replaces everything currently on this device '
                          'with the contents of the backup file.',
                          style: TextStyle(fontSize: Gold.t13, height: 1.45),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              'Choose file',
                              style: TextStyle(
                                color: Ink.violetDeep,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await restoreBackupData(context);
                    }
                  },
                ),
              ),
              if (firebaseReady &&
                  FirebaseAuth.instance.currentUser != null) ...[
                const SizedBox(height: Gold.s21),
                Reveal(
                  index: 9,
                  child: GhostButton(
                    label: 'Sign Out',
                    icon: Icons.logout_rounded,
                    color: Ink.red,
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) Navigator.of(context).maybePop();
                    },
                  ),
                ),
              ],
              const SizedBox(height: Gold.s21),
              const Center(
                child: Text(
                  'VIMO \u2022 Manage. Care. Grow.',
                  style: TextStyle(
                    color: Ink.faint,
                    fontSize: Gold.t10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingLink extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SettingLink({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Gold.r27,
      margin: const EdgeInsets.only(bottom: Gold.s13),
      padding: const EdgeInsets.all(Gold.s16),
      elevation: 0.8,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: Gold.s34,
            height: Gold.s34,
            decoration: ShapeDecoration(
              shape: SquircleBorder(
                radius: Gold.concentric(Gold.r27, Gold.s16),
              ),
              color: color.withValues(alpha: 0.13),
            ),
            child: Icon(icon, color: color, size: Gold.t16),
          ),
          const SizedBox(width: Gold.s13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Ink.navy,
                    fontSize: Gold.t13,
                  ),
                ),
                const SizedBox(height: Gold.s2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Ink.muted,
                    fontSize: Gold.t10,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Ink.faint,
            size: Gold.t21,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  App settings
// -----------------------------------------------------------------------------

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  late final TextEditingController _farm;
  late final TextEditingController _owner;
  late final TextEditingController _place;
  late final TextEditingController _currency;
  late final TextEditingController _price;
  late final TextEditingController _ranch;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _farm = TextEditingController(text: farmName());
    _owner = TextEditingController(text: ownerName());
    _place = TextEditingController(text: placeName());
    _currency = TextEditingController(text: currencySymbol());
    _price = TextEditingController(text: defaultMilkPrice().toStringAsFixed(0));
    _ranch = TextEditingController(text: ranchId());
  }

  @override
  void dispose() {
    _farm.dispose();
    _owner.dispose();
    _place.dispose();
    _currency.dispose();
    _price.dispose();
    _ranch.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!canManageRanch) {
      snack(context, 'Only the ranch admin can change ranch settings');
      return;
    }
    setState(() => _saving = true);

    await setSetting(
      'farmName',
      _farm.text.trim().isEmpty ? 'My Ranch' : _farm.text.trim(),
    );
    await setSetting('ownerName', _owner.text.trim());
    await setSetting('place', _place.text.trim());
    await setSetting(
      'currency',
      _currency.text.trim().isEmpty ? '\u20b9' : _currency.text.trim(),
    );
    final price = toDouble(_price.text);
    await setSetting('defaultMilkPrice', price <= 0 ? 60.0 : price);

    await CloudSyncService.uploadAll();

    if (!mounted) return;
    setState(() => _saving = false);
    snack(context, 'Settings saved');
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'App Settings',
      children: [
        TextField(
          controller: _farm,
          textCapitalization: TextCapitalization.words,
          decoration: fieldStyle('Farm Name', icon: Icons.home_work_outlined),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _owner,
          textCapitalization: TextCapitalization.words,
          decoration: fieldStyle(
            'Owner Name',
            icon: Icons.person_outline_rounded,
          ),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _place,
          textCapitalization: TextCapitalization.words,
          decoration: fieldStyle('Place', icon: Icons.place_outlined),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _currency,
          decoration: fieldStyle(
            'Currency Symbol',
            icon: Icons.currency_exchange_rounded,
          ),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldStyle(
            'Default Milk Price per Liter',
            icon: Icons.local_offer_outlined,
          ),
        ),
        const SizedBox(height: Gold.s13),
        TextField(
          controller: _ranch,
          readOnly: true,
          decoration: fieldStyle(
            'Ranch ID (permanent)',
            icon: Icons.key_outlined,
          ),
        ),
        const SizedBox(height: Gold.s8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Gold.s5),
          child: Text(
            'Members join with this ID and require admin approval. The Ranch ID '
            'cannot be changed after creation.',
            style: TextStyle(
              color: Ink.muted,
              fontSize: Gold.t10,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: Gold.s21),
        LiquidButton(
          label: 'Save Settings',
          icon: Icons.check_rounded,
          busy: _saving,
          onPressed: canManageRanch
              ? _save
              : () => snack(
                  context,
                  'Only the ranch admin can change these settings',
                ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
//  Family users
// -----------------------------------------------------------------------------

class FamilyUsersScreen extends StatelessWidget {
  const FamilyUsersScreen({super.key});

  static Color roleColor(String role) => switch (normalizeFamilyRole(role)) {
    'Admin' => Ink.goldDeep,
    'Editor' => Ink.violet,
    'Basic Entry' => Ink.green,
    _ => Ink.blue,
  };

  static IconData roleIcon(String role) => switch (normalizeFamilyRole(role)) {
    'Admin' => Icons.admin_panel_settings_rounded,
    'Editor' => Icons.edit_note_rounded,
    'Basic Entry' => Icons.playlist_add_check_circle_rounded,
    _ => Icons.visibility_rounded,
  };

  Future<void> _reviewRequest(
    BuildContext context,
    Map<String, dynamic> request,
  ) async {
    String role = 'Basic Entry';
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: const SquircleBorder(radius: Gold.r27),
          title: Text(
            '${txt(request, 'name', 'New member')} wants to join',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                txt(request, 'email'),
                style: const TextStyle(color: Ink.muted),
              ),
              const SizedBox(height: Gold.s13),
              DropdownButtonFormField<String>(
                initialValue: role,
                isExpanded: true,
                decoration: fieldStyle(
                  'Permission after approval',
                  icon: Icons.badge_outlined,
                ),
                items: [
                  for (final value in familyRoles.where((r) => r != 'Admin'))
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: (value) =>
                    setLocal(() => role = value ?? 'Basic Entry'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Reject',
                style: TextStyle(color: Ink.red, fontWeight: FontWeight.w900),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Accept',
                style: TextStyle(color: Ink.green, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
    if (approved == null) return;
    try {
      if (approved) {
        await RanchAccessService.approveRequest(ranchId(), request, role: role);
        if (context.mounted) {
          snack(context, '${txt(request, 'name')} joined as $role');
        }
      } else {
        await RanchAccessService.rejectRequest(ranchId(), request);
        if (context.mounted) snack(context, 'Join request rejected');
      }
    } catch (error) {
      if (context.mounted) {
        snack(context, '$error'.replaceFirst('Bad state: ', ''));
      }
    }
  }

  Future<void> _manageMember(
    BuildContext context,
    Map<String, dynamic> member,
  ) async {
    final memberUid = txt(member, 'uid');
    if (!canManageRanch || memberUid == RanchAccessService.uid) return;
    String role = normalizeFamilyRole(txt(member, 'role', 'Viewer'));
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: const SquircleBorder(radius: Gold.r27),
          title: Text(
            'Manage ${txt(member, 'name', 'member')}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: DropdownButtonFormField<String>(
            initialValue: role,
            isExpanded: true,
            decoration: fieldStyle(
              'Permission',
              icon: Icons.manage_accounts_rounded,
            ),
            items: [
              for (final value in familyRoles.where((r) => r != 'Admin'))
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) => setLocal(() => role = value ?? role),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: const Text(
                'Remove',
                style: TextStyle(color: Ink.red, fontWeight: FontWeight.w900),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text(
                'Save Role',
                style: TextStyle(
                  color: Ink.violetDeep,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (!context.mounted) return;
    try {
      if (action == 'save') {
        await RanchAccessService.updateMemberRole(ranchId(), memberUid, role);
        if (context.mounted) snack(context, 'Permission updated to $role');
      } else {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: const SquircleBorder(radius: Gold.r27),
            title: const Text(
              'Remove from ranch?',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            content: Text(
              '${txt(member, 'name', 'This member')} will immediately lose access to ranch data.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: Ink.red, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await RanchAccessService.removeMember(ranchId(), memberUid);
          if (context.mounted) snack(context, 'Member removed');
        }
      }
    } catch (error) {
      if (context.mounted) {
        snack(context, '$error'.replaceFirst('Bad state: ', ''));
      }
    }
  }

  Widget _memberCard(BuildContext context, Map<String, dynamic> member) {
    final role = normalizeFamilyRole(txt(member, 'role', 'Viewer'));
    final color = roleColor(role);
    final self = txt(member, 'uid') == RanchAccessService.uid;
    return Glass(
      radius: Gold.r27,
      margin: const EdgeInsets.only(bottom: Gold.s13),
      padding: const EdgeInsets.all(Gold.s16),
      elevation: 0.8,
      onTap: canManageRanch && !self
          ? () => _manageMember(context, member)
          : null,
      child: Row(
        children: [
          Container(
            width: Gold.s34,
            height: Gold.s34,
            decoration: ShapeDecoration(
              shape: const SquircleBorder(radius: Gold.r13),
              color: color.withValues(alpha: 0.13),
            ),
            child: Icon(roleIcon(role), color: color, size: Gold.t16),
          ),
          const SizedBox(width: Gold.s13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${txt(member, 'name', 'Ranch Member')}${self ? ' (You)' : ''}',
                  style: const TextStyle(
                    color: Ink.navy,
                    fontWeight: FontWeight.w900,
                    fontSize: Gold.t13,
                  ),
                ),
                Text(
                  txt(member, 'email'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Ink.muted, fontSize: Gold.t10),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Gold.s8,
              vertical: Gold.s5,
            ),
            decoration: ShapeDecoration(
              shape: const SquircleBorder(radius: Gold.r13),
              color: color.withValues(alpha: 0.14),
            ),
            child: Text(
              role,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: Gold.t10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = RanchAccessService.ranchRef(
      ranchId(),
    ).collection('members').snapshots();
    final requests = RanchAccessService.ranchRef(
      ranchId(),
    ).collection('join_requests').snapshots();

    return Scaffold(
      backgroundColor: Ink.canvasTop,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Ranch Members'),
        leading: const _BackButton(),
      ),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Gold.s21,
            Gold.s89,
            Gold.s21,
            Gold.s55,
          ),
          children: [
            Glass(
              radius: Gold.r27,
              padding: const EdgeInsets.all(Gold.s16),
              child: Row(
                children: [
                  const Icon(Icons.key_rounded, color: Ink.violet),
                  const SizedBox(width: Gold.s13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ranch ID',
                          style: TextStyle(
                            color: Ink.muted,
                            fontSize: Gold.t10,
                          ),
                        ),
                        Text(
                          ranchId(),
                          style: const TextStyle(
                            color: Ink.navy,
                            fontWeight: FontWeight.w900,
                            fontSize: Gold.t16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canManageRanch)
                    const Chip(
                      avatar: Icon(
                        Icons.admin_panel_settings_rounded,
                        size: Gold.t13,
                      ),
                      label: Text('Admin'),
                    ),
                ],
              ),
            ),
            if (canManageRanch) ...[
              const SizedBox(height: Gold.s21),
              const Text(
                'Join Requests',
                style: TextStyle(
                  color: Ink.navy,
                  fontSize: Gold.t21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: Gold.s13),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: requests,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return EmptyNote(
                      icon: Icons.sync_problem_rounded,
                      title: 'Could not load join requests',
                      message: '${snapshot.error}',
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: Ink.violet),
                    );
                  }
                  final rows =
                      snapshot.data?.docs
                          .map((doc) => {...doc.data(), 'uid': doc.id})
                          .where((row) => txt(row, 'status') == 'pending')
                          .toList() ??
                      <Map<String, dynamic>>[];
                  if (rows.isEmpty) {
                    return const EmptyNote(
                      icon: Icons.mark_email_read_rounded,
                      title: 'No pending requests',
                      message:
                          'New requests will appear here for admin approval.',
                    );
                  }
                  return Column(
                    children: [
                      for (final request in rows)
                        Glass(
                          radius: Gold.r27,
                          margin: const EdgeInsets.only(bottom: Gold.s13),
                          padding: const EdgeInsets.all(Gold.s16),
                          onTap: () => _reviewRequest(context, request),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.person_add_alt_1_rounded,
                                color: Ink.violet,
                              ),
                              const SizedBox(width: Gold.s13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      txt(request, 'name', 'New member'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Ink.navy,
                                      ),
                                    ),
                                    Text(
                                      txt(request, 'email'),
                                      style: const TextStyle(
                                        color: Ink.muted,
                                        fontSize: Gold.t10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Text(
                                'Review',
                                style: TextStyle(
                                  color: Ink.violetDeep,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: Gold.s21),
            const Text(
              'Members',
              style: TextStyle(
                color: Ink.navy,
                fontSize: Gold.t21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: Gold.s13),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: members,
              builder: (context, snapshot) {
                final rows =
                    snapshot.data?.docs
                        .map((doc) => {...doc.data(), 'uid': doc.id})
                        .where((row) => row['active'] != false)
                        .toList() ??
                    <Map<String, dynamic>>[];
                rows.sort((a, b) {
                  final ra = familyRoles.indexOf(
                    normalizeFamilyRole(txt(a, 'role', 'Viewer')),
                  );
                  final rb = familyRoles.indexOf(
                    normalizeFamilyRole(txt(b, 'role', 'Viewer')),
                  );
                  return ra != rb
                      ? ra.compareTo(rb)
                      : txt(a, 'name').compareTo(txt(b, 'name'));
                });
                if (snapshot.hasError) {
                  return EmptyNote(
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load members',
                    message: '${snapshot.error}',
                  );
                }
                return Column(
                  children: [
                    for (final member in rows) _memberCard(context, member),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class LegacyFamilyUsersScreen extends StatelessWidget {
  const LegacyFamilyUsersScreen({super.key});

  static const Map<String, String> roleNotes = {
    'Owner': 'Full access - manage everything',
    'Manager': 'Manage animals and records',
    'Viewer': 'View only - reports and details',
  };

  static IconData roleIcon(String role) {
    if (role == 'Owner') return Icons.workspace_premium_rounded;
    if (role == 'Manager') return Icons.groups_rounded;
    return Icons.visibility_rounded;
  }

  static Color roleColor(String role) {
    if (role == 'Owner') return Ink.goldDeep;
    if (role == 'Manager') return Ink.violet;
    return Ink.blue;
  }

  Future<void> _addUser(BuildContext context) async {
    final name = TextEditingController();
    String role = 'Viewer';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: const SquircleBorder(radius: Gold.r27),
          backgroundColor: Colors.white,
          title: const Text(
            'Add family user',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: Gold.t16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: fieldStyle(
                  'Name',
                  icon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(height: Gold.s13),
              DropdownButtonFormField<String>(
                initialValue: role,
                isExpanded: true,
                borderRadius: BorderRadius.circular(Gold.r21),
                decoration: fieldStyle('Role', icon: Icons.badge_outlined),
                items: [
                  for (final r in familyRoles)
                    DropdownMenuItem<String>(value: r, child: Text(r)),
                ],
                onChanged: (v) => setLocal(() => role = v ?? role),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Add',
                style: TextStyle(
                  color: Ink.violetDeep,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final clean = name.text.trim();
    if (clean.isEmpty) return;

    final users = Hive.box('family_users');
    final key = userKeyFor(clean, role);
    // A family member has one stable key even when their role changes.
    await users.put(key, {
      'userId': key,
      'name': clean,
      'role': role,
      'email': '',
      'phone': '',
      'active': true,
      'createdAt': DateTime.now().toIso8601String(),
      'addedBy': currentUserName(),
    });

    if (context.mounted) snack(context, '$clean added as $role');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box('family_users').listenable(),
      builder: (_, box, _) {
        final users = deduplicateFamilyUsers(box.values.whereType<Map>());
        users.sort((a, b) {
          final ra = familyRoles.indexOf(
            normalizeFamilyRole(txt(a, 'role', 'Viewer')),
          );
          final rb = familyRoles.indexOf(
            normalizeFamilyRole(txt(b, 'role', 'Viewer')),
          );
          if (ra != rb) return ra.compareTo(rb);
          return txt(a, 'name').compareTo(txt(b, 'name'));
        });

        return Scaffold(
          backgroundColor: Ink.canvasTop,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text('Family Users'),
            leading: const _BackButton(),
          ),
          body: Shell(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Gold.s21,
                Gold.s55,
                Gold.s21,
                Gold.s55,
              ),
              children: [
                const Reveal(
                  index: 0,
                  child: EmptyNote(
                    icon: Icons.groups_rounded,
                    title: 'Manage together as a family',
                    message:
                        'Everyone sharing your Ranch ID sees the same animals and records.',
                  ),
                ),
                const SizedBox(height: Gold.s21),
                for (int i = 0; i < users.length; i++)
                  Reveal(
                    index: 1 + i,
                    child: Builder(
                      builder: (_) {
                        final u = users[i];
                        final role = normalizeFamilyRole(
                          txt(u, 'role', 'Viewer'),
                        );
                        final color = roleColor(role);

                        return Glass(
                          radius: Gold.r27,
                          margin: const EdgeInsets.only(bottom: Gold.s13),
                          padding: const EdgeInsets.all(Gold.s16),
                          elevation: 0.8,
                          child: Row(
                            children: [
                              Container(
                                width: Gold.s34,
                                height: Gold.s34,
                                decoration: ShapeDecoration(
                                  shape: SquircleBorder(
                                    radius: Gold.concentric(Gold.r27, Gold.s16),
                                  ),
                                  color: color.withValues(alpha: 0.13),
                                ),
                                child: Icon(
                                  roleIcon(role),
                                  color: color,
                                  size: Gold.t16,
                                ),
                              ),
                              const SizedBox(width: Gold.s13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      txt(u, 'name'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Ink.navy,
                                        fontSize: Gold.t16,
                                      ),
                                    ),
                                    Text(
                                      roleNotes[role] ?? role,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Ink.muted,
                                        fontSize: Gold.t10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: Gold.s8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Gold.s8,
                                  vertical: Gold.s3,
                                ),
                                decoration: ShapeDecoration(
                                  shape: const SquircleBorder(radius: Gold.r8),
                                  color: color.withValues(alpha: 0.14),
                                ),
                                child: Text(
                                  role,
                                  style: TextStyle(
                                    fontSize: Gold.t10,
                                    fontWeight: FontWeight.w900,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: Gold.s8),
                LiquidButton(
                  label: 'Add Family User',
                  icon: Icons.person_add_alt_rounded,
                  onPressed: () => _addUser(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
//  Cloud sync
// -----------------------------------------------------------------------------

class FirebaseSyncScreen extends StatefulWidget {
  const FirebaseSyncScreen({super.key});

  @override
  State<FirebaseSyncScreen> createState() => _FirebaseSyncScreenState();
}

class _FirebaseSyncScreenState extends State<FirebaseSyncScreen> {
  bool _busy = false;
  Map<String, int>? _counts;

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) snack(context, done);
    } catch (e) {
      if (mounted) snack(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box('settings').listenable(),
      builder: (_, _, _) {
        final signedIn =
            firebaseReady && FirebaseAuth.instance.currentUser != null;

        return Scaffold(
          backgroundColor: Ink.canvasTop,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text('Cloud Sync'),
            leading: const _BackButton(),
          ),
          body: Shell(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Gold.s21,
                Gold.s55,
                Gold.s21,
                Gold.s55,
              ),
              children: [
                Reveal(
                  index: 0,
                  child: Glass(
                    radius: Gold.r34,
                    elevation: 1.3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              signedIn
                                  ? Icons.cloud_done_rounded
                                  : Icons.cloud_off_rounded,
                              color: signedIn ? Ink.green : Ink.amber,
                              size: Gold.t27,
                            ),
                            const SizedBox(width: Gold.s13),
                            Expanded(
                              child: Text(
                                signedIn ? 'Connected' : 'Working offline',
                                style: const TextStyle(
                                  fontSize: Gold.t21,
                                  fontWeight: FontWeight.w900,
                                  color: Ink.navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Gold.s13),
                        Text(
                          signedIn
                              ? 'Your records sync automatically every 4 hours, when the app opens, and whenever the network returns.'
                              : 'Everything you save is stored safely on this device and will upload once you sign in.',
                          style: const TextStyle(
                            color: Ink.muted,
                            fontSize: Gold.t11,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Gold.s16),
                Reveal(
                  index: 1,
                  child: InfoRow(
                    title: 'Last Synced',
                    value: lastSyncedText(),
                    icon: Icons.schedule_rounded,
                    color: Ink.violet,
                  ),
                ),
                const SizedBox(height: Gold.s13),
                Reveal(
                  index: 2,
                  child: InfoRow(
                    title: 'Status',
                    value: settingText('syncStatus', 'Waiting'),
                    icon: Icons.info_outline_rounded,
                    color: Ink.blue,
                  ),
                ),
                const SizedBox(height: Gold.s13),
                Reveal(
                  index: 3,
                  child: InfoRow(
                    title: 'Pending Records',
                    value: '${pendingSyncCount()}',
                    icon: Icons.pending_actions_rounded,
                    color: pendingSyncCount() > 0 ? Ink.amber : Ink.green,
                  ),
                ),
                const SizedBox(height: Gold.s13),
                Reveal(
                  index: 4,
                  child: InfoRow(
                    title: 'Ranch ID',
                    value: ranchId(),
                    icon: Icons.key_outlined,
                    color: Ink.violetDeep,
                  ),
                ),
                const SizedBox(height: Gold.s16),
                Reveal(
                  index: 5,
                  child: Glass(
                    radius: Gold.r27,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gold.s16,
                      vertical: Gold.s5,
                    ),
                    elevation: 0.8,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: autoSyncEnabled(),
                      activeThumbColor: Ink.violet,
                      title: const Text(
                        'Auto Sync',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: Gold.t13,
                          color: Ink.navy,
                        ),
                      ),
                      subtitle: const Text(
                        'Sync in the background without asking',
                        style: TextStyle(fontSize: Gold.t10, color: Ink.muted),
                      ),
                      onChanged: (v) async {
                        await setSetting('autoSyncEnabled', v);
                        if (v) {
                          AutoSyncService.scheduleSync(reason: 'switched on');
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: Gold.s21),
                if (!signedIn)
                  const Reveal(
                    index: 6,
                    child: EmptyNote(
                      icon: Icons.login_rounded,
                      title: 'Sign in to sync',
                      message:
                          'Cloud actions need an account. Your local data stays safe either way.',
                    ),
                  )
                else ...[
                  Reveal(
                    index: 6,
                    child: LiquidButton(
                      label: 'Sync Now',
                      icon: Icons.sync_rounded,
                      busy: _busy,
                      onPressed: () => _run(
                        () => AutoSyncService.run(reason: 'manual'),
                        'Sync complete',
                      ),
                    ),
                  ),
                  const SizedBox(height: Gold.s13),
                  Reveal(
                    index: 7,
                    child: GhostButton(
                      label: 'Upload This Device to Cloud',
                      icon: Icons.cloud_upload_rounded,
                      onPressed: _busy
                          ? null
                          : () => _run(
                              CloudSyncService.uploadAll,
                              'Upload complete',
                            ),
                    ),
                  ),
                  const SizedBox(height: Gold.s13),
                  Reveal(
                    index: 8,
                    child: GhostButton(
                      label: 'Download Cloud to This Device',
                      icon: Icons.cloud_download_rounded,
                      onPressed: _busy
                          ? null
                          : () => _run(
                              CloudSyncService.downloadAll,
                              'Download complete',
                            ),
                    ),
                  ),
                  const SizedBox(height: Gold.s13),
                  Reveal(
                    index: 9,
                    child: GhostButton(
                      label: 'Check Cloud Record Counts',
                      icon: Icons.fact_check_outlined,
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final counts =
                                  await CloudSyncService.cloudCounts();
                              if (mounted) setState(() => _counts = counts);
                            }, 'Counts updated'),
                    ),
                  ),
                  if (_counts != null) ...[
                    const SizedBox(height: Gold.s16),
                    panel('Cloud Records', 'Nothing in the cloud yet.', [
                      for (final entry in _counts!.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Gold.s3,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.key.replaceAll('_', ' '),
                                  style: const TextStyle(
                                    fontSize: Gold.t11,
                                    color: Ink.body,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '${entry.value}',
                                style: const TextStyle(
                                  fontSize: Gold.t11,
                                  fontWeight: FontWeight.w900,
                                  color: Ink.navy,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ]),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
//  Offline explainer
// -----------------------------------------------------------------------------

class WorksOfflineScreen extends StatelessWidget {
  const WorksOfflineScreen({super.key});

  static const List<List<String>> _points = [
    [
      'Everything works offline',
      'Add animals, milk, feed, doctor visits and sales with no network at all.',
    ],
    [
      'Nothing is lost',
      'Records are written to this device the moment you save them.',
    ],
    [
      'Automatic catch-up',
      'When the network returns, pending records upload on their own.',
    ],
    [
      'Every 4 hours',
      'A background sync runs regularly, and again each time you open the app.',
    ],
    [
      'Shared with your family',
      'Anyone using the same Ranch ID sees the same records after a sync.',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Works Offline'),
        leading: const _BackButton(),
      ),
      body: Shell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Gold.s21,
            Gold.s55,
            Gold.s21,
            Gold.s55,
          ),
          children: [
            const Reveal(
              index: 0,
              child: EmptyNote(
                icon: Icons.wifi_off_rounded,
                title: 'Use anytime, anywhere',
                message:
                    'The ranch does not wait for a signal, and neither does this app.',
              ),
            ),
            const SizedBox(height: Gold.s21),
            for (int i = 0; i < _points.length; i++)
              Reveal(
                index: 1 + i,
                child: Glass(
                  radius: Gold.r27,
                  margin: const EdgeInsets.only(bottom: Gold.s13),
                  padding: const EdgeInsets.all(Gold.s16),
                  elevation: 0.8,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: Gold.s27,
                        height: Gold.s27,
                        decoration: ShapeDecoration(
                          shape: const SquircleBorder(radius: Gold.r8),
                          color: Ink.green.withValues(alpha: 0.14),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Ink.green,
                          size: Gold.t13,
                        ),
                      ),
                      const SizedBox(width: Gold.s13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _points[i][0],
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Ink.navy,
                                fontSize: Gold.t13,
                              ),
                            ),
                            const SizedBox(height: Gold.s2),
                            Text(
                              _points[i][1],
                              style: const TextStyle(
                                color: Ink.muted,
                                fontSize: Gold.t10,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: Gold.s8),
            const SyncChip(),
          ],
        ),
      ),
    );
  }
}
