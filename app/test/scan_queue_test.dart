// Scan queue: invariants under load. Whenever the queue says „nothing open“, every bill is finished (ok or failed) – never
// „queued“ or „reading“. Random delays, errors, streams that end without a result, photos added while reading. No network, no models.
import 'dart:math';
import 'dart:typed_data';

import 'package:fasan_core/bill.dart';
import 'package:fasan_split/recognition/scan_events.dart';
import 'package:fasan_split/flows/scan_queue.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';

ScanResultData _result(String shop) => ScanResultData(
      items: [BillItem(name: 'Café', amount: 250), BillItem(name: 'Pastel', amount: 120)],
      total: 370,
      checked: true,
      contradiction: false,
      display: Uint8List(0),
      width: 100,
      height: 200,
      shop: shop,
      kind: 'Café',
      advance: 0,
      log: '{}',
      lines: const [],
    );

bool _finished(Bill b) => b.read == BillRead.ok || b.read == BillRead.failed;

/// Fails the test the moment the queue reports „nothing open“ while a bill is not finished.
void _guard(ScanQueue q, BillStore store, List<String> problems) {
  q.addListener(() {
    if (q.open == 0) {
      for (final b in store.bills) {
        if (!_finished(b)) problems.add('open == 0 but ${b.id} is ${b.read}');
      }
    }
  });
}

