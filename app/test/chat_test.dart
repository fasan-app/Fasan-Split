// SPDX-License-Identifier: MPL-2.0
import 'dart:math';

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
    Notes.reactMessage(d, id, 'ali', '❤️');
    expect(Notes.messages(d).single.reactions, {'ben': '👍', 'ali': '❤️'});
    Notes.reactMessage(d, id, 'ben', '👍');
    expect(Notes.messages(d).single.reactions, {'ali': '❤️'});
    Notes.reactMessage(d, id, 'ali', '😂');
    expect(Notes.messages(d).single.reactions, {'ali': '😂'});
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

  test('Erwähnung wird mit der Nachricht gespeichert, Anpinnen ist ein eigener Schlüssel und lässt sich lösen', () {
    final d = LwwDoc('aa');
    Notes.send(d, 'anna', '@Ben Pizza?', mentions: ['ben']);
    Notes.send(d, 'anna', 'ohne');
    final m = Notes.messages(d);
    expect(m[0].mentions, ['ben']);
    expect(m[1].mentions, isEmpty);
    expect(m[0].pinned, isFalse);
    Notes.pinMessage(d, m[0].id, true);
    expect(Notes.messages(d).where((x) => x.pinned).map((x) => x.id), [m[0].id]);
    expect(Notes.messages(d).length, 2, reason: 'a pin is not a message');
    Notes.pinMessage(d, m[0].id, false);
    expect(Notes.messages(d).any((x) => x.pinned), isFalse);
    Notes.pinMessage(d, 'gibtsnicht', true);
    expect(d.keys('c/gibtsnicht').isEmpty, isTrue);
    // editing keeps the mention and the pin
    Notes.pinMessage(d, m[0].id, true);
    Notes.editMessage(d, m[0].id, 'anna', '@Ben Pizza heute?');
    final e = Notes.messages(d).first;
    expect(e.mentions, ['ben']);
    expect(e.pinned, isTrue);
  });

  test('Zufall: drei Geräte, beliebige Aktionen und Abgleiche – am Ende überall derselbe Chat (200 Läufe)', () {
    String view(LwwDoc d) => Notes.messages(d)
        .map((m) => '${m.id}|${m.from}|${m.text}|${m.at.millisecondsSinceEpoch}|${m.reply}|${m.edited}|${m.deleted}|${m.pinned}|${(m.reactions.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join(',')}|${m.mentions.join(',')}')
        .join('\n');
    for (var run = 0; run < 200; run++) {
      final r = Random(run);
      final docs = [LwwDoc('aa'), LwwDoc('bb'), LwwDoc('cc')];
      const who = ['anna', 'ben', 'ali'];
      for (var step = 0; step < 40; step++) {
        final i = r.nextInt(3), d = docs[i];
        final msgs = Notes.messages(d);
        switch (r.nextInt(7)) {
          case 0 || 1:
            Notes.send(d, who[i], 'Text ${r.nextInt(100)}', reply: msgs.isNotEmpty && r.nextBool() ? msgs[r.nextInt(msgs.length)].id : null, mentions: r.nextBool() ? [who[(i + 1) % 3]] : const []);
          case 2 when msgs.isNotEmpty:
            final m = msgs[r.nextInt(msgs.length)];
            Notes.editMessage(d, m.id, m.from, 'neu ${r.nextInt(100)}');
          case 3 when msgs.isNotEmpty:
            final m = msgs[r.nextInt(msgs.length)];
            Notes.deleteMessage(d, m.id, m.from);
          case 4 when msgs.isNotEmpty:
            Notes.reactMessage(d, msgs[r.nextInt(msgs.length)].id, who[i], ['👍', '❤️', '😂'][r.nextInt(3)]);
          case 5 when msgs.isNotEmpty:
            Notes.pinMessage(d, msgs[r.nextInt(msgs.length)].id, r.nextBool());
          default:
            final j = r.nextInt(3);
            if (j != i) docs[j].merge(d.entries);
        }
      }
      // full exchange, twice and in different orders
      for (final d in docs) {
        for (final o in docs) {
          d.merge(o.entries);
        }
      }
      for (final o in docs.reversed) {
        for (final d in docs) {
          d.merge(o.entries);
        }
      }
      expect(view(docs[1]), view(docs[0]), reason: 'run $run');
      expect(view(docs[2]), view(docs[0]), reason: 'run $run');
      // every reply points to a message that exists (deleted ones stay as markers); no message without a sender
      final ids = Notes.messages(docs[0]).map((m) => m.id).toSet();
      for (final m in Notes.messages(docs[0])) {
        expect(m.from, isNotEmpty);
        if (m.reply != null) expect(ids.contains(m.reply), isTrue, reason: 'run $run: reply to a missing message');
        if (m.deleted) expect(m.text, '');
      }
    }
  });
}
