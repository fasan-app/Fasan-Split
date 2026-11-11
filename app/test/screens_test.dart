// SPDX-License-Identifier: MPL-2.0
// Bildschirmfotos im Handyformat (393 × 873 dp, 2,75 px/dp), hoch und quer, hell und dunkel.
// Nur zum Ansehen, kein Vergleichstest: läuft nur mit FASAN_SCREENS=<Ausgabeordner>, sonst übersprungen (CI).
// Der Bon ist erfunden und wird hier gezeichnet (Regel: keine echten oder bekannten Test-Bons in Repo oder App).
// Aufruf: FASAN_SCREENS=/tmp/screens flutter test test/screens_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fasan_split/main.dart';
import 'package:fasan_split/collab/keys.dart' show MemoryVault;
import 'package:fasan_split/collab/nostr.dart' show MemoryRelay, MemoryRelayHub;
import 'package:fasan_split/collab/service.dart' show CollabService;
import 'package:fasan_split/flows/scan_queue.dart';
import 'package:fasan_split/ui/my_balance.dart';
import 'package:fasan_split/ui/history.dart';
import 'package:fasan_split/ui/change_badge.dart';
import 'package:fasan_split/ui/balance_breakdown.dart';
import 'package:fasan_split/collab/bill_changes.dart';
import 'package:fasan_split/collab/bill_sync.dart';
import 'package:fasan_split/collab/group.dart' show BillSnapshot;
import 'package:fasan_split/collab/ledger.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_split/ui/groups.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/perf/perf_governor.dart';
import 'package:fasan_split/state/snippets.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/assign.dart';
import 'package:fasan_split/ui/bill_screen.dart' show askHideBill;
import 'package:fasan_split/ui/flow.dart';
import 'package:fasan_split/ui/home.dart';
import 'package:fasan_split/ui/join_screen.dart';
import 'package:fasan_split/ui/onboarding.dart';
import 'package:fasan_split/ui/settings_screen.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:fasan_split/recognition/onnx.dart';
import 'package:fasan_split/recognition/paddle.dart';
import 'package:fasan_split/recognition/pipeline.dart';
import 'package:fasan_split/recognition/service.dart';
import 'package:fasan_split/ui/receipt_view.dart';
import 'support/synthetic_receipt.dart';
import 'support/fonts.dart';
import 'package:fasan_split/ui/scan_screen.dart';
import 'package:fasan_split/ui/tutorial.dart';


Bill _bill(String path, List<NBox> bx, {bool assigned = true}) {
  final b = Bill(
    id: 'screens',
    created: DateTime(2026, 10, 24, 20, 15),
    purpose: 'Abendessen',
    total: 3960,
    checked: true,
    imagePath: path,
    imageAspect: 600 / 1500,
    people: [Person('Anna', 0), Person('Jo', 1), Person('Mia', 2)],
    items: [
      BillItem(name: 'Flammkuchen', amount: 1250, boxes: [bx[0]]),
      BillItem(name: 'Apfelschorle 0,4', amount: 420, boxes: [bx[1]]),
      BillItem(name: 'Weizen 0,5', amount: 540, boxes: [bx[2]]),
      BillItem(name: 'Salat Bowl', amount: 1190, boxes: [bx[3]], sure: false),
      BillItem(name: 'Espresso', amount: 560, qty: 2, boxes: [bx[4], bx[5]]),
    ],
  );
  if (assigned) {
    b.its[0].shares = {0: 1, 1: 1};
    b.its[1].shares = {2: 1};
    b.its[2].shares = {1: 1};
    b.its[4].shares = {0: 1, 2: 1};
  }
  return b;
}

