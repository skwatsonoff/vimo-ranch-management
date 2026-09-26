part of 'main.dart';

class SocialPostRecord {
  final String id;
  final Map<String, dynamic> _data;
  const SocialPostRecord(this.id, this._data);
  Map<String, dynamic> data() => _data;
  DocumentReference<Map<String, dynamic>> get reference =>
      FirebaseFirestore.instance.collection('social_posts').doc(id);
}

dynamic decodeSocialField(dynamic value) {
  // One malformed field must not break the whole feed.
  if (value is! Map) return null;
  final field = value;
  if (field.containsKey('timestampValue')) {
    final time = DateTime.tryParse('${field['timestampValue']}');
    return time == null ? null : Timestamp.fromDate(time);
  }
  if (field.containsKey('integerValue')) {
    return int.tryParse('${field['integerValue']}');
  }
  if (field.containsKey('doubleValue')) {
    final value = field['doubleValue'];
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    return number != null && number.isFinite ? number : null;
  }
  if (field.containsKey('booleanValue')) {
    return field['booleanValue'] is bool ? field['booleanValue'] : null;
  }
  if (field.containsKey('stringValue')) {
    return field['stringValue'] is String ? field['stringValue'] : null;
  }
  if (field.containsKey('arrayValue')) {
    final array = field['arrayValue'];
    final values = array is Map ? array['values'] : null;
    return values is List
        ? [for (final value in values) decodeSocialField(value)]
        : <dynamic>[];
  }
  if (field.containsKey('mapValue')) {
    final map = field['mapValue'];
    final fields = map is Map ? map['fields'] : null;
    return fields is Map
        ? {
            for (final entry in fields.entries)
              '${entry.key}': decodeSocialField(entry.value),
          }
        : <String, dynamic>{};
  }
  return null;
}

SocialPostRecord? decodeSocialPost(dynamic row) {
  if (row is! Map || row['document'] is! Map) return null;
  final document = row['document'] as Map;
  final name = document['name'];
  if (name is! String || name.split('/').last.isEmpty) return null;
  final fields = document['fields'];
  return SocialPostRecord(name.split('/').last, {
    if (fields is Map)
      for (final entry in fields.entries)
        if (entry.key is String)
          entry.key as String: decodeSocialField(entry.value),
  });
}

/// Scheduled-post visibility is evaluated at each HTTP request's server time.
/// Reusing a Listen stream can retain an older request.time and reject a new
/// time-bound feed query. Ranch sync and chat keep their realtime listeners.
class SocialFeed {
  static Future<List<SocialPostRecord>> load({
    String? authorUid,
    bool own = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError(ui('Please sign in again'));
    final token = await user.getIdToken().timeout(
      CloudSyncService.networkTimeout,
    );
    final project = Firebase.app().options.projectId;
    final host = vimoUseEmulators
        ? 'http://127.0.0.1:8088'
        : 'https://firestore.googleapis.com';
    final documentsPath = 'projects/$project/databases/(default)/documents';
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    // Use a server-confirmed boundary. Even a slightly fast device clock makes
    // createdAt <= deviceNow broader than the rules' request.time permission.
    String? publishedThrough;
    if (!own) {
      final clockResponse = await http
          .post(
            Uri.parse('$host/v1/$documentsPath:batchGet'),
            headers: headers,
            body: jsonEncode({
              'documents': ['$documentsPath/users/${user.uid}'],
            }),
          )
          .timeout(CloudSyncService.networkTimeout);
      if (clockResponse.statusCode != 200) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      }
      final clockRows = jsonDecode(clockResponse.body) as List<dynamic>;
      publishedThrough = clockRows.isEmpty
          ? null
          : clockRows.first['readTime'] as String?;
      if (publishedThrough == null) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      }
    }
    final filters = <Map<String, dynamic>>[
      if (authorUid != null)
        {
          'fieldFilter': {
            'field': {'fieldPath': 'authorUid'},
            'op': 'EQUAL',
            'value': {'stringValue': authorUid},
          },
        },
      if (!own)
        {
          'fieldFilter': {
            'field': {'fieldPath': 'createdAt'},
            'op': 'LESS_THAN_OR_EQUAL',
            'value': {'timestampValue': publishedThrough},
          },
        },
    ];
    final response = await http
        .post(
          Uri.parse('$host/v1/$documentsPath:runQuery'),
          headers: headers,
          body: jsonEncode({
            'structuredQuery': {
              'from': [
                {'collectionId': 'social_posts'},
              ],
              'where': filters.length == 1
                  ? filters.single
                  : {
                      'compositeFilter': {'op': 'AND', 'filters': filters},
                    },
              'orderBy': [
                {
                  'field': {'fieldPath': 'createdAt'},
                  'direction': 'DESCENDING',
                },
              ],
              'limit': 60,
            },
          }),
        )
        .timeout(CloudSyncService.networkTimeout);
    if (response.statusCode != 200) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: switch (response.statusCode) {
          401 => 'unauthenticated',
          403 => 'permission-denied',
          _ => 'unavailable',
        },
      );
    }
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) return [];
    final rows = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final row in rows)
        if (decodeSocialPost(row) case final post?) post,
    ];
  }
}
