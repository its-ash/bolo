import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../main.dart';
import '../speech/languages.dart';

/// Dictation options, then Appearance, Updates and Developer.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.services});

  final BoloServices services;

  @override
  Widget build(BuildContext context) {
    final settings = services.settings;
    return UiScaffold(
      appBar: const UiAppBar(title: 'Settings'),
      scrollable: true,
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => UiColumn(
          gap: UiSpace.lg,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiSection(
              title: 'Dictation',
              child: UiColumn(
                gap: UiSpace.md,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  UiChoiceChips<String>(
                    scrollable: true,
                    value: settings.lang,
                    onChanged: settings.setLang,
                    options: [for (final l in SpeechLanguage.all) UiChoice(l.tag, l.label)],
                  ),
                  UiSwitchTile(
                    'Keep audio',
                    icon: Icons.graphic_eq_rounded,
                    value: settings.keepAudio,
                    subtitle: 'Save a recording next to the text on Android 13 or later, when the speech service allows it.',
                    onChanged: settings.setKeepAudio,
                  ),
                  UiListTile(
                    'Speech language packs',
                    subtitle: 'Download a language so dictation works offline.',
                    icon: Icons.download_rounded,
                    chevron: true,
                    onTap: () => services.platform.openLanguageSettings(settings.lang),
                  ),
                ],
              ),
            ),
            const UiAppearanceSection(),
            const UiUpdateSection(storeId: 'bolo'),
            const UiDeveloperSection(),
          ],
        ),
      ),
    );
  }
}
