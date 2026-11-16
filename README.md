# Bolo

Speak and it becomes searchable text. Voice notes in English and Hindi, on your phone.

**[Website](https://bolo.itsash.in)** · **[Download APK](https://github.com/its-ash/bolo/releases/latest/download/bolo.apk)** · Get it in **[Ash Store](https://store.itsash.in)**

## Features

- **Big record button, live text**: your words appear while you speak. Uses the speech recognizer
  on your phone, on-device when a speech pack is installed.
- **Keeps listening**: pauses do not end the note; Bolo restarts the recognizer and appends.
- **English (India), Hindi or device language.** If the offline pack is missing, a button opens
  the language download settings.
- **Keeps the audio** on Android 13 and later when the speech service allows it. Otherwise the
  note is text only.
- **Search** across every transcript, **edit** mistakes, **pin** notes, **play** the audio,
  **share** the text or the audio, **delete**.
- **Private**: no account, nothing uploaded by Bolo. The only network call is the update check
  in Settings.

## Install

- **Ash Store**: install [Ash Store](https://store.itsash.in) once, then install and update Bolo from it.
- **APK**: download the [latest APK](https://github.com/its-ash/bolo/releases/latest/download/bolo.apk) on your phone and open it. Allow your browser to install unknown apps if Android asks.

Requires Android 8.0 (API 26) or later. For offline dictation install the speech pack for your
language (Settings, Speech language packs).

## Develop

Needs Flutter 3.44 or later and the shared theme package at `../theme`.

```bash
make run     # run on a connected device
make test    # flutter analyze + flutter test
make build   # release APK
make deploy  # bump version, build, tag, push, GitHub release (see store.mk)
```

## Release

`make deploy` follows the Ash Store kit (`store.mk`, `store.json`): it bumps the version in
`pubspec.yaml`, builds, commits, tags `vX.Y.Z`, pushes, and publishes a GitHub release with
`bolo.apk`. Ash Store and the website pick up the new version from that release.

## Project layout

```
lib/
├── main.dart
├── notes/       # Note, NoteStore (notes.json), search, settings
├── speech/      # platform channel, DictationController, TranscriptBuilder, languages
└── screens/     # home, record, note, settings
android/app/src/main/kotlin/com/itsash/bolo/
├── SpeechEngine.kt   # SpeechRecognizer, restarts, on-device first
├── AudioTee.kt       # records WAV and feeds the recognizer (Android 13+)
├── Player.kt         # audio playback
└── MainActivity.kt   # channels, permission, share
```

See `CLAUDE.md` for the mic and recognizer design.

## License

No license file is included yet.

Built by [itsash.in](https://itsash.in).