/// The bill of the browser walk (tool/e2e/screens.js, phone side test/e2e_web_photo_test.dart without FASAN_FILE): same people,
/// items, receipt picture. Key „b…“ screens are compared with the browser's screenshots of the same name.
Bill _walkBill(Directory dir) {
  final im = img.Image(width: 900, height: 1600);
  img.fill(im, color: img.ColorRgb8(250, 250, 248));
  for (var r = 0; r < 12; r++) {
    final y = 120 + r * 100;
    img.fillRect(im, x1: 60, y1: y, x2: 560, y2: y + 40, color: img.ColorRgb8(20, 20, 20));
    img.fillRect(im, x1: 700, y1: y, x2: 840, y2: y + 40, color: img.ColorRgb8(20, 20, 20));
  }
  final f = File('${dir.path}/walk.jpg')..writeAsBytesSync(img.encodeJpg(im, quality: 85));
  final b = Bill(id: 'walk', created: DateTime(2026, 11, 6), total: 2400, people: [Person('Pia', 0), Person('Lena', 1)], payer: 0, items: [
    BillItem(name: 'Pizza', amount: 1400, shares: {0: 1}, boxes: const [NBox(0.06, 0.075, 0.94, 0.1)]),
    BillItem(name: 'Wein', amount: 1000, shares: {1: 1}, boxes: const [NBox(0.06, 0.1375, 0.94, 0.1625)]),
  ])
    ..purpose = 'Foto-Test'
    ..group = 'Beispielstadt'
    ..imagePath = f.path
    ..originalPath = f.path
    ..imageAspect = 900 / 1600;
  return b;
}

/// Real receipt (FASAN_ECHT=Pfad zum JPG aus fasan-diagnose/tests/echt): the real recognition runs once, like on the phone.
Bill? _real;
Bill? _pushBill;
Future<Bill> _realBill(String photo, Directory dir) async {
  if (_real != null) return _real!;
  final uv = File('assets/models/uvdoc.onnx');
  final ocr = PaddleOcr(
    OnnxModel.fromBytes(File('assets/models/det.onnx').readAsBytesSync(), threads: 2),
    OnnxModel.fromBytes(File('assets/models/rec-latin.onnx').readAsBytesSync(), threads: 2),
    File('assets/models/dict-latin.txt').readAsStringSync(),
    uvdoc: uv.existsSync() ? OnnxModel.fromBytes(uv.readAsBytesSync(), threads: 2) : null,
  );
  final bytes = File(photo).readAsBytesSync();
  final r = RecognitionService.fromRecognition(await Recognizer(ocr).recognize(bytes));
  final scan = File('${dir.path}/echt-scan.png')..writeAsBytesSync(r.display);
  final orig = File('${dir.path}/echt-orig.jpg')..writeAsBytesSync(bytes);
  return _real = Bill(
    id: 'echt',
    created: DateTime(2026, 10, 24, 11, 52),
    purpose: r.shop.isEmpty ? r.kind : r.shop,
    total: r.total,
    items: r.items,
    imagePath: scan.path,
    originalPath: orig.path,
    imageAspect: r.width / r.height,
    checked: r.checked && !r.contradiction,
    people: [for (final (i, n) in ['Lena', 'Nora', 'Tilda', 'Rosa', 'Jonas', 'Pia'].indexed) Person(n, i)],
  );
}

