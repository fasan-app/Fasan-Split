// SPDX-License-Identifier: MPL-2.0
// Fasan Split – several photos at once: they are saved, listed as „wartet“ and read one after the other. MPL-2.0
//
// Nutzer 02.11.: Mehrere Bons auf einmal hochladen und nacheinander erkennen (Warteschlange mit Fortschritt).
// The recognition runs in its own isolate and handles one photo at a time; this queue keeps the order, saves every photo
// first (so nothing is lost if the app closes) and turns each result into the bill that was created as a placeholder.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fasan_core/bill.dart';
import 'scan_bill.dart';
import '../recognition/service.dart';
import '../state/scan_live.dart';
import '../state/store.dart';

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
  /// The queue of the start page (HomeScreen); bill screens use it for „Bon neu lesen“.
  static ScanQueue? current;

  /// Bills read again on purpose: what the user set stays (people, payer, group, category, currency, name).
  final Map<String, Bill> _keep = {};

  /// Reads a finished or started bill again from its original photo (Nutzer 04.11.: newer recognition for old bills).
  /// Items and their assignment are replaced; people, payer, group, category, currency and the name stay.
  Future<void> reread(Bill b, Uint8List photo) {
    _keep[b.id] = Bill.fromJson(b.toJson());
    b
      ..done = false
      ..step = 1;
    return retry(b, photo);
  }

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

  /// Name last set by the recognition, per bill id: tells a name the user typed from one the scan filled in.
  final Map<String, String> _autoPurpose = {};

  Future<void> _readOne(Bill placeholder, Uint8List photo) async {
    final done = Completer<void>();
    final live = ScanLive();
    _live = live;
    notifyListeners();
    // Events are handled one after the other, and „done“ is only reported after the last handler has finished: the ScanDone
    // handler is async (it builds the bill), and the stream ending must not let the queue move on – or say „nothing open“ –
    // before the result is in the store (found by the stress test `scan_queue_test.dart`).
    var chain = Future<void>.value();
    Future<void> handle(ScanEvent e) async {
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
            // a name the user typed while the bill is still being read is kept (see ScanDone)
            if (e.shop.isNotEmpty && (cur.purpose.isEmpty || cur.purpose == _autoPurpose[placeholder.id])) {
              cur.purpose = titleCase(e.shop);
              _autoPurpose[placeholder.id] = cur.purpose;
            }
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
            final k = _keep.remove(placeholder.id);
            if (k != null) {
              b.ps
                ..clear()
                ..addAll(k.ps);
              b
                ..payer = k.payer
                ..group = k.group
                ..category = k.category ?? b.category
                ..currency = k.currency
                ..rate = k.rate
                ..rateDate = k.rateDate
                ..order = k.order
                ..refund = k.refund
                ..receiptDate = b.receiptDate ?? k.receiptDate;
              if (k.purpose.isNotEmpty) b.purpose = k.purpose;
            }
            final typed = store.bills.where((x) => x.id == placeholder.id).firstOrNull?.purpose ?? '';
            if (typed.isNotEmpty && typed != _autoPurpose[placeholder.id]) b.purpose = typed; // the user renamed it meanwhile
            _autoPurpose.remove(placeholder.id);
            store.upsert(b);
          } catch (_) {
            _fail(placeholder);
          }
          if (!done.isCompleted) done.complete();
        case ScanError():
          _fail(placeholder);
          if (!done.isCompleted) done.complete();
      }
    }

    late StreamSubscription<ScanEvent> sub;
    sub = _recognize(photo).listen((e) {
      chain = chain.then((_) => handle(e)).catchError((Object _) {
        _fail(placeholder);
        if (!done.isCompleted) done.complete();
      });
    }, onError: (Object _) {
      chain = chain.then((_) {
        _fail(placeholder);
        if (!done.isCompleted) done.complete();
      });
    }, onDone: () {
      // the stream ended: wait for the handlers; if it ended without a result or an error, the bill failed (never „reading“ for ever)
      chain.whenComplete(() {
        if (!done.isCompleted) {
          final cur = store.bills.where((x) => x.id == placeholder.id).firstOrNull;
          if (cur != null && cur.read == BillRead.reading) _fail(placeholder);
          done.complete();
        }
      });
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
