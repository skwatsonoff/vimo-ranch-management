import 'dart:async';

/// Compare the complete saved revision, including nested values, before
/// acknowledging it. A timestamp alone can match two edits in one millisecond.
bool sameSyncValue(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && sameSyncValue(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameSyncValue(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

class SyncFailure implements Exception {
  final Map<String, Object> failures;
  SyncFailure(this.failures);

  @override
  String toString() => failures.entries
      .take(3)
      .map((entry) => '${entry.key}: ${entry.value}')
      .join('; ');
}

/// An invalid photo, restricted health edit or chat message must not prevent
/// independent milk/feed/sales entries from reaching the other family phones.
Future<void> runSyncSteps(Map<String, Future<void> Function()> steps) async {
  final failures = <String, Object>{};
  for (final step in steps.entries) {
    try {
      await step.value();
    } catch (error) {
      failures[step.key] = error;
    }
  }
  if (failures.isNotEmpty) throw SyncFailure(failures);
}

/// Concurrent callers wait for the real result. A manual request arriving
/// during background sync asks for another pass before it reports completion.
class SyncCoordinator {
  Future<void>? _active;
  bool _again = false;

  bool get running => _active != null;

  Future<void> run(Future<void> Function() action, {bool rerun = false}) {
    final active = _active;
    if (active != null) {
      _again = _again || rerun;
      return active;
    }
    final done = Completer<void>();
    _active = done.future;
    unawaited(() async {
      Object? failure;
      StackTrace? trace;
      do {
        _again = false;
        failure = null;
        try {
          await action();
        } catch (error, stack) {
          failure = error;
          trace = stack;
        }
      } while (_again);
      _active = null;
      if (failure != null) {
        done.completeError(failure, trace);
      } else {
        done.complete();
      }
    }());
    return done.future;
  }
}
