/// Builds one transcript out of recognizer results.
///
/// The recognizer stops after every pause, and each new session starts from nothing, so the text
/// is the finished segments joined with a space, plus the unfinished "partial" of the session
/// that is running now. A final replaces the partial. A final that repeats the previous final
/// without any partial in between is dropped (some recognizers send the result twice).
class TranscriptBuilder {
  TranscriptBuilder([String initial = '']) : _committed = initial.trim();

  String _committed;
  String _partial = '';
  String _lastFinal = '';
  bool _partialSinceFinal = true;

  /// Finished text only.
  String get committed => _committed;

  /// The unfinished words being heard now.
  String get partial => _partial;

  /// Everything: finished text and the partial.
  String get text => _join(_committed, _partial);

  bool get isEmpty => text.isEmpty;

  void onPartial(String s) {
    _partial = s.trim();
    if (_partial.isNotEmpty) _partialSinceFinal = true;
  }

  void onFinal(String s) {
    final t = s.trim();
    _partial = '';
    if (t.isEmpty) return;
    if (t == _lastFinal && !_partialSinceFinal) return;
    _committed = _join(_committed, t);
    _lastFinal = t;
    _partialSinceFinal = false;
  }

  /// Keeps the partial as finished text. Call when dictation ends without a last final.
  void flush() {
    if (_partial.isEmpty) return;
    onFinal(_partial);
  }

  static String _join(String a, String b) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return '$a $b';
  }
}
