import 'package:bolo/speech/transcript.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('partial shows after finished text and a final replaces it', () {
    final t = TranscriptBuilder();
    t.onPartial('hello');
    expect(t.text, 'hello');
    t.onPartial('hello world');
    t.onFinal('hello world');
    expect(t.committed, 'hello world');
    expect(t.partial, '');
    t.onPartial('how are');
    expect(t.text, 'hello world how are');
  });

  test('segments from restarted sessions are appended with a space', () {
    final t = TranscriptBuilder();
    t.onFinal('first part');
    t.onFinal('  second part ');
    t.onFinal('third');
    expect(t.text, 'first part second part third');
  });

  test('empty finals and partials change nothing', () {
    final t = TranscriptBuilder('start');
    t.onFinal('');
    t.onPartial('   ');
    expect(t.text, 'start');
  });

  test('a duplicate final with no speech in between is dropped, a real repeat is kept', () {
    final t = TranscriptBuilder();
    t.onFinal('yes');
    t.onFinal('yes');
    expect(t.text, 'yes');
    t.onPartial('yes');
    t.onFinal('yes');
    expect(t.text, 'yes yes');
  });

  test('flush keeps a pending partial', () {
    final t = TranscriptBuilder();
    t.onFinal('one');
    t.onPartial('two');
    t.flush();
    expect(t.committed, 'one two');
    expect(t.partial, '');
  });

  test('Hindi text merges the same way', () {
    final t = TranscriptBuilder();
    t.onFinal('नमस्ते दोस्तों');
    t.onFinal('आज मौसम अच्छा है');
    expect(t.text, 'नमस्ते दोस्तों आज मौसम अच्छा है');
  });
}
