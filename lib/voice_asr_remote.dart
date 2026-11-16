/// Speech-to-text through VIMO's own private runner (services/vimo-asr).
///
/// The runner loads VIMO's speech model from the owner's private Google
/// Drive, writes each sentence down in memory and keeps nothing. The phone
/// sends one short sentence of audio, with the signed-in person's Firebase
/// ID token; the runner checks the token and ranch membership itself.
///
/// The runner address is fixed at build time (`--dart-define=VIMO_ASR_URL`)
/// so no address or secret is typed into or stored in the app. Until the
/// owner approves a zero-billing host, it is empty and voice shows
/// "speech recognition is not set up" with Manual Entry.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'voice_capture.dart';

/// The approved runner, or empty.
const vimoAsrUrl = String.fromEnvironment('VIMO_ASR_URL');

/// Only an https address on an exact host, with no query or credentials.
Uri? vimoAsrEndpoint([String raw = vimoAsrUrl]) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return uri.replace(path: '${path}v1/transcribe');
}

class RemoteSpeechToText implements SpeechToTextService {
  RemoteSpeechToText({
    required this.endpoint,
    required this.idToken,
    required this.ranchId,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final Uri? endpoint;

  /// The signed-in person's Firebase ID token (null when signed out).
  final Future<String?> Function() idToken;

  /// The current ranch; the runner checks membership on its side.
  final String Function() ranchId;
  final http.Client _client;
  final Duration timeout;

  @override
  String get name => 'vimo-runner';

  @override
  bool get configured => endpoint != null;

  @override
  Future<String?> transcribe(
    Uint8List wav, {
    required String locale,
    List<String> hints = const [],
  }) async {
    final url = endpoint;
    if (url == null) {
      throw const SpeechServiceFailure(CaptureError.recognitionUnavailable);
    }
    // At most 15 s of 16 kHz mono 16-bit audio.
    if (wav.length < 44 || wav.length > 44 + 16000 * 2 * 15) return null;
    final token = await idToken();
    final ranch = ranchId();
    if (token == null || token.isEmpty || ranch.isEmpty) {
      throw const SpeechServiceFailure(CaptureError.recognitionUnavailable);
    }
    final http.Response reply;
    try {
      reply = await _client
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'audio/wav',
              'Cache-Control': 'no-store',
              'X-Vimo-Ranch': ranch,
              'X-Vimo-Locale': locale,
              // Cow names help the model; they go only to VIMO's runner.
              if (hints.isNotEmpty)
                'X-Vimo-Hints': base64Encode(
                  utf8.encode(hints.take(60).join('\n')),
                ),
            },
            body: wav,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const SpeechServiceFailure(CaptureError.offline);
    } catch (_) {
      throw const SpeechServiceFailure(CaptureError.offline);
    }
    if (reply.statusCode == 429) {
      throw const SpeechServiceFailure(CaptureError.quota);
    }
    if (reply.statusCode != 200) {
      throw const SpeechServiceFailure(CaptureError.recognitionUnavailable);
    }
    try {
      final body = jsonDecode(utf8.decode(reply.bodyBytes));
      if (body is! Map || body['schema'] != 'vimo.asr.v1') return null;
      final text = body['text'];
      if (text is! String || text.length > 400) return null;
      return text.trim();
    } catch (_) {
      return null;
    }
  }
}
