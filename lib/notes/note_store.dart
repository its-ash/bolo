import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'note.dart';
import 'note_search.dart';

/// Notes saved as one JSON file (`notes.json`) in the app's files folder.
/// Writes go to a temp file first, then replace the real one, so a crash never loses the list.
class NoteStore extends ChangeNotifier {
  NoteStore(this.dir);

  final Directory dir;
  final List<Note> _notes = [];
  Future<void> _writing = Future.value();

  File get _file => File('${dir.path}/notes.json');

  /// Every note, pinned first then newest first.
  List<Note> get notes => sortNotes(_notes);

  Note? byId(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  List<Note> search(String query) => searchNotes(_notes, query);

  Future<void> load() async {
    _notes.clear();
    try {
      if (await _file.exists()) {
        final data = jsonDecode(await _file.readAsString());
        if (data is List) {
          for (final e in data) {
            if (e is Map<String, dynamic>) _notes.add(Note.fromJson(e));
          }
        }
      }
    } catch (_) {
      // A damaged file: start with what we could not read ignored.
    }
    notifyListeners();
  }

  /// Adds a note, or replaces the one with the same id.
  Future<void> put(Note note) async {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i >= 0) {
      _notes[i] = note;
    } else {
      _notes.add(note);
    }
    notifyListeners();
    await _save();
  }

  Future<void> updateText(String id, String text) async {
    final n = byId(id);
    if (n == null || n.text == text) return;
    await put(n.copyWith(text: text, updatedAt: DateTime.now()));
  }

  Future<void> togglePin(String id) async {
    final n = byId(id);
    if (n != null) await put(n.copyWith(pinned: !n.pinned));
  }

  /// Removes the note and its audio file.
  Future<void> delete(String id) async {
    final n = byId(id);
    if (n == null) return;
    _notes.remove(n);
    notifyListeners();
    final audio = n.audioPath;
    if (audio != null) {
      try {
        final f = File(audio);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _save();
  }

  Future<void> _save() {
    final json = jsonEncode([for (final n in _notes) n.toJson()]);
    _writing = _writing.catchError((_) {}).then((_) async {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(_file.path);
    });
    return _writing;
  }
}
