import 'dart:async';

import 'package:flutter/services.dart';

/// What the phone can do for dictation right now.
class SpeechStatus {
  const SpeechStatus({
    required this.filesDir,
    this.sdk = 0,
    this.mic = false,
    this.onDevice = false,
    this.available = true,
  });

  /// App files folder (notes, settings, audio live here).
  final String filesDir;
  final int sdk;
  final bool mic;

  /// An on-device recognizer exists (Android 12+).
  final bool onDevice;

  /// Some recognizer exists at all.
  final bool available;

  /// Keeping audio next to the text needs Android 13 (API 33).
  bool get canKeepAudio => sdk >= 33;
}

/// One message from the Kotlin side (`SpeechEngine` and `Player`).
class SpeechEvent {
  const SpeechEvent(
    this.type, {
    this.text = '',
    this.code = '',
    this.offlineMissing = false,
    this.listening = false,
    this.level = 0,
    this.playing = false,
    this.path,
    this.posMs = 0,
    this.durMs = 0,
  });

  /// partial | final | state | error | notice | level | play
  final String type;
  final String text;
  final String code;
  final bool offlineMissing;
  final bool listening;
  final double level;
  final bool playing;
  final String? path;
  final int posMs;
  final int durMs;

  factory SpeechEvent.fromMap(Map<Object?, Object?> m) => SpeechEvent(
    (m['type'] as String?) ?? '',
    text: (m['text'] as String?) ?? '',
    code: (m['code'] as String?) ?? '',
    offlineMissing: (m['offlineMissing'] as bool?) ?? false,
    listening: (m['listening'] as bool?) ?? false,
    level: ((m['value'] as num?) ?? 0).toDouble(),
    playing: (m['playing'] as bool?) ?? false,
    path: m['path'] as String?,
    posMs: ((m['posMs'] as num?) ?? 0).toInt(),
    durMs: ((m['durMs'] as num?) ?? 0).toInt(),
  );
}

class StopResult {
  const StopResult({this.audioPath, this.durationMs = 0});
  final String? audioPath;
  final int durationMs;
}

/// Everything Dart needs from Android. A fake implements it in tests.
abstract class SpeechPlatform {
  Stream<SpeechEvent> get events;
  Future<SpeechStatus> status();
  Future<bool> requestMic();

  /// Starts dictation. Returns whether audio is being kept for this note.
  Future<bool> start({required String id, required String lang, required bool keepAudio});
  Future<StopResult> stop();
  Future<void> openLanguageSettings(String lang);
  Future<void> openAppSettings();

  Future<bool> play(String path);
  Future<void> pausePlay();
  Future<void> stopPlay();
  Future<void> seek(int ms);

  Future<void> shareText(String text);
  Future<void> shareAudio(String path);
}

/// The real thing: MethodChannel + EventChannel implemented in `MainActivity.kt`.
class ChannelSpeechPlatform implements SpeechPlatform {
  static const _control = MethodChannel('com.itsash.bolo/control');
  static const _stream = EventChannel('com.itsash.bolo/events');

  Stream<SpeechEvent>? _events;

  @override
  Stream<SpeechEvent> get events => _events ??= _stream
      .receiveBroadcastStream()
      .map((e) => SpeechEvent.fromMap((e as Map).cast<Object?, Object?>()))
      .asBroadcastStream();

  @override
  Future<SpeechStatus> status() async {
    final m = (await _control.invokeMapMethod<String, Object?>('status')) ?? {};
    return SpeechStatus(
      filesDir: (m['files'] as String?) ?? '',
      sdk: (m['sdk'] as num?)?.toInt() ?? 0,
      mic: (m['mic'] as bool?) ?? false,
      onDevice: (m['onDevice'] as bool?) ?? false,
      available: (m['available'] as bool?) ?? true,
    );
  }

  @override
  Future<bool> requestMic() async => (await _control.invokeMethod<bool>('requestMic')) ?? false;

  @override
  Future<bool> start({required String id, required String lang, required bool keepAudio}) async {
    final m = await _control.invokeMapMethod<String, Object?>('start', {
      'id': id,
      'lang': lang,
      'keepAudio': keepAudio,
    });
    return (m?['audio'] as bool?) ?? false;
  }

  @override
  Future<StopResult> stop() async {
    final m = await _control.invokeMapMethod<String, Object?>('stop');
    return StopResult(audioPath: m?['audioPath'] as String?, durationMs: (m?['durationMs'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<void> openLanguageSettings(String lang) => _control.invokeMethod('openLanguageSettings', {'lang': lang});

  @override
  Future<void> openAppSettings() => _control.invokeMethod('openAppSettings');

  @override
  Future<bool> play(String path) async => (await _control.invokeMethod<bool>('play', {'path': path})) ?? false;

  @override
  Future<void> pausePlay() => _control.invokeMethod('pausePlay');

  @override
  Future<void> stopPlay() => _control.invokeMethod('stopPlay');

  @override
  Future<void> seek(int ms) => _control.invokeMethod('seek', {'ms': ms});

  @override
  Future<void> shareText(String text) => _control.invokeMethod('shareText', {'text': text});

  @override
  Future<void> shareAudio(String path) => _control.invokeMethod('shareAudio', {'path': path});
}
