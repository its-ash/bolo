import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Dictation language and whether to keep the audio. Saved in `settings.json`.
class BoloSettings extends ChangeNotifier {
  BoloSettings(this.dir);

  final Directory dir;

  /// BCP-47 tag, '' = device default.
  String _lang = 'en-IN';
  bool _keepAudio = true;

  String get lang => _lang;
  bool get keepAudio => _keepAudio;

  File get _file => File('${dir.path}/settings.json');

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        final j = jsonDecode(await _file.readAsString());
        if (j is Map) {
          _lang = (j['lang'] as String?) ?? _lang;
          _keepAudio = (j['keepAudio'] as bool?) ?? _keepAudio;
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setLang(String v) async {
    _lang = v;
    notifyListeners();
    await _save();
  }

  Future<void> setKeepAudio(bool v) async {
    _keepAudio = v;
    notifyListeners();
    await _save();
  }

  Future<void> _save() => _file.writeAsString(jsonEncode({'lang': _lang, 'keepAudio': _keepAudio}), flush: true);
}
