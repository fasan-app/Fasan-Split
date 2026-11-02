// Fasan Split – several photos at once: they are saved, listed as „wartet“ and read one after the other. MPL-2.0
//
// Nutzer 02.11.: Mehrere Bons auf einmal hochladen und nacheinander erkennen (Warteschlange mit Fortschritt).
// The recognition runs in its own isolate and handles one photo at a time; this queue keeps the order, saves every photo
// first (so nothing is lost if the app closes) and turns each result into the bill that was created as a placeholder.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/bill.dart';
import '../model/scan_bill.dart';
import '../recognition_service.dart';
import 'scan_live.dart';
import 'store.dart';

class ScanQueue extends ChangeNotifier {
  ScanQueue(this.store, {Stream<ScanEvent> Function(Uint8List photo)? recognize}) : _recognize = recognize ?? RecognitionService.instance.recognize;

  final BillStore store;
  final Stream<ScanEvent> Function(Uint8List photo) _recognize;

  final List<(String id, Uint8List photo)> _waiting = [];
  bool _running = false;

  /// Preview, boxes and straightening of the bill that is being read now: the list tile plays the scan animation with it.
  ScanLive? _live;
  ScanLive? liveFor(String id) => id == currentId ? _live : null;

  /// Progress 0–1 and stage text of the bill that is being read now (not saved).
  String? currentId;
  double progress = 0;
  String stage = '';

  /// Number of photos that are waiting or being read.
  int get open => _waiting.length + (currentId == null ? 0 : 1);

  /// Adds photos; each one becomes a bill with the state „wartet“ at once.
  Future<void> add(List<Uint8List> photos, {String? group}) async {
    for (final p in photos) {
      final id = '${DateTime.now().microsecondsSinceEpoch}${_waiting.length}';
      final orig = await BillStore.saveFile('$id.orig.jpg', p);
      store.upsert(Bill(id: id, created: DateTime.now(), originalPath: orig, read: BillRead.queued, group: group, items: []));
      _waiting.add((id, p));
    }
    notifyListeners();
    unawaited(_run());
  }

  /// Reads a failed or interrupted bill again from its saved photo.
  Future<void> retry(Bill b, Uint8List photo) async {
    b.read = BillRead.queued;
    store.upsert(b);
    _waiting.add((b.id, photo));
    notifyListeners();
    unawaited(_run());
  }

  /// Takes a waiting bill out of the queue (it is deleted by the caller).
  void forget(String id) {
    _waiting.removeWhere((w) => w.$1 == id);
    notifyListeners();
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (_waiting.isNotEmpty) {
        final (id, photo) = _waiting.removeAt(0);
        final b = store.bills.where((x) => x.id == id).firstOrNull;
        if (b == null) continue; // deleted while waiting
        currentId = id;
        progress = 0;
        stage = '';
        b.read = BillRead.reading;
        store.upsert(b);
        notifyListeners();
        await _readOne(b, photo);
        currentId = null;
        notifyListeners();
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _readOne(Bill placeholder, Uint8List photo) async {
    final done = Completer<void>();
    final live = ScanLive();
    _live = live;
    notifyListeners();
    late StreamSubscription<ScanEvent> sub;
    sub = _recognize(photo).listen((e) async {
      switch (e) {
        case ScanProgress():
          stage = e.stage;
          progress = e.progress;
          notifyListeners();
        case ScanPreview() || ScanWarp():
          live.onEvent(e);
          notifyListeners();
        case ScanPartial():
          // shop, date and total are known after the first pass: the tile shows them while the rest is still reading
          final cur = store.bills.where((x) => x.id == placeholder.id).firstOrNull;
          if (cur != null && cur.read == BillRead.reading) {
            if (e.shop.isNotEmpty) cur.purpose = titleCase(e.shop);
            cur.receiptDate = DateTime.tryParse(e.dateIso ?? '') ?? cur.receiptDate;
            cur.placeAddress = e.address ?? cur.placeAddress;
            cur.total = e.total ?? cur.total;
            store.upsert(cur);
          }
        case ScanDone():
          try {
            // deleted while it was being read: nothing to fill in
            if (store.bills.every((x) => x.id != placeholder.id)) {
              if (!done.isCompleted) done.complete();
              return;
            }
            final b = await billFromScan(e.result, photo, id: placeholder.id, group: placeholder.group, created: placeholder.created, saveOriginal: false);
            b.originalPath = placeholder.originalPath;
            store.upsert(b);
          } catch (_) {
            _fail(placeholder);
          }
          if (!done.isCompleted) done.complete();
        case ScanError():
          _fail(placeholder);
          if (!done.isCompleted) done.complete();
      }
    }, onError: (_) {
      _fail(placeholder);
      if (!done.isCompleted) done.complete();
    }, onDone: () {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    await sub.cancel();
  }

  void _fail(Bill b) {
    final cur = store.bills.where((x) => x.id == b.id).firstOrNull;
    if (cur == null) return;
    cur.read = BillRead.failed;
    store.upsert(cur);
  }
}
