// SPDX-License-Identifier: MPL-2.0
// „Speichern dauert sehr lange“ (Nutzer 07.11.): the snippets are encoded once, and the write after a save is bundled.
import 'dart:typed_data';

import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Snippet wird nur einmal in base64 umgewandelt', () {
    final it = BillItem(name: 'Cola', amount: 320, snippet: Uint8List.fromList(List.filled(5000, 7)));
    final a = it.toJson()['snippet'];
    final b = it.toJson()['snippet'];
    expect(identical(a, b), isTrue, reason: 'second save must reuse the encoded text');
  });

  test('Speichern schreibt gebündelt nach dem Schließen, flush sofort', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await BillStore.load();
    final b = Bill(id: 'x', created: DateTime(2026), total: 100, items: [BillItem(name: 'A', amount: 100)], people: []);
    store.upsert(b);
    store.upsert(b);
    expect(store.lastWrite?.bills ?? 0, 0, reason: 'nothing written inside the frame of the tap');
    store.flush();
    expect(store.lastWrite?.bills, 1);
    final saved = (await SharedPreferences.getInstance()).getString('bills.v1');
    expect(saved, isNotNull);
  });
}
