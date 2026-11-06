import 'package:ranch_management/mic_permission.dart';

/// A scripted phone: each check or request answers the next state given.
class FakeMicBackend implements MicPermissionBackend {
  FakeMicBackend({
    required this.statuses,
    this.requests = const [],
    this.platform = 'android',
  });

  final List<MicAccess> statuses;
  final List<MicAccess> requests;
  @override
  final String platform;
  int statusCalls = 0;
  int requestCalls = 0;
  int settingsCalls = 0;

  @override
  Future<MicAccess> status({bool speech = false}) async =>
      statuses[(statusCalls++).clamp(0, statuses.length - 1)];

  @override
  Future<MicAccess> request({bool speech = false}) async =>
      requests[(requestCalls++).clamp(0, requests.length - 1)];

  @override
  Future<bool> openSettings() async {
    settingsCalls++;
    return true;
  }
}
