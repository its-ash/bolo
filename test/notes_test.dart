import 'dart:convert';
import 'dart:io';

import 'package:bolo/notes/note.dart';
import 'package:bolo/notes/note_search.dart';
import 'package:bolo/notes/note_store.dart';
import 'package:flutter_test/flutter_test.dart';

Note note(String id, String text, {int minute = 0, bool pinned = false, String? audio}) => Note(
  id: id,
  text: text,
  createdAt: DateTime(2026, 1, 1, 10, minute),
  updatedAt: DateTime(2026, 1, 1, 10, minute),
  pinned: pinned,
  audioPath: audio,
);

void main() {
  group('search', () {
    final notes = [
      note('a', 'Buy milk and eggs from the market', minute: 1),
      note('b', 'Meeting notes: budget and milk supplier', minute: 2),
      note('c', 'पानी और दूध लाना है', minute: 3),
      note('d', 'Call mom', minute: 4, pinned: true),
    ];

    test('empty query lists pinned first, then newest', () {
      expect(searchNotes(notes, '').map((n) => n.id), ['d', 'c', 'b', 'a']);
    });

    test('is case-insensitive and matches partial words', () {
      expect(searchNotes(notes, 'MIL').map((n) => n.id).toSet(), {'a', 'b'});
    });

    test('every word must match', () {
      expect(searchNotes(notes, 'milk budget').map((n) => n.id), ['b']);
      expect(searchNotes(notes, 'milk zebra'), isEmpty);
    });

    test('finds Hindi text', () {
      expect(searchNotes(notes, 'दूध').map((n) => n.id), ['c']);
    });

    test('more hits rank first', () {
      final list = [note('x', 'milk', minute: 5), note('y', 'milk milk milk', minute: 1)];
      expect(searchNotes(list, 'milk').map((n) => n.id), ['y', 'x']);
    });

    test('snippet centres on the match', () {
      final text = '${'word ' * 40}needle ${'tail ' * 40}';
      final s = snippet(text, 'needle', length: 60);
      expect(s, contains('needle'));
      expect(s.length, lessThanOrEqualTo(62));
    });
  });

  group('Note', () {
    test('json round trip', () {
      final n = note('1', 'hello', pinned: true, audio: '/x/1.wav').copyWith(durationMs: 4200);
      final back = Note.fromJson(jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>);
      expect(back.id, '1');
      expect(back.text, 'hello');
      expect(back.pinned, isTrue);
      expect(back.audioPath, '/x/1.wav');
      expect(back.durationMs, 4200);
      expect(back.createdAt, n.createdAt);
    });

    test('title is the first line', () {
      expect(note('1', '\n First line \nsecond').title, 'First line');
      expect(note('2', '').title, 'Empty note');
      expect(note('3', '', audio: '/a.wav').title, 'Audio memo');
    });
  });

  group('NoteStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('bolo_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('saves and reloads notes', () async {
      final store = NoteStore(dir);
      await store.put(note('1', 'alpha', minute: 1));
      await store.put(note('2', 'beta', minute: 2));
      await store.togglePin('1');
      await store.updateText('2', 'beta edited');

      final again = NoteStore(dir);
      await again.load();
      expect(again.notes.map((n) => n.id), ['1', '2']);
      expect(again.byId('1')!.pinned, isTrue);
      expect(again.byId('2')!.text, 'beta edited');
      expect(again.search('edited').single.id, '2');
    });

    test('put with an existing id replaces the note', () async {
      final store = NoteStore(dir);
      await store.put(note('1', 'one'));
      await store.put(note('1', 'uno'));
      expect(store.notes, hasLength(1));
      expect(store.byId('1')!.text, 'uno');
    });

    test('delete removes the note and its audio file', () async {
      final audio = File('${dir.path}/1.wav')..writeAsBytesSync([1, 2, 3]);
      final store = NoteStore(dir);
      await store.put(note('1', 'one', audio: audio.path));
      await store.delete('1');
      expect(store.notes, isEmpty);
      expect(audio.existsSync(), isFalse);

      final again = NoteStore(dir);
      await again.load();
      expect(again.notes, isEmpty);
    });

    test('a damaged file loads as an empty list', () async {
      File('${dir.path}/notes.json').writeAsStringSync('{not json');
      final store = NoteStore(dir);
      await store.load();
      expect(store.notes, isEmpty);
    });
  });
}
