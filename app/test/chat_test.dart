import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_split/collab/notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Antwort: Zitat zeigt auf die Nachricht', () {
    final d = LwwDoc('aa');
    Notes.send(d, 'anna', 'Wer holt Brot?');
    final first = Notes.messages(d).single;
    Notes.send(d, 'ben', 'Ich', reply: first.id);
    final m = Notes.messages(d);
    expect(m.length, 2);
    expect(m[0].reply, isNull);
    expect(m[1].reply, first.id);
  });

  test('Bearbeiten: nur der Autor, Markierung „bearbeitet“, Zeit bleibt', () {
    final d = LwwDoc('aa');
    Notes.send(d, 'anna', 'Tippfehlr');
    final m0 = Notes.messages(d).single;
    expect(Notes.editMessage(d, m0.id, 'ben', 'x'), isFalse);
    expect(Notes.editMessage(d, m0.id, 'anna', '  '), isFalse);
    expect(Notes.editMessage(d, m0.id, 'anna', 'Tippfehler'), isTrue);
    final m = Notes.messages(d).single;
    expect(m.text, 'Tippfehler');
    expect(m.edited, isTrue);
    expect(m.at, m0.at);
  });

  test('Löschen: Text weg, Marker bleibt, Zitate lösen weiter auf, nicht mehr bearbeitbar', () {
    final d = LwwDoc('aa');
    Notes.send(d, 'anna', 'geheim');
    final id = Notes.messages(d).single.id;
    Notes.send(d, 'ben', 'ok', reply: id);
    expect(Notes.deleteMessage(d, id, 'ben'), isFalse);
    expect(Notes.deleteMessage(d, id, 'anna'), isTrue);
    final m = Notes.messages(d);
    expect(m.length, 2);
    expect(m[0].deleted, isTrue);
    expect(m[0].text, '');
    expect(m[1].reply, id);
    expect(Notes.editMessage(d, id, 'anna', 'neu'), isFalse);
  });

  test('Reaktion: eine je Person, gleiche nimmt zurück, andere ersetzt; Reaktionen sind keine Nachrichten', () {
    final d = LwwDoc('aa');
    Notes.send(d, 'anna', 'Pizza?');
    final id = Notes.messages(d).single.id;
    Notes.reactMessage(d, id, 'ben', '👍');
    Notes.reactMessage(d, id, 'cem', '❤️');
    expect(Notes.messages(d).single.reactions, {'ben': '👍', 'cem': '❤️'});
    Notes.reactMessage(d, id, 'ben', '👍');
    expect(Notes.messages(d).single.reactions, {'cem': '❤️'});
    Notes.reactMessage(d, id, 'cem', '😂');
    expect(Notes.messages(d).single.reactions, {'cem': '😂'});
    expect(Notes.messages(d).length, 1);
    Notes.reactMessage(d, 'gibtsnicht', 'ben', '👍'); // unknown message: nothing happens
    expect(d.keys('c/gibtsnicht').isEmpty, isTrue);
  });

  test('Zwei Geräte: Reaktionen und Bearbeiten laufen zusammen', () {
    final a = LwwDoc('aa'), b = LwwDoc('bb');
    Notes.send(a, 'anna', 'Hallo');
    b.merge(a.entries);
    final id = Notes.messages(b).single.id;
    Notes.reactMessage(b, id, 'ben', '👍');
    Notes.editMessage(a, id, 'anna', 'Hallo zusammen');
    a.merge(b.entries);
    b.merge(a.entries);
    for (final d in [a, b]) {
      final m = Notes.messages(d).single;
      expect(m.text, 'Hallo zusammen');
      expect(m.reactions, {'ben': '👍'});
    }
  });
}
