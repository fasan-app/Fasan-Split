import 'dart:math';

import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_split/collab/notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Notiz: Text setzen, lesen, ändern', () {
    final d = LwwDoc('aa');
    final id = Notes.create(d, 'Einkauf');
    Notes.setText(d, id, 'Brot\nMilch\nKäse');
    expect(Notes.text(d, id), 'Brot\nMilch\nKäse');
    Notes.setText(d, id, 'Brot\nHafermilch\nKäse\nOliven');
    expect(Notes.text(d, id), 'Brot\nHafermilch\nKäse\nOliven');
    Notes.setText(d, id, '');
    expect(Notes.text(d, id), '');
    expect(Notes.list(d).single.title, 'Einkauf');
  });

  test('Zwei tippen an verschiedenen Stellen: beides bleibt', () {
    final a = LwwDoc('aa'), b = LwwDoc('bb');
    final id = Notes.create(a, 'Plan');
    Notes.setText(a, id, 'Strand\nEssen\nHeimfahrt');
    b.merge(a.entries);
    Notes.setText(a, id, 'Strand\nEssen\nHeimfahrt\nEis');
    Notes.setText(b, id, 'Strand früh\nEssen\nHeimfahrt'.replaceFirst('Strand früh', 'Dusche\nStrand'));
    a.merge(b.entries);
    b.merge(a.entries);
    final t = Notes.text(a, id);
    expect(Notes.text(b, id), t);
    expect(t, contains('Eis'));
    expect(t, contains('Dusche'));
    expect(t.split('\n'), containsAllInOrder(['Dusche', 'Strand', 'Essen', 'Heimfahrt', 'Eis']));
  });

  test('Gleiche Zeile gleichzeitig: beide Fassungen bleiben, nichts verschwindet', () {
    final a = LwwDoc('aa'), b = LwwDoc('bb');
    final id = Notes.create(a, 'x');
    Notes.setText(a, id, 'Hotel');
    b.merge(a.entries);
    Notes.setText(a, id, 'Hotel Sol');
    Notes.setText(b, id, 'Hotel Mar');
    a.merge(b.entries);
    b.merge(a.entries);
    expect(Notes.text(a, id), Notes.text(b, id));
    expect(Notes.text(a, id), allOf(contains('Hotel Sol'), contains('Hotel Mar')));
  });

  test('Zufall: Text nach jeder Bearbeitung exakt wie eingegeben (300 Läufe)', () {
    final r = Random(5);
    final words = ['a', 'b', 'c', 'd', 'e', 'f'];
    for (var run = 0; run < 300; run++) {
      final d = LwwDoc('aa');
      final id = Notes.create(d, 't');
      for (var step = 0; step < 8; step++) {
        final lines = [for (var i = 0; i < r.nextInt(8); i++) words[r.nextInt(words.length)]];
        final t = lines.join('\n');
        Notes.setText(d, id, t);
        expect(Notes.text(d, id), t);
      }
    }
  });

  test('Chat sortiert nach Zeit', () {
    final d = LwwDoc('aa');
    Notes.send(d, 'p1', 'Hallo');
    Notes.send(d, 'p2', 'Wer zahlt?');
    final m = Notes.messages(d);
    expect(m.map((x) => x.text), ['Hallo', 'Wer zahlt?']);
  });
}
