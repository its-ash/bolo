import 'dart:async';

import 'package:flutter/foundation.dart';

import '../notes/note.dart';
import 'speech_platform.dart';
import 'transcript.dart';

enum DictationPhase { idle, starting, active, stopping }

enum StartOutcome { started, micDenied, noRecognizer, failed }

/// One dictation at a time: starts the recognizer, merges what it hears into a transcript, and
/// turns the result into a [Note] when you stop.
class DictationController extends ChangeNotifier {
  DictationController(this.platform);

  final SpeechPlatform platform;

  DictationPhase _phase = DictationPhase.idle;
  TranscriptBuilder _transcript = TranscriptBuilder();
  StreamSubscription<SpeechEvent>? _sub;
  String _id = '';
  String _lang = '';
  DateTime _startedAt = DateTime.now();

  bool _keepingAudio = false;
  bool _halted = false;
  double _level = 0;
  String? _errorCode;
  bool _offlineMissing = false;
  String? _notice;
  bool _disposed = false;

  DictationPhase get phase => _phase;
  bool get isActive => _phase == DictationPhase.active || _phase == DictationPhase.starting;

  /// What has been said so far (finished text plus the words being heard).
  String get text => _transcript.text;

  /// Finished text only.
  String get committedText => _transcript.committed;

  /// The words still being recognized.
  String get partialText => _transcript.partial;

  /// Audio is being saved next to the text for this note.
  bool get keepingAudio => _keepingAudio;

  /// The recognizer stopped by itself after an error; [stop] still saves what we have.
  bool get halted => _halted;

  /// Microphone loudness, 0..1.
  double get level => _level;

  String? get errorCode => _errorCode;

  /// The error means a speech pack for the language is missing (or needs internet).
  bool get offlineMissing => _offlineMissing;

  /// A non-fatal message, e.g. the audio copy was dropped.
  String? get notice => _notice;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<StartOutcome> start({required String lang, required bool keepAudio}) async {
    if (_disposed || _phase != DictationPhase.idle) return StartOutcome.failed;
    _phase = DictationPhase.starting;
    _transcript = TranscriptBuilder();
    _halted = false;
    _level = 0;
    _errorCode = null;
    _offlineMissing = false;
    _notice = null;
    _keepingAudio = false;
    _lang = lang;
    _notify();

    final status = await platform.status();
    if (_disposed) return StartOutcome.failed;
    if (!status.available) {
      _fail('no_recognizer');
      return StartOutcome.noRecognizer;
    }
    if (!status.mic) {
      final granted = await platform.requestMic();
      if (_disposed) return StartOutcome.failed;
      if (!granted) {
        _phase = DictationPhase.idle;
        _errorCode = 'mic_denied';
        _notify();
        return StartOutcome.micDenied;
      }
    }

    _startedAt = DateTime.now();
    _id = _startedAt.millisecondsSinceEpoch.toString();
    _sub = platform.events.listen(_onEvent);
    try {
      _keepingAudio = await platform.start(id: _id, lang: lang, keepAudio: keepAudio);
    } catch (_) {
      await _sub?.cancel();
      _sub = null;
      if (_disposed) return StartOutcome.failed;
      _fail('start_failed');
      return StartOutcome.failed;
    }
    if (_disposed) {
      await _sub?.cancel();
      _sub = null;
      try {
        await platform.stop();
      } catch (_) {}
      return StartOutcome.failed;
    }
    _phase = DictationPhase.active;
    _notify();
    return StartOutcome.started;
  }

  void _fail(String code) {
    _phase = DictationPhase.idle;
    _errorCode = code;
    _notify();
  }

  void _onEvent(SpeechEvent e) {
    if (_disposed) return;
    switch (e.type) {
      case 'partial':
        _transcript.onPartial(e.text);
      case 'final':
        _transcript.onFinal(e.text);
      case 'level':
        _level = e.level.clamp(0.0, 1.0);
      case 'error':
        _errorCode = e.code;
        _offlineMissing = e.offlineMissing;
        _halted = true;
      case 'notice':
        _notice = e.code;
        if (e.code == 'audio_unsupported') _keepingAudio = false;
      default:
        return;
    }
    _notify();
  }

  /// Stops listening and returns the note to save, or null when nothing was captured.
  Future<Note?> stop() async {
    if (_phase != DictationPhase.active) return null;
    _phase = DictationPhase.stopping;
    _notify();
    StopResult result;
    try {
      result = await platform.stop();
    } catch (_) {
      result = const StopResult();
    }
    // The last text arrives on the event stream just before the stop result.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await _sub?.cancel();
    _sub = null;
    _transcript.flush();
    final text = _transcript.text;
    _phase = DictationPhase.idle;
    _level = 0;
    _notify();
    final audio = result.audioPath;
    if (text.isEmpty && audio == null) return null;
    return Note(
      id: _id,
      text: text,
      createdAt: _startedAt,
      updatedAt: DateTime.now(),
      lang: _lang,
      audioPath: audio,
      durationMs: result.durationMs,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
