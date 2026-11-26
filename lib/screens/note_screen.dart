import 'dart:async';

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../main.dart';
import '../notes/note.dart';
import '../speech/languages.dart';
import 'format.dart';

enum _Action { shareText, shareAudio, delete }

/// One note: play the audio, edit the transcript, pin, share, delete.
class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key, required this.services, required this.noteId});

  final BoloServices services;
  final String noteId;

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  late final TextEditingController _text;
  StreamSubscription<dynamic>? _sub;
  Timer? _debounce;

  bool _playing = false;
  int _pos = 0;
  int _dur = 0;
  bool _deleted = false;

  BoloServices get s => widget.services;
  Note? get note => s.notes.byId(widget.noteId);

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: note?.text ?? '');
    _dur = note?.durationMs ?? 0;
    _sub = s.platform.events.listen((e) {
      if (e.type != 'play' || e.path != note?.audioPath || !mounted) return;
      setState(() {
        _playing = e.playing;
        _pos = e.posMs;
        if (e.durMs > 0) _dur = e.durMs;
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (!_deleted) {
      // Not synchronously: listeners must not rebuild while this screen is being removed.
      final (id, text, notes) = (widget.noteId, _text.text, s.notes);
      Future.microtask(() => notes.updateText(id, text));
    }
    _sub?.cancel();
    if (_playing || _pos > 0) s.platform.stopPlay();
    _text.dispose();
    super.dispose();
  }

  void _saveNow() {
    if (!_deleted) s.notes.updateText(widget.noteId, _text.text);
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  Future<void> _togglePlay(Note n) async {
    if (_playing) {
      await s.platform.pausePlay();
    } else {
      final ok = await s.platform.play(n.audioPath!);
      if (!ok && mounted) context.showToast('Could not play this audio.', status: UiStatus.danger);
    }
  }

  Future<void> _onAction(_Action a, Note n) async {
    switch (a) {
      case _Action.shareText:
        _saveNow();
        await s.platform.shareText(_text.text);
      case _Action.shareAudio:
        try {
          await s.platform.shareAudio(n.audioPath!);
        } catch (_) {
          if (mounted) context.showToast('The audio file is missing.', status: UiStatus.danger);
        }
      case _Action.delete:
        final ok = await UiDialog.confirm(
          context,
          title: 'Delete this note?',
          message: n.hasAudio ? 'The text and the audio will be removed from this phone.' : 'The text will be removed from this phone.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (!ok) return;
        _deleted = true;
        await s.platform.stopPlay();
        await s.notes.delete(n.id);
        if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s.notes,
      builder: (context, _) {
        final n = note;
        if (n == null) return const UiScaffold(body: SizedBox.shrink());
        return UiScaffold(
          scrollable: true,
          appBar: UiAppBar(
            title: formatWhen(n.createdAt),
            actions: [
              UiIconButton(
                n.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                tooltip: n.pinned ? 'Unpin' : 'Pin',
                onPressed: () => s.notes.togglePin(n.id),
              ),
              UiMenuButton<_Action>(
                onSelected: (a) => _onAction(a, n),
                items: [
                  const UiMenuItem(_Action.shareText, 'Share text', icon: Icons.notes_rounded),
                  if (n.hasAudio) const UiMenuItem(_Action.shareAudio, 'Share audio', icon: Icons.graphic_eq_rounded),
                  const UiMenuItem.divider(),
                  const UiMenuItem(_Action.delete, 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
                ],
              ),
            ],
          ),
          body: UiColumn(
            gap: UiSpace.md,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (n.hasAudio) _player(context, n),
              UiTextArea(
                controller: _text,
                label: 'Transcript',
                hint: 'Nothing was heard. Type your note here.',
                minLines: 8,
                maxLines: 40,
                onChanged: _onChanged,
              ),
              Text(
                '${SpeechLanguage.of(n.lang).label}'
                '${n.updatedAt.isAfter(n.createdAt.add(const Duration(seconds: 5))) ? ' · edited ${formatWhen(n.updatedAt)}' : ''}',
                style: context.text.bodySmall?.copyWith(color: context.colors.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _player(BuildContext context, Note n) {
    final dur = _dur > 0 ? _dur : n.durationMs;
    final max = dur > 0 ? dur.toDouble() : 1.0;
    return UiCard(
      padding: const EdgeInsets.symmetric(horizontal: UiSpace.md, vertical: UiSpace.sm),
      child: Row(
        children: [
          UiIconButton(
            _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: _playing ? 'Pause' : 'Play',
            variant: UiButtonVariant.primary,
            circular: true,
            onPressed: () => _togglePlay(n),
          ),
          Expanded(
            child: UiSlider(
              value: _pos.clamp(0, dur > 0 ? dur : 1).toDouble(),
              max: max,
              showValue: false,
              onChanged: _playing || _pos > 0 ? (v) => s.platform.seek(v.round()) : null,
            ),
          ),
          Text(
            '${formatDuration(_pos)} / ${formatDuration(dur)}',
            style: context.text.bodySmall?.copyWith(color: context.colors.textMuted),
          ),
        ],
      ),
    );
  }
}
