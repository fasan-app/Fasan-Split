// SPDX-License-Identifier: MPL-2.0
// Fasan Split – Einträge des replizierten Dokuments: Geräteuhr und App-Version (Nutzer 08.11.). MPL-2.0
import 'dart:convert';

import 'package:fasan_split/collab/lww.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {

  test('Eintrag trägt Geräteuhr und App-Version; alte Einträge ohne beides lesen sich weiter (Nutzer 08.11.)', () {
    Entry.appTag = '0.1.77';
    final d = LwwDoc('aa')..set('k', 1);
    final e = d.entries.single;
    expect(e.app, '0.1.77');
    expect(e.wall, isNotNull);
    final back = Entry.fromJson(jsonDecode(jsonEncode(e.toJson())));
    expect([back.wall, back.app, back.ts], [e.wall, '0.1.77', e.ts]);
    // an entry of an older build has four list items only
    final old = Entry.fromJson(['k', 2, 5, 'bb']);
    expect([old.wall, old.app], [null, null]);
    // an older build reads our entry with its four-item reader: key, value, ts, author are in the same place
    final l = e.toJson();
    expect([l[0], l[1], l[2], l[3]], ['k', 1, e.ts, 'aa']);
    // the winner never depends on the device clock
    expect(Entry('k', 1, 3, 'aa', wall: 1).beats(Entry('k', 2, 2, 'zz', wall: 999999999999)), isTrue);
    Entry.appTag = '';
  });
}
