// Dependency-free checks for the coordinator shared by automatic/manual sync.
import 'dart:async';
import '../lib/sync_support.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

Future<void> main() async {
  final coordinator = SyncCoordinator();
  final gate = Completer<void>();
  var passes = 0;
  final first = coordinator.run(() async {
    passes++;
    if (passes == 1) await gate.future;
  });
  final next = coordinator.run(() async {}, rerun: true);
  var completed = false;
  next.then((_) => completed = true);
  await Future<void>.delayed(Duration.zero);
  check(
    !completed,
    'A caller must wait for server work, not report early success',
  );
  gate.complete();
  await Future.wait([first, next]);
  check(passes == 2, 'An edit during upload must trigger another pass');
  check(!coordinator.running, 'Coordinator must be released');

  var goodStep = false;
  try {
    await runSyncSteps({
      'blocked photo': () async => throw StateError('permission-denied'),
      'milk': () async => goodStep = true,
    });
    throw StateError('Failure must be reported');
  } on SyncFailure catch (error) {
    check(
      goodStep && error.failures.containsKey('blocked photo'),
      'A bad photo must not block independent milk records',
    );
  }
  check(
    !sameSyncValue(
      {'updatedAtMillis': 12, 'quantity': 2},
      {'updatedAtMillis': 12, 'quantity': 3},
    ),
    'Same-millisecond edits must not be acknowledged as the same revision',
  );
  try {
    await coordinator.run(() async => throw StateError('offline'));
  } on StateError {
    check(!coordinator.running, 'Failed work must not leave sync locked');
  }
  var retried = false;
  await coordinator.run(() async => retried = true);
  check(retried, 'Failed work must permit a later reconnect retry');
  print(
    '6 sync core checks passed. Firebase/device integration is not covered.',
  );
}
