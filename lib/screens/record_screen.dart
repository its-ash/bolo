import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../main.dart';
import '../speech/dictation.dart';
import '../speech/languages.dart';
import '../speech/speech_platform.dart';

/// The big record button with live text. Pops with the saved note's id.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.services});

  final BoloServices services;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final DictationController _dictation = DictationController(s.platform);
  late final AppLifecycleListener _lifecycle;
  final _scroll = ScrollController();
  SpeechStatus? _status;
  bool _saving = false;

  BoloServices get s => widget.services;

  @override
  void initState() {
    super.initState();
    s.platform.status().then((v) {
      if (mounted) setState(() => _status = v);
    });
    _dictation.addListener(_followText);
    // Leaving the app ends the recognizer on Android 12+, so save what we have.
    _lifecycle = AppLifecycleListener(
      onHide: () {
        if (_dictation.isActive && _dictation.phase == DictationPhase.active) _finish();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _dictation.removeListener(_followText);
    _dictation.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _followText() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _toggle() async {
    if (_dictation.phase == DictationPhase.active) {
      await _finish();
    } else if (_dictation.phase == DictationPhase.idle) {
      await _dictation.start(lang: s.settings.lang, keepAudio: s.settings.keepAudio);
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    _saving = true;
    final note = await _dictation.stop();
    if (note != null) await s.notes.put(note);
    _saving = false;
    if (!mounted) return;
    if (note == null) {
      context.showToast('Nothing was heard, so no note was saved.');
    }
    Navigator.of(context).pop(note?.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_dictation, s.settings]),
      builder: (context, _) {
        final d = _dictation;
        final active = d.phase == DictationPhase.active;
        final busy = d.phase == DictationPhase.starting || d.phase == DictationPhase.stopping;
        return PopScope(
          canPop: !active && !busy,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && active) _finish();
          },
          child: UiScaffold(
            appBar: const UiAppBar(title: 'New note'),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UiChoiceChips<String>(
                  scrollable: true,
                  value: s.settings.lang,
                  onChanged: active || busy ? null : s.settings.setLang,
                  options: [for (final l in SpeechLanguage.all) UiChoice(l.tag, l.label)],
                ),
                const SizedBox(height: UiSpace.sm),
                UiSwitchTile(
                  'Keep audio',
                  icon: Icons.graphic_eq_rounded,
                  value: s.settings.keepAudio,
                  subtitle: _status != null && !_status!.canKeepAudio
                      ? 'Needs Android 13 or later. Text is still saved.'
                      : 'Save a recording next to the text, when the phone allows it.',
                  onChanged: active || busy ? null : s.settings.setKeepAudio,
                ),
                const SizedBox(height: UiSpace.md),
                if (d.errorCode != null) ...[_ErrorBanner(dictation: d, services: s), const SizedBox(height: UiSpace.md)],
                if (d.notice != null) ...[_NoticeBanner(code: d.notice!), const SizedBox(height: UiSpace.md)],
                Expanded(child: _Transcript(dictation: d, controller: _scroll)),
                const SizedBox(height: UiSpace.md),
                Center(child: _RecordButton(active: active, busy: busy, level: d.level, onTap: _toggle)),
                const SizedBox(height: UiSpace.sm),
                Center(
                  child: Text(
                    active
                        ? (d.halted ? 'Stopped. Tap to save' : 'Listening. Tap to stop and save')
                        : busy
                        ? 'Please wait'
                        : 'Tap to start talking',
                    style: context.text.bodySmall?.copyWith(color: context.colors.textMuted),
                  ),
                ),
                const SizedBox(height: UiSpace.md),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({required this.dictation, required this.controller});

  final DictationController dictation;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final empty = dictation.text.isEmpty;
    return UiCard(
      variant: UiCardVariant.outlined,
      child: SizedBox.expand(
        child: SingleChildScrollView(
          controller: controller,
          child: empty
              ? Text(
                  dictation.isActive ? 'Say something…' : 'Your words will appear here.',
                  style: context.text.bodyLarge?.copyWith(color: colors.textSubtle),
                )
              : Text.rich(
                  TextSpan(
                    style: context.text.bodyLarge,
                    children: [
                      TextSpan(text: dictation.committedText),
                      if (dictation.partialText.isNotEmpty)
                        TextSpan(
                          text: '${dictation.committedText.isEmpty ? '' : ' '}${dictation.partialText}',
                          style: TextStyle(color: colors.textMuted),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.active, required this.busy, required this.level, required this.onTap});

  final bool active;
  final bool busy;
  final double level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fill = active ? colors.danger : colors.accent;
    final double halo = 96 + 40 * (active ? level : 0.0);
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: halo,
            height: halo,
            decoration: BoxDecoration(shape: BoxShape.circle, color: fill.withValues(alpha: 0.18)),
          ),
          Semantics(
            button: true,
            label: active ? 'Stop and save' : 'Start recording',
            child: Material(
              color: fill,
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : onTap,
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: busy
                      ? const Center(child: UiSpinner(size: 28))
                      : Icon(active ? Icons.stop_rounded : Icons.mic_rounded, size: 44, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final message = switch (code) {
      'audio_unsupported' =>
        'This phone\'s speech service cannot share the microphone, so Bolo saves text only for this note.',
      'audio_needs_13' => 'Keeping audio needs Android 13 or later. Saving text only.',
      'audio_unavailable' => 'Could not start the audio recording. Saving text only.',
      _ => code,
    };
    return UiAlert(message, status: UiStatus.info);
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.dictation, required this.services});

  final DictationController dictation;
  final BoloServices services;

  @override
  Widget build(BuildContext context) {
    final code = dictation.errorCode ?? '';
    final lang = services.settings.lang;
    final name = SpeechLanguage.of(lang).label;
    String message;
    String? action;
    VoidCallback? onAction;
    if (dictation.offlineMissing) {
      message =
          'No offline speech pack for $name is installed, and there is no internet. '
          'Download the language pack, then try again.';
      action = 'Download language';
      onAction = () => services.platform.openLanguageSettings(lang);
    } else {
      switch (code) {
        case 'mic_denied':
          message = 'Bolo needs the microphone to hear you.';
          action = 'Open settings';
          onAction = services.platform.openAppSettings;
        case 'permission':
          message = 'The speech service was not allowed to use the microphone.';
          action = 'Open settings';
          onAction = services.platform.openAppSettings;
        case 'no_recognizer':
          message = 'This phone has no speech recognition service. Install or enable Speech Services by Google.';
          action = 'Open settings';
          onAction = () => services.platform.openLanguageSettings(lang);
        case 'busy':
          message = 'The speech service is busy. Close other apps that use the microphone and try again.';
        default:
          message = 'Speech recognition stopped ($code). Tap record to try again.';
      }
    }
    return UiAlert(
      message,
      status: UiStatus.warning,
      action: action == null ? null : UiButton(action, size: UiSize.sm, variant: UiButtonVariant.secondary, onPressed: onAction),
    );
  }
}
