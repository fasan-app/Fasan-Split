// SPDX-License-Identifier: MPL-2.0
// Fasan Split – group members, balances and settling (model/settle.dart, BillStore, GroupScreen). MPL-2.0
import 'package:fasan_split/main.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_core/settle.dart';
import 'package:fasan_split/flows/scan_queue.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/groups.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A finished bill of [cents], split equally between [people], paid by the first one.
Bill paid(String id, int cents, List<String> people, {String group = 'WG', bool refund = false}) {
  final b = Bill(id: id, created: DateTime(2026), purpose: id, total: cents, done: true)
    ..group = group
    ..payer = 0
    ..refund = refund;
  b.ps.addAll([for (final (i, n) in people.indexed) Person(n, i)]);
  b.its.add(BillItem(name: id, amount: cents)..shares = {for (var i = 0; i < people.length; i++) i: 1});
  return b;
}

void main() {
  test('Saldo über mehrere Bons, Summe immer null', () {
    final bal = balances([paid('a', 3000, ['Anna', 'Ben', 'Ali']), paid('b', 1200, ['Ben', 'Anna'])]);
    expect(bal, {'Anna': 2000 - 600, 'Ben': 600 - 1000, 'Ali': -1000});
    expect(bal.values.fold<int>(0, (a, x) => a + x), 0);
  });

  test('Erstattung dreht die Richtung im Saldo', () {
    final bal = balances([paid('r', 1000, ['Anna', 'Ben'], refund: true)]);
    expect(bal, {'Anna': -500, 'Ben': 500});
  });

  test('Saldo je Mitglied: zwei Schreibweisen einer Person zählen zusammen', () {
    final bills = [paid('a', 1000, ['Anna', 'Ben']), paid('b', 1000, ['Anna', 'Benni'])];
    expect(balances(bills), {'Anna': 1000, 'Ben': -500, 'Benni': -500});
    final bal = balances(bills, key: (n) => n == 'Benni' ? 'Ben' : n);
    expect(bal, {'Anna': 1000, 'Ben': -1000});
    expect(settle(bal), [('Ben', 'Anna', 1000)]);
  });

  test('Mein Stand: je Person über alle Bons', () {
    final bills = [paid('a', 3000, ['Anna', 'Ben', 'Ali']), paid('b', 1200, ['Ben', 'Anna'], group: 'Urlaub')];
    final mine = myDebts(bills, (n) => n == 'Anna');
    expect(mine, {'Ben': 1000 - 600, 'Ali': 1000});
  });

  test('Offene Bons und Bons ohne Zahler zählen nicht', () {
    final open = paid('o', 1000, ['Anna', 'Ben'])..done = false;
    final noPayer = paid('n', 1000, ['Anna', 'Ben'])..payer = null;
    expect(balances([open, noPayer]), isEmpty);
  });

  test('Ausgleich: wenige Überweisungen, gleicht alles aus', () {
    final bal = {'Anna': 1400, 'Ben': -400, 'Ali': -1000, 'Dora': 0};
    final m = settle(bal);
    expect(m, [('Ali', 'Anna', 1000), ('Ben', 'Anna', 400)]);
    final after = Map.of(bal);
    for (final (f, to, c) in m) {
      after[f] = after[f]! + c;
      after[to] = after[to]! - c;
    }
    expect(after.values.every((v) => v == 0), isTrue);
    expect(settle({'A': 0}), isEmpty);
  });

  test('Gruppe ohne Bon: Mitglieder von Hand, dann aus Bons; löschen räumt auf', () {
    final store = BillStore.memory();
    store.addGroup('Urlaub');
    expect(store.groupMembers('Urlaub'), isEmpty);
    store.addGroupMember('Urlaub', ' Mia ');
    store.addGroupMember('Urlaub', 'Mia');
    expect(store.groupMembers('Urlaub'), ['Mia']);
    store.bills.add(paid('h', 900, ['Jo', 'Mia'], group: 'Urlaub'));
    expect(store.groupMembers('Urlaub'), ['Mia', 'Jo']);
    expect(store.isHandMember('Urlaub', 'Jo'), isFalse);
    expect(store.groupBalance('Urlaub'), {'Jo': 450, 'Mia': -450});
    store.removeGroupMember('Urlaub', 'Mia');
    expect(store.groupMembers('Urlaub'), ['Jo', 'Mia']); // Mia stays: she is in a bill
    store.deleteGroup('Urlaub');
    store.addGroup('Urlaub');
    expect(store.groupMembers('Urlaub'), isEmpty);
  });

  testWidgets('Gruppenseite zeigt Personen, Saldo und Ausgleich', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final store = BillStore.memory([paid('Pizza', 3000, ['Anna', 'Ben', 'Ali'])])..onboarded = true;
    store.addGroupMember('WG', 'Dora');
    final q = ScanQueue(store, recognize: (_) => const Stream.empty());
    final ctl = FasanController(settings: FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ctl, home: GroupScreen(name: 'WG', queue: q)));
    await tester.pump(const Duration(milliseconds: 100));
    // header with the person symbol and the count; the members open behind it (Nutzer 08.11. 04:09)
    expect(find.text('Pizza'), findsOneWidget);
    expect(find.text('4'), findsWidgets, reason: 'Personenzahl im Kopf');
    expect(find.text('Dora'), findsNothing, reason: 'erst nach dem Tippen auf das Personensymbol');
    await tester.tap(find.byIcon(Icons.group_outlined).first);
    await tester.pumpAndSettle();
    expect(find.text('Dora'), findsOneWidget);
    expect(find.text('Ohne App'), findsNothing, reason: 'nur Gruppen mit Live-Teilen zeigen den Status');
    expect(find.text('So gleicht ihr aus'), findsOneWidget);
    expect(find.textContaining('Ben zahlt Anna 10,00'), findsOneWidget);
    expect(find.textContaining('Ali zahlt Anna 10,00'), findsOneWidget);
  });
}