void main() {
  final out = Platform.environment['FASAN_SCREENS'];
  final echt = Platform.environment['FASAN_ECHT'];
  final screens = <String, Widget Function(Bill)>{
    '0-einfuehrung': (_) => const OnboardingScreen(),
    '1-start': (_) => const HomeScreen(),
    '2-summe': (b) => ReviewScreen(bill: b),
    '4a-fokus': (b) => AssignScreen(bill: b, initialMode: AssignMode.focus),
    '4b-liste': (b) => AssignScreen(bill: b, initialMode: AssignMode.list),
    '4c-bon': (b) => AssignScreen(bill: b, initialMode: AssignMode.receipt),
    '4d-karten': (b) => AssignScreen(bill: b, initialMode: AssignMode.cards),
    '4e-bon-digital': (b) => _ReceiptLayerProbe(bill: b, layer: ReceiptLayer.digital),
    '4f-bon-original': (b) => _ReceiptLayerProbe(bill: b, layer: ReceiptLayer.original),
    '5-bezahlt': (b) => PayScreen(bill: b..payer = 1),
    '6-ergebnis': (b) => ResultScreen(bill: b..payer = 1),
    '7-einstellungen': (_) => const SettingsScreen(),
    'b01-bon': (b) => ReviewScreen(bill: b),
    'b02-menue': (b) => ReviewScreen(bill: b),
    'b04-posten-blatt': (b) => ReviewScreen(bill: b),
    'b04v-posten-vllt': (b) => ReviewScreen(bill: b),
    'b04w-liste-vllt': (b) => ReviewScreen(bill: b),
    // visibility question (Sichtbarkeit je Rechnung): the dialog over the bill
    'b24-sichtbarkeit': (b) => Builder(builder: (c) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (c.mounted) askHideBill(c, 'Lena, Pia');
          });
          return ReviewScreen(bill: b);
        }),
    'b05-posten-blatt-fest': (b) => ReviewScreen(bill: b),
    // pieces (07.11.): item sheet with the piece counter (Pizza: quantity 2, Pia off, Lena on = one of two pieces); same steps in the browser
    'b20-stueck-posten': (b) => ReviewScreen(bill: b),
    // provisional balance (07.11.): „Mein Stand“ with an unfinished bill in the store (Lena owes Pia 10,00 so far)
    'b21-saldo-vorlaeufig': (_) => Builder(builder: (c) {
          final st = StoreScope.read(c);
          st.bills.removeWhere((x) => x.id == 'prov');
          st.bills.add(Bill(id: 'prov', created: DateTime(2026, 11, 7), total: 4000, people: [Person('Lena', 0), Person('Pia', 1)], items: [
            BillItem(name: 'Pizza', amount: 1400, shares: {0: 1}),
            BillItem(name: 'Wein', amount: 1000, shares: {1: 1}),
            BillItem(name: 'Rest', amount: 1600),
          ])
            ..payer = 1
            ..group = 'Beispielstadt');
          return const MyBalanceScreen();
        }),
    // history (07.11.): what exactly changed in the receipts, and the cost history of my balance
    for (final k in ['b22-verlauf', 'b23-verlauf-kosten'])
      k: (_) => Builder(builder: (c) {
            final co = CollabScope.read(c);
            final t = DateTime.now();
            co.changeLog
              ..clear()
              ..addAll([
                ChangeRecord(at: t.subtract(const Duration(minutes: 4)), group: 'x', billId: 'a', title: 'Strandbar Erfunden', who: 'Hugo', whoKey: 'k1', lines: const [
                  ChangeLine('Sprudel: Menge 2 → 3', 'Sprudel: quantity 2 → 3'),
                  ChangeLine('Sprudel: Betrag 7,00 € → 10,50 €', 'Sprudel: amount 7.00 € → 10.50 €'),
                  ChangeLine('Pia bei „Sprudel“ eingetragen (2 Stück)', 'Pia added to “Sprudel” (2 pcs)'),
                ]),
                ChangeRecord(at: t.subtract(const Duration(hours: 3)), group: 'x', billId: 'b', title: 'Restaurant Beispiel', who: 'Tilda', whoKey: 'k2', lines: const [
                  ChangeLine('Posten „Cola“ entfernt', 'Item “Cola” removed'),
                  ChangeLine('Summe 85,00 € → 82,00 €', 'Total 85.00 € → 82.00 €'),
                ]),
              ]);
            co.ledger.entries
              ..clear()
              ..addAll([
                LedgerEntry(at: t.subtract(const Duration(minutes: 4)), billId: 'a', title: 'Strandbar Erfunden', group: 'Beispielstadt', delta: 700, total: 3350, groupTotal: 2350, whyDe: 'Hugo: Sprudel: Menge 2 → 3', whyEn: 'Hugo: Sprudel: quantity 2 → 3'),
                LedgerEntry(at: t.subtract(const Duration(hours: 3)), billId: 'b', title: 'Restaurant Beispiel', group: 'Beispielstadt', delta: -300, total: 2650, groupTotal: 1650, whyDe: 'Tilda: Posten „Cola“ entfernt', whyEn: 'Tilda: Item “Cola” removed'),
              ]);
            return const HistoryScreen.all();
          }),
    // how the balance comes about (07.11.): my breakdown with a provisional bill, and the group page for everybody
    'b24-saldo-aufstellung': (_) => Builder(builder: (c) {
          final st = StoreScope.read(c);
          st.bills.removeWhere((x) => x.id == 'prov');
          st.bills.add(Bill(id: 'prov', created: DateTime(2026, 11, 7), purpose: 'Kneipe Beispiel', total: 4000, people: [Person('Lena', 0), Person('Pia', 1)], items: [
            BillItem(name: 'Pizza', amount: 1400, shares: {0: 1}),
            BillItem(name: 'Wein', amount: 1000, shares: {1: 1}),
            BillItem(name: 'Rest', amount: 1600),
          ])
            ..payer = 1
            ..group = 'Beispielstadt');
          return const MyBreakdownScreen();
        }),
    // earlier state of a damaged bill (08.11.): the dialog with made-up snapshots of two members
    'b27-frueherer-stand': (_) => Builder(builder: (c) {
          Bill mk(int qty) => Bill(id: 'r', created: DateTime(2026, 11, 8), total: 1920, people: [Person('Pia', 0)], items: [
                BillItem(name: qty == 1 ? 'z Coca cola 23 e' : 'Coca Cola', amount: 960, qty: qty, shares: {0: 1}),
                BillItem(name: qty == 1 ? 'x' : 'Törtchen', amount: 960, qty: qty * 2, shares: {0: 1}),
              ]);
          BillSnapshot snap(String a, DateTime at, int qty) {
            final d = LwwDoc(a);
            BillSync.write(d, mk(qty));
            return BillSnapshot(author: a, at: at, doc: d);
          }
          final now = DateTime.now();
          final list = [snap('pia', now.subtract(const Duration(minutes: 20)), 1), snap('bine', now.subtract(const Duration(hours: 2)), 2)];
          return Scaffold(body: RestoreDialog(bill: mk(2), snapshots: Future.value(list), who: (s) => s.author == 'pia' ? 'Pia' : 'Rosa', onRestore: (_) {}));
        }),
    // changed by others (08.11.): counter on the thumbnail, banner in the bill
    'b28-neu-seit-besuch': (_) => Builder(builder: (c) {
          final co = CollabScope.read(c);
          co.changeLog
            ..clear()
            ..add(ChangeRecord(at: DateTime.now().subtract(const Duration(minutes: 4)), group: 'x', billId: 'nb', title: 'Strandbar Erfunden', who: 'Hugo', whoKey: 'k1', lines: const [
              ChangeLine('Sprudel: Menge 2 → 3', 'Sprudel: quantity 2 → 3'),
              ChangeLine('Pia bei „Sprudel“ eingetragen (2 Stück)', 'Pia added to “Sprudel” (2 pcs)'),
            ]));
          return Scaffold(
            appBar: AppBar(title: const Text('Bon')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              const UnseenChangesBanner(billId: 'nb'),
              const SizedBox(height: 24),
              Row(children: [
                Stack(clipBehavior: Clip.none, children: [Container(width: 34, height: 44, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))), const Positioned(right: -7, top: -7, child: ChangeBadge(id: 'nb', count: 2))]),
                const SizedBox(width: 24),
                Stack(clipBehavior: Clip.none, children: [Container(width: 34, height: 44, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))), const Positioned(right: -7, top: -7, child: ChangeBadge(id: 'nb2', count: 14))]),
                const SizedBox(width: 24),
                Stack(clipBehavior: Clip.none, children: [Container(width: 34, height: 44, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))), const Positioned(right: -7, top: -7, child: ChangeBadge(id: 'nb3', count: 0))]),
              ]),
            ]),
          );
        }),
    'b26-anleitung': (_) => const TutorialScreen(),
    'b25-gruppe-aufstellung': (_) => Builder(builder: (c) {
          final st = StoreScope.read(c);
          st.bills.removeWhere((x) => x.id.startsWith('gb'));
          Bill done(String id, String title, int payer, List<(String, int, int)> items) => Bill(id: id, created: DateTime(2026, 11, 6), purpose: title, total: items.fold<int>(0, (a, i) => a + i.$2), people: [Person('Lena', 0), Person('Pia', 1), Person('Hugo', 2)], items: [
                for (final i in items) BillItem(name: i.$1, amount: i.$2, shares: {i.$3: 1}),
              ])
            ..payer = payer
            ..done = true
            ..group = 'Beispielstadt';
          st.bills.add(done('gb1', 'Strandbar Erfunden', 1, [('Menü', 2400, 0), ('Wasser', 1050, 1), ('Wein', 1895, 2)]));
          st.bills.add(done('gb2', 'Kneipe Beispiel', 0, [('Pizza', 1400, 1), ('Bier', 700, 2)]));
          return const GroupBreakdownScreen(name: 'Beispielstadt');
        }),
    'b01p-bon-gepusht': (b) => const SizedBox(),
    'b07-pruefen': (b) => ReviewScreen(bill: b),
    // the invitation of a browser walk (FASAN_WALK_LINK = link.txt of tool/e2e/screens.js); no link: skipped
    if (Platform.environment['FASAN_WALK_LINK'] != null) 'j01-beitritt': (_) => JoinScreen(prefill: Platform.environment['FASAN_WALK_LINK']),
    'h04-archiv': (_) => const HomeScreen(),
    'h05-papierkorb': (_) => const HomeScreen(),
    'h06-gruppen': (_) => const HomeScreen(),
    // Posten view of the start page: the same tiles as in the bill, with the receipt snippet (09.11.); browser walk step still to add
    'h07b-gruppe-posten': (_) => const HomeScreen(),
    'h13-freunde': (_) => const HomeScreen(),
    // group page with the walk receipt (Beispielstadt, Pia paid, Lena owes 10,00): Personen, settle as paid – whole and a part (06.11.)
    for (final k in ['h07-gruppe-offen', 'h08-personen', 'h08b-bezahlt-frage', 'h08d-teilbetrag', 'h08e-rest-offen'])
      k: (_) => Builder(builder: (c) => GroupScreen(name: 'Beispielstadt', queue: ScanQueue.current ?? ScanQueue(StoreScope.read(c)))),
    // scanning (07.11.): the choice sheet of the plus, the reading page with its progress, the failure page; same steps in the browser (scan walk of screens.js)
    'sc01-neuer-bon': (_) => const HomeScreen(),
    'sc02-liest': (b) => ScanScreen(photo: File(b.imagePath!).readAsBytesSync(), events: StreamController<ScanEvent>().stream),
    'sc03-fehler': (b) => ScanScreen(photo: File(b.imagePath!).readAsBytesSync(), events: Stream.fromIterable([ScanError('Test: nichts gelesen')])),
    'b08-person-lang': (b) => ReviewScreen(bill: b),
    'b10-bon-ansicht': (b) => ReceiptScreen(bill: b),
    'b11-bon-original': (b) => _ReceiptLayerProbe(bill: b, layer: ReceiptLayer.original),
    'b12-bon-digital': (b) => _ReceiptLayerProbe(bill: b, layer: ReceiptLayer.digital),
    'b14e-fertig': (b) => PayScreen(bill: b),
    // account (Nutzer 11.11.): profile with „Abmelden“ and the sign-out question (signed-in account, invented name)
    'b29-profil': (_) => const ProfileScreen(),
    'b30-abmelden-dialog': (_) => const ProfileScreen(),
    'b15b-ergebnis': (b) => ResultScreen(bill: b..done = true),
  };
  // interaction before the picture (same steps as the browser walk)
  final acts = <String, Future<void> Function(WidgetTester)>{
    'b23-verlauf-kosten': (t) async {
      await t.tap(find.widgetWithText(Tab, 'Kosten'));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    },
    'b30-abmelden-dialog': (t) async {
      await t.ensureVisible(find.byKey(const ValueKey('profile-signout')));
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(find.byKey(const ValueKey('profile-signout')), warnIfMissed: false);
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    },
    'b02-menue': (t) async {
      await t.tap(find.byIcon(Icons.more_vert_rounded));
      await t.pump(const Duration(milliseconds: 400));
    },
    'b01p-bon-gepusht': (t) async {
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      final bill = _pushBill!;
      nav.push(MaterialPageRoute<void>(builder: (_) => ReviewScreen(bill: bill)));
      await t.pump(const Duration(milliseconds: 800));
    },
    'h07b-gruppe-posten': (t) async {
      await t.tap(find.text('Posten').first);
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    },
    'h04-archiv': (t) async {
      await t.tap(find.byKey(const ValueKey('view-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text('Archiv'));
      await t.pump(const Duration(milliseconds: 500));
    },
    'h05-papierkorb': (t) async {
      await t.tap(find.byKey(const ValueKey('view-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text('Papierkorb'));
      await t.pump(const Duration(milliseconds: 500));
    },
    'h06-gruppen': (t) async {
      await t.tap(find.text('Abrechnung').last);
      await t.pump(const Duration(milliseconds: 500));
    },
    'h13-freunde': (t) async {
      await t.tap(find.text('Freunde'));
      await t.pump(const Duration(milliseconds: 500));
    },
    'h08-personen': (t) => _openPeople(t),
    'h08b-bezahlt-frage': (t) async {
      await _openPeople(t);
      await t.tap(find.text('Als bezahlt eintragen'));
      await _frames(t);
    },
    'h08d-teilbetrag': (t) async {
      await _openPeople(t);
      await t.tap(find.text('Als bezahlt eintragen'));
      await _frames(t);
      await t.enterText(find.byType(TextField), '4,00');
      await _frames(t, 4);
    },
    'h08e-rest-offen': (t) async {
      await _openPeople(t);
      await t.tap(find.text('Als bezahlt eintragen'));
      await _frames(t);
      await t.enterText(find.byType(TextField), '4,00');
      await _frames(t, 4);
      await t.tap(find.widgetWithText(FilledButton, 'Bezahlt'));
      await _frames(t, 14);
    },
    'sc01-neuer-bon': (t) async {
      await t.tap(find.byIcon(Icons.add_rounded));
      await _frames(t);
    },
    'b07-pruefen': (t) async {
      await t.tap(find.byIcon(Icons.fact_check_outlined));
      await t.pump(const Duration(milliseconds: 500));
    },
    'b08-person-lang': (t) async {
      await t.longPress(find.text('Pia').first);
      await t.pump(const Duration(milliseconds: 600));
    },
    'b04-posten-blatt': (t) async {
      await t.longPress(find.textContaining('Pizza').first);
      await t.pump(const Duration(milliseconds: 600));
    },
    // „vllt“ proposal (0.1.96): the list shows the suggested person faded, the sheet offers Übernehmen / Ablehnen
    'b04v-posten-vllt': (t) async {
      await t.longPress(find.textContaining('Pizza').first);
      await t.pump(const Duration(milliseconds: 600));
    },
    'b20-stueck-posten': (t) async {
      await t.longPress(find.textContaining('Pizza').first);
      await t.pump(const Duration(milliseconds: 600));
      final sheet = find.byType(BottomSheet);
      await t.tap(find.descendant(of: sheet, matching: find.text('Pia')).first);
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.descendant(of: sheet, matching: find.byType(TextField)).last, '2');
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.descendant(of: sheet, matching: find.text('Lena')).first);
      await t.pump(const Duration(milliseconds: 600));
    },
    'b05-posten-blatt-fest': (t) async {
      await t.longPress(find.textContaining('Pizza').first);
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(find.text('Fester Betrag'));
      await t.pump(const Duration(milliseconds: 400));
    },
  };
  for (final dark in [false, true]) {
    for (final land in [false, true]) {
      final tag = '${dark ? 'dunkel' : 'hell'}-${land ? 'quer' : 'hoch'}';
      for (final e in screens.entries) {
        testWidgets('$tag ${e.key}', (tester) async {
          await tester.runAsync(loadTestFonts);
          tester.view.physicalSize = land ? const Size(2400, 1080) : const Size(1080, 2400);
          tester.view.devicePixelRatio = 2.75;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.localesTestValue = [Platform.environment['FASAN_LANG'] == 'en' ? const Locale('en', 'US') : const Locale('de', 'DE')];
          addTearDown(tester.platformDispatcher.clearLocalesTestValue);
          final dir = Directory(out!)..createSync(recursive: true);
          final (path, bx) = await tester.runAsync(() async => syntheticReceipt(dir)) ?? ('', <NBox>[]);
          Bill bill;
          if (e.key.startsWith('b') || e.key.startsWith('h') || e.key.startsWith('j') || e.key.startsWith('sc')) {
            // variants only for the screens that are also walked in the browser with DARK=1 / LAND=1
            if ((dark || land) && !(const ['b01-bon', 'b10-bon-ansicht', 'b15b-ergebnis', 'sc01-neuer-bon', 'sc02-liest'].contains(e.key) || (dark && e.key == 'b04-posten-blatt'))) return;
            bill = _walkBill(dir);
            if (e.key.startsWith('b04v') || e.key.startsWith('b04w')) bill.its.first.maybe = {1: 'pub-lena'}; // Lena is suggested for the first item
            _pushBill = bill;
            await tester.runAsync(() => fillSnippets(bill, File(bill.imagePath!).readAsBytesSync()));
          } else if (echt != null) {
            bill = (await tester.runAsync(() async => _realBill(echt, dir)))!;
            final n = bill.ps.length;
            for (final (k, it) in bill.its.indexed) {
              it.shares = e.key.startsWith('4a') || k.isOdd ? {} : {k % n: 1, (k + 1) % n: 1};
            }
          } else {
            bill = _bill(path, bx, assigned: !e.key.startsWith('4a'));
          }
          // group screens need the walk receipt in the store (done, so it counts in the balance)
          // the browser starts empty: so does the start page of the scan walk
          final store = BillStore.memory([if (e.key != 'sc01-neuer-bon') _bill(path, bx)..payer = 1, if (e.key.startsWith('h07') || e.key.startsWith('h08')) bill..done = true])
            ..onboarded = true
            ..me = 'Lena';
          // the walk screens show the look of the default (PerfMode.light: no blur, no grain, no moving background), like the browser
          var look = FasanSettings(reduceMotion: e.key.startsWith('b01p') ? false : true, themeMode: dark ? FasanThemeMode.dark : FasanThemeMode.light);
          // like main(): glass without grain is the standard look
          if ((e.key.startsWith('b') || e.key.startsWith('h') || e.key.startsWith('j') || e.key.startsWith('sc'))) look = look.copyWith(style: FasanStyle.fullGlass, effects: look.effects.copyWith(grain: 0));
          final ctl = SplitController(settings: look);
          if ((e.key.startsWith('b') || e.key.startsWith('h') || e.key.startsWith('j') || e.key.startsWith('sc'))) ctl.tier = PerfTier.slow;
          final key = GlobalKey();
          CollabService? svc;
          if (e.key.startsWith('b29') || e.key.startsWith('b30')) {
            final made = svc = CollabService(store: store, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(MemoryRelayHub()));
            await tester.runAsync(() async {
              await made.init();
              await made.setName('Lena');
            });
          }
          await tester.pumpWidget(RepaintBoundary(key: key, child: SplitApp(store: store, ui: ctl, collab: svc, home: e.value(bill))));
          // Bon-Foto und Shader laden echt asynchron; danach ein paar Bilder ohne Dauer-Animation.
          await tester.runAsync(() async {
            await precacheImage(FileImage(File(bill.imagePath ?? path)), key.currentContext!);
            if (bill.originalPath != null) await precacheImage(FileImage(File(bill.originalPath!)), key.currentContext!);
            await Future<void>.delayed(const Duration(milliseconds: 300));
          });
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (acts[e.key] != null) await acts[e.key]!(tester);
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: (e.key.startsWith('b') || e.key.startsWith('h') || e.key.startsWith('j') || e.key.startsWith('sc')) ? 2.0 : 1.25);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File('${dir.path}/$tag-${e.key}.png').writeAsBytesSync(png!.buffer.asUint8List());
          });
          if (svc != null) {
            await tester.pumpWidget(const SizedBox());
            svc.dispose();
          }
        }, skip: out == null);
      }
    }
  }
}

/// Opens the members behind the person symbol in the group header (same step as the browser walk).
Future<void> _openPeople(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.group_outlined).first);
  await _frames(t);
}

/// Several frames instead of one jump: section folds and dialogs animate over many frames.
Future<void> _frames(WidgetTester t, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

/// Receipt screen with a given layer preselected (screenshots of „Original“ and „Digital“).
class _ReceiptLayerProbe extends StatefulWidget {
  const _ReceiptLayerProbe({required this.bill, required this.layer});
  final Bill bill;
  final ReceiptLayer layer;
  @override
  State<_ReceiptLayerProbe> createState() => _ReceiptLayerProbeState();
}

class _ReceiptLayerProbeState extends State<_ReceiptLayerProbe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() {}) : null);
  }

  @override
  Widget build(BuildContext context) => ReceiptScreen(bill: widget.bill, initialLayer: widget.layer);
}
