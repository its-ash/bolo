/// A dictation language. [tag] is a BCP-47 tag, or '' for the device language.
class SpeechLanguage {
  const SpeechLanguage(this.tag, this.label);

  final String tag;
  final String label;

  static const all = [
    SpeechLanguage('en-IN', 'English (India)'),
    SpeechLanguage('hi-IN', 'Hindi'),
    SpeechLanguage('', 'Device default'),
  ];

  static SpeechLanguage of(String tag) => all.firstWhere((l) => l.tag == tag, orElse: () => all.last);
}
