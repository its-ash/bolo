import 'dart:io';

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import 'notes/note_store.dart';
import 'notes/settings.dart';
import 'screens/home_screen.dart';
import 'speech/speech_platform.dart';

/// Everything the screens share.
class BoloServices {
  const BoloServices({required this.platform, required this.notes, required this.settings});

  final SpeechPlatform platform;
  final NoteStore notes;
  final BoloSettings settings;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = ChannelSpeechPlatform();
  final status = await platform.status();
  final dir = Directory(status.filesDir);
  final notes = NoteStore(dir);
  final settings = BoloSettings(dir);
  await Future.wait([notes.load(), settings.load()]);
  runApp(BoloApp(services: BoloServices(platform: platform, notes: notes, settings: settings)));
}

class BoloApp extends StatelessWidget {
  const BoloApp({super.key, required this.services});

  final BoloServices services;

  @override
  Widget build(BuildContext context) {
    return UiApp(
      title: 'Bolo',
      home: HomeScreen(services: services),
    );
  }
}