Future<void> _drain(ScanQueue q) async {
  while (q.open > 0) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  test('Ergebnis liegt vor, bevor die Warteschlange „fertig“ meldet (zwei Fotos, sofort)', () async {
    final store = BillStore.memory();
    var n = 0;
    final q = ScanQueue(store, recognize: (_) async* {
      final shop = ['Café Um', 'Padaria Dois'][n++];
      yield ScanProgress('Bon wird gelesen', 0.5);
      yield ScanDone(_result(shop));
    });
    final problems = <String>[];
    _guard(q, store, problems);
    await q.add([Uint8List(3), Uint8List(3)], group: 'Reise');
    await _drain(q);
    expect(problems, isEmpty);
    expect(store.bills.every((b) => b.read == BillRead.ok), isTrue);
  });

  test('Strom endet ohne Ergebnis: Bon gilt als fehlgeschlagen, nie für immer „liest“', () async {
    final store = BillStore.memory();
    final q = ScanQueue(store, recognize: (_) async* {
      yield ScanProgress('x', 0.1);
    });
    final problems = <String>[];
    _guard(q, store, problems);
    await q.add([Uint8List(3)]);
    await _drain(q);
    expect(problems, isEmpty);
    expect(store.bills.single.read, BillRead.failed);
  });

  test('Strom wirft mittendrin: fehlgeschlagen, der nächste Bon wird trotzdem gelesen', () async {
    final store = BillStore.memory();
    var n = 0;
    final q = ScanQueue(store, recognize: (_) async* {
      if (n++ == 0) {
        yield ScanProgress('x', 0.1);
        throw StateError('kaputt');
      }
      yield ScanDone(_result('Gut'));
    });
    final problems = <String>[];
    _guard(q, store, problems);
    await q.add([Uint8List(3), Uint8List(3)]);
    await _drain(q);
    expect(problems, isEmpty);
    expect(store.bills.map((b) => b.read).toList()..sort(), [BillRead.failed, BillRead.ok]..sort());
  });

  for (final seed in [1, 2, 3, 4, 5]) {
    test('Stresstest: 60 Fotos, Zufall, Fehler, Hinzufügen während des Lesens (Seed $seed)', () async {
      final r = Random(seed);
      final store = BillStore.memory();
      final fate = <int, String>{}; // photo marker → what the fake recognition does
      final q = ScanQueue(store, recognize: (photo) async* {
        final id = photo[0];
        final kind = fate[id]!;
        await Future<void>.delayed(Duration(milliseconds: r.nextInt(4)));
        yield ScanProgress('Bon wird gelesen', 0.3);
        if (r.nextBool()) await Future<void>.delayed(Duration(milliseconds: r.nextInt(3)));
        yield ScanPartial('Shop $id', null, null, 370);
        switch (kind) {
          case 'ok':
            yield ScanDone(_result('Shop $id'));
          case 'error':
            yield ScanError('kaputt');
          case 'throw':
            throw StateError('kaputt');
          case 'silent':
            break; // stream just ends
        }
      });
      final problems = <String>[];
      _guard(q, store, problems);
      var next = 0;
      Future<void> addSome(int count) async {
        final photos = <Uint8List>[];
        for (var i = 0; i < count; i++) {
          final id = next++;
          fate[id % 256] = const ['ok', 'ok', 'ok', 'error', 'throw', 'silent'][r.nextInt(6)];
          photos.add(Uint8List.fromList([id % 256, 1, 2]));
        }
        await q.add(photos, group: 'Reise');
      }

      // 60 photos in bursts, partly while the queue is already reading
      for (var burst = 0; burst < 12; burst++) {
        await addSome(5);
        await Future<void>.delayed(Duration(milliseconds: r.nextInt(6)));
      }
      await _drain(q);
      expect(problems, isEmpty);
      expect(store.bills.length, 60);
      expect(store.bills.map((b) => b.id).toSet().length, 60, reason: 'bill ids are unique');
      expect(store.bills.every(_finished), isTrue);
      expect(q.open, 0);
      for (final b in store.bills.where((b) => b.read == BillRead.ok)) {
        expect(b.its.length, 2);
        expect(b.total, 370);
      }
    });
  }

  test('Löschen während des Lesens und im Wartebereich: kein Absturz, kein Geister-Bon, Rest wird gelesen', () async {
    final r = Random(9);
    final store = BillStore.memory();
    final q = ScanQueue(store, recognize: (photo) async* {
      await Future<void>.delayed(Duration(milliseconds: 2 + r.nextInt(4)));
      yield ScanPartial('Shop ${photo[0]}', null, null, 370);
      await Future<void>.delayed(Duration(milliseconds: r.nextInt(4)));
      yield ScanDone(_result('Shop ${photo[0]}'));
    });
    final problems = <String>[];
    _guard(q, store, problems);
    await q.add([for (var i = 0; i < 20; i++) Uint8List.fromList([i, 1, 2])]);
    final ids = [for (final b in store.bills) b.id];
    final doomed = <String>{};
    for (var i = 0; i < ids.length; i += 3) {
      await Future<void>.delayed(Duration(milliseconds: r.nextInt(5)));
      final b = store.bills.where((x) => x.id == ids[i]).firstOrNull;
      if (b == null) continue;
      q.forget(b.id);
      store.remove(b);
      doomed.add(b.id);
    }
    await _drain(q);
    expect(problems, isEmpty);
    for (final id in doomed) {
      expect(store.bills.any((b) => b.id == id), isFalse, reason: 'deleted bill $id must not come back');
    }
    expect(store.bills.every(_finished), isTrue);
    expect(store.bills.length, ids.length - doomed.length);
  });

  test('Stresstest: 150 weitere Seeds, kürzere Läufe', () async {
    for (var seed = 100; seed < 250; seed++) {
      final r = Random(seed);
      final store = BillStore.memory();
      final q = ScanQueue(store, recognize: (photo) async* {
        if (r.nextInt(3) == 0) await Future<void>.delayed(Duration(milliseconds: r.nextInt(2)));
        yield ScanProgress('x', 0.2);
        final k = r.nextInt(6);
        if (k == 0) yield ScanError('kaputt');
        if (k == 1) throw StateError('kaputt');
        if (k >= 3) yield ScanDone(_result('S'));
      });
      final problems = <String>[];
      _guard(q, store, problems);
      final n = 3 + r.nextInt(8);
      await q.add([for (var i = 0; i < n; i++) Uint8List.fromList([i, 1, 2])]);
      if (r.nextBool()) await q.add([Uint8List.fromList([99, 1, 2])]);
      await _drain(q);
      expect(problems, isEmpty, reason: 'seed $seed');
      expect(store.bills.every(_finished), isTrue, reason: 'seed $seed');
    }
  });
}
