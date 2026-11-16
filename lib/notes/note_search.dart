import 'note.dart';

/// Splits a search query into lowercase words.
List<String> searchTerms(String query) =>
    query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

/// Notes in display order: pinned first, then newest first.
List<Note> sortNotes(Iterable<Note> notes) {
  final list = notes.toList();
  list.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return b.createdAt.compareTo(a.createdAt);
  });
  return list;
}

/// Full-text search over transcripts. Every word of [query] must appear somewhere in the text
/// (case-insensitive, partial words match). Best match first (more hits, then pinned, then newest).
/// An empty query returns every note in display order.
List<Note> searchNotes(Iterable<Note> notes, String query) {
  final terms = searchTerms(query);
  if (terms.isEmpty) return sortNotes(notes);
  final scored = <(Note, int)>[];
  for (final n in notes) {
    final text = n.text.toLowerCase();
    var score = 0;
    var all = true;
    for (final t in terms) {
      final hits = _count(text, t);
      if (hits == 0) {
        all = false;
        break;
      }
      score += hits;
    }
    if (all) scored.add((n, score));
  }
  scored.sort((a, b) {
    if (a.$2 != b.$2) return b.$2.compareTo(a.$2);
    if (a.$1.pinned != b.$1.pinned) return a.$1.pinned ? -1 : 1;
    return b.$1.createdAt.compareTo(a.$1.createdAt);
  });
  return [for (final s in scored) s.$1];
}

int _count(String text, String term) {
  var n = 0;
  var i = text.indexOf(term);
  while (i >= 0) {
    n++;
    i = text.indexOf(term, i + term.length);
  }
  return n;
}

/// A short piece of [text] around the first match of any term, for list rows.
String snippet(String text, String query, {int length = 120}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= length) return flat;
  final lower = flat.toLowerCase();
  var at = -1;
  for (final t in searchTerms(query)) {
    final i = lower.indexOf(t);
    if (i >= 0 && (at < 0 || i < at)) at = i;
  }
  if (at < 0) return '${flat.substring(0, length).trimRight()}…';
  var start = at - length ~/ 3;
  if (start < 0) start = 0;
  final end = start + length > flat.length ? flat.length : start + length;
  return '${start > 0 ? '…' : ''}${flat.substring(start, end).trim()}${end < flat.length ? '…' : ''}';
}
