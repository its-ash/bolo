# Bolo (package: bolo / com.itsash.bolo)

Voice notes turned into searchable text, on the device. Tap record, talk, get live text. Notes
list with full-text search, audio playback, edit, pin, share, delete. Hindi, English (India) or the
device language. Flutter UI; Kotlin owns the microphone and the speech recognizer.

## Mic and recognizer design (read this first)

Android's `SpeechRecognizer` opens the microphone itself, and on many devices a second recorder
(MediaRecorder / AudioRecord) in the same app either gets silence or makes the recognizer fail. So
there are two modes, picked per note by the "Keep audio" switch and the Android version:

1. **Text only** (default fallback, works on every device): the recognizer owns the mic. Nothing is
   recorded. The note has no audio.
2. **Text + audio** (Android 13 / API 33+): the app owns the mic. `AudioTee.kt` records 16 kHz mono
   PCM with `AudioRecord` into `files/audio/<noteId>.wav` and feeds the same samples to the
   recognizer through a pipe given in `RecognizerIntent.EXTRA_AUDIO_SOURCE` (plus channel count,
   encoding, sampling rate extras). The recognizer never touches the mic, so no conflict. The pipe
   is replaced on every recognizer restart; the WAV keeps recording across restarts.
   - Not every recognition service honours `EXTRA_AUDIO_SOURCE`. If the recognizer errors before it
     has produced any text in this mode, `SpeechEngine.dropAudioIfFresh` deletes the WAV, goes back
     to text only for this note, and sends the notice `audio_unsupported` (Dart shows a banner).
   - Below API 33 the switch has no effect: `audio_needs_13` notice, text only.
   - WAV is about 1.9 MB per minute. Deleting a note deletes its WAV.

Other decisions:
- On-device first: `createOnDeviceSpeechRecognizer` on API 31+ when `isOnDeviceRecognitionAvailable`,
  else `createSpeechRecognizer` with `EXTRA_PREFER_OFFLINE`. No speech pack and no internet
  (`ERROR_LANGUAGE_*`, `ERROR_NETWORK*`, `ERROR_SERVER*`) gives `error` with `offlineMissing: true`;
  the record screen shows "Download language", which calls `openLanguageSettings` (best-effort
  `triggerModelDownload` on API 33+, then Google speech settings, voice input settings, locale
  settings, settings).
- Continuous dictation: the recognizer ends after every pause. `SpeechEngine` restarts it after a
  result, `ERROR_NO_MATCH` and `ERROR_SPEECH_TIMEOUT` while the user has not pressed stop
  (`ERROR_RECOGNIZER_BUSY` recreates the recognizer, 3 tries). Dart appends the finals
  (`lib/speech/transcript.dart`).
- No foreground service: the recognizer stops when the app is hidden on Android 12+, so the record
  screen saves what it has on `AppLifecycleListener.onHide`.
- Some recognizers beep on every restart. Not handled.
- Only the mic permission (`RECORD_AUDIO`, asked on first record). `INTERNET` is for the update
  check only. No analytics.

## Channels (`MainActivity.kt`, `lib/speech/speech_platform.dart`)

`com.itsash.bolo/control` (methods): `status`, `requestMic`, `start({id, lang, keepAudio})` ->
`{audio}`, `stop` -> `{audioPath, durationMs}` (waits for the last text), `openLanguageSettings`,
`openAppSettings`, `play`, `pausePlay`, `stopPlay`, `seek`, `shareText`, `shareAudio` (FileProvider
`${applicationId}.files`, `res/xml/file_paths.xml`).
`com.itsash.bolo/events` (stream of maps with `type`): `partial`, `final`, `state`, `error`,
`notice`, `level` (from `SpeechEngine`), `play` (from `Player.kt`).

## Data

`files/notes.json` (list of `Note`: id = start time in ms, text, createdAt, updatedAt, lang, pinned,
audioPath, durationMs) and `files/settings.json` (lang, keepAudio). Written through a temp file and
rename. Search is in memory (`lib/notes/note_search.dart`): every word must appear, case-insensitive,
partial words match, more hits rank first.

## Code layout

- `lib/main.dart`: `BoloServices` (platform, notes, settings), `BoloApp`.
- `lib/notes/`: `note.dart`, `note_store.dart`, `note_search.dart`, `settings.dart`.
- `lib/speech/`: `speech_platform.dart` (interface + channel), `dictation.dart`
  (`DictationController`), `transcript.dart` (`TranscriptBuilder`), `languages.dart`.
- `lib/screens/`: `home_screen.dart`, `record_screen.dart`, `note_screen.dart`,
  `settings_screen.dart` (ends with `UiAppearanceSection`, `UiUpdateSection(storeId: 'bolo')`,
  `UiDeveloperSection`).
- `android/app/src/main/kotlin/com/itsash/bolo/`: `SpeechEngine.kt`, `AudioTee.kt`, `Player.kt`,
  `MainActivity.kt`.
- Tests: `test/` (transcript merging, note store and search, dictation controller with a fake
  platform). The Kotlin side is not unit tested; verify on a device.

## Commands

- `make run`, `make build`, `make test` (analyze + Dart tests), `make clean`.
- Icon: `assets/icon/*.svg` (violet and white, pixel mic + text lines) -> PNG 1024 -> `dart run flutter_launcher_icons`.

## Conventions

- minSdk 26. UI only from `../theme` (read `../theme/COMPONENTS.md`).

## Release (Ash Store)

- `store.json` (id `bolo`, repo its-ash/bolo), `store.mk`, `index.html` + `CNAME` (`bolo.itsash.in`).
  See `../ash-store/store-kit/STORE.md`.
- `make deploy` = bump version, build, commit, tag, push, GitHub release with `bolo.apk`. Never
  create releases, tags or asset names by hand.
- Do not edit `store.mk` here. Edit `../ash-store/store-kit/store.mk`, then run `make store-sync`
  at the workspace root.
