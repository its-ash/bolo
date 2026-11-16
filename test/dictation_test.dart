import 'dart:async';

import 'package:bolo/speech/dictation.dart';
import 'package:bolo/speech/speech_platform.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlatform implements SpeechPlatform {
  final controller = StreamController<SpeechEvent>.broadcast();
  SpeechStatus fakeStatus = const SpeechStatus(filesDir: '/tmp', sdk: 34, mic: true, onDevice: true);
  bool keepAudio = false;
  StopResult stopResult = const StopResult();

  @override
  Stream<SpeechEvent> get events => controller.stream;
  @override
  Future<SpeechStatus> status() async => fakeStatus;
  @override
  Future<bool> requestMic() async => true;
  @override
  Future<bool> start({required String id, required String lang, required bool keepAudio}) async => keepAudio;
  @override
  Future<StopResult> stop() async => stopResult;
  @override
  Future<void> openLanguageSettings(String lang) async {}
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<bool> play(String path) async => true;
  @override
  Future<void> pausePlay() async {}
  @override
  Future<void> stopPlay() async {}
  @override
  Future<void> seek(int ms) async {}
  @override
  Future<void> shareText(String text) async {}
  @override
  Future<void> shareAudio(String path) async {}
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  test('merges partials and finals across recognizer restarts into one note', () async {
    final p = FakePlatform();
    final d = DictationController(p);
    expect(await d.start(lang: 'en-IN', keepAudio: false), StartOutcome.started);

    p.controller.add(const SpeechEvent('partial', text: 'hello'));
    p.controller.add(const SpeechEvent('final', text: 'hello there'));
    p.controller.add(const SpeechEvent('partial', text: 'second'));
    await pump();
    expect(d.text, 'hello there second');

    p.controller.add(const SpeechEvent('final', text: 'second sentence'));
    await pump();
    final note = await d.stop();
    expect(note!.text, 'hello there second sentence');
    expect(note.lang, 'en-IN');
    expect(note.audioPath, isNull);
    expect(d.phase, DictationPhase.idle);
  });

  test('keeps the audio path and duration from stop', () async {
    final p = FakePlatform()..stopResult = const StopResult(audioPath: '/f/1.wav', durationMs: 5000);
    final d = DictationController(p);
    await d.start(lang: '', keepAudio: true);
    final note = await d.stop();
    expect(note!.text, '');
    expect(note.audioPath, '/f/1.wav');
    expect(note.durationMs, 5000);
  });

  test('nothing heard and no audio gives no note', () async {
    final d = DictationController(FakePlatform());
    await d.start(lang: 'hi-IN', keepAudio: false);
    expect(await d.stop(), isNull);
  });

  test('a pending partial is kept when stopping', () async {
    final p = FakePlatform();
    final d = DictationController(p);
    await d.start(lang: 'en-IN', keepAudio: false);
    p.controller.add(const SpeechEvent('partial', text: 'unfinished words'));
    await pump();
    expect((await d.stop())!.text, 'unfinished words');
  });

  test('a missing offline pack is reported and the text so far is kept', () async {
    final p = FakePlatform();
    final d = DictationController(p);
    await d.start(lang: 'hi-IN', keepAudio: false);
    p.controller.add(const SpeechEvent('final', text: 'kuch'));
    p.controller.add(const SpeechEvent('error', code: 'language', offlineMissing: true));
    await pump();
    expect(d.offlineMissing, isTrue);
    expect(d.halted, isTrue);
    expect((await d.stop())!.text, 'kuch');
  });

  test('no recognizer stops before starting', () async {
    final p = FakePlatform()..fakeStatus = const SpeechStatus(filesDir: '/tmp', available: false);
    final d = DictationController(p);
    expect(await d.start(lang: 'en-IN', keepAudio: false), StartOutcome.noRecognizer);
    expect(d.errorCode, 'no_recognizer');
    expect(d.phase, DictationPhase.idle);
  });

  test('audio notice switches the audio flag off', () async {
    final p = FakePlatform();
    final d = DictationController(p);
    await d.start(lang: 'en-IN', keepAudio: true);
    expect(d.keepingAudio, isTrue);
    p.controller.add(const SpeechEvent('notice', code: 'audio_unsupported'));
    await pump();
    expect(d.keepingAudio, isFalse);
    expect(d.notice, 'audio_unsupported');
  });
}
