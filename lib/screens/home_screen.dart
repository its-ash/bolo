import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../main.dart';
import '../notes/note.dart';
import '../notes/note_search.dart';
import 'format.dart';
import 'note_screen.dart';
import 'record_screen.dart';
import 'settings_screen.dart';

/// Search box, the list of notes and the record button.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});

  final BoloServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _query = '';

  BoloServices get s => widget.services;

  void _open(Note note) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => NoteScreen(services: s, noteId: note.id)),
  );

  Future<void> _record() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => RecordScreen(services: s)),
    );
    if (id != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => NoteScreen(services: s, noteId: id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s.notes,
      builder: (context, _) {
        final notes = s.notes.search(_query);
        final searching = searchTerms(_query).isNotEmpty;
        return UiScaffold(
          appBar: UiAppBar(
            title: 'Bolo',
            actions: [
              UiIconButton(
                Icons.settings_rounded,
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => SettingsScreen(services: s)),
                ),
              ),
            ],
          ),
          fab: UiFab(Icons.mic_rounded, label: 'Record', onPressed: _record),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (s.notes.notes.isNotEmpty) ...[
                UiSearchField(hint: 'Search your notes', onChanged: (v) => setState(() => _query = v)),
                const SizedBox(height: UiSpace.md),
              ],
              Expanded(
                child: notes.isEmpty
                    ? UiEmptyState(
                        icon: searching ? Icons.search_off_rounded : Icons.mic_none_rounded,
                        title: searching ? 'No notes match' : 'No notes yet',
                        message: searching
                            ? 'Try fewer or different words.'
                            : 'Tap Record and start talking. Your words turn into text you can search.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: notes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: UiSpace.sm),
                        itemBuilder: (_, i) => _NoteCard(note: notes[i], query: _query, onTap: () => _open(notes[i])),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.query, required this.onTap});

  final Note note;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final body = snippet(note.text, query);
    final meta = context.text.bodySmall?.copyWith(color: colors.textMuted);
    return UiCard(
      onTap: onTap,
      padding: const EdgeInsets.all(UiSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (note.pinned) ...[
                Icon(Icons.push_pin_rounded, size: 16, color: colors.accent),
                const SizedBox(width: UiSpace.xs),
              ],
              Expanded(
                child: UiHighlightText(
                  note.title,
                  query,
                  style: context.text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (body.isNotEmpty && body != note.title) ...[
            const SizedBox(height: UiSpace.xs),
            UiHighlightText(
              body,
              query,
              style: context.text.bodyMedium?.copyWith(color: colors.textMuted),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: UiSpace.sm),
          Row(
            children: [
              Text(formatWhen(note.createdAt), style: meta),
              if (note.hasAudio) ...[
                const SizedBox(width: UiSpace.md),
                Icon(Icons.graphic_eq_rounded, size: 14, color: colors.textMuted),
                const SizedBox(width: UiSpace.xs),
                Text(formatDuration(note.durationMs), style: meta),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
