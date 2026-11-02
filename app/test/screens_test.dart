// Bildschirmfotos im Handyformat (393 × 873 dp, 2,75 px/dp), hoch und quer, hell und dunkel.
// Nur zum Ansehen, kein Vergleichstest: läuft nur mit FASAN_SCREENS=<Ausgabeordner>, sonst übersprungen (CI).
// Der Bon ist erfunden und wird hier gezeichnet (Regel: keine echten oder bekannten Test-Bons in Repo oder App).
// Aufruf: FASAN_SCREENS=/tmp/screens flutter test test/screens_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fasan_split/main.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/assign.dart';
import 'package:fasan_split/ui/flow.dart';
import 'package:fasan_split/ui/home.dart';
import 'package:fasan_split/ui/onboarding.dart';
import 'package:fasan_split/ui/settings_screen.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:fasan_split/recognition/onnx.dart';
import 'package:fasan_split/recognition/paddle.dart';
import 'package:fasan_split/recognition/pipeline.dart';
import 'package:fasan_split/recognition_service.dart';
import 'package:fasan_split/ui/receipt_view.dart';

const _lines = [
  ('Flammkuchen', '12,50'),
  ('Apfelschorle 0,4', '4,20'),
  ('Weizen 0,5', '5,40'),
  ('Salat Bowl', '11,90'),
  ('2 x Espresso', '5,60'),
  ('  a 2,80', ''),
];

/// Draws a plain receipt (bitmap font, ASCII) and returns its path and the normalised box of every line.
(String, List<NBox>) _receipt(Directory dir) {
  const w = 600, h = 1500, top = 360, step = 64;
  final im = img.Image(width: w, height: h)..clear(img.ColorRgb8(250, 248, 242));
  final ink = img.ColorRgb8(30, 30, 30);
  img.drawString(im, 'GASTHAUS AM FLUSS', font: img.arial24, x: 170, y: 120, color: ink);
  img.drawString(im, 'Tisch 7', font: img.arial24, x: 250, y: 170, color: ink);
  final boxes = <NBox>[];
  for (var i = 0; i < _lines.length; i++) {
    final y = top + i * step;
    img.drawString(im, _lines[i].$1, font: img.arial24, x: 40, y: y, color: ink);
    if (_lines[i].$2.isNotEmpty) img.drawString(im, _lines[i].$2, font: img.arial24, x: 470, y: y, color: ink);
    boxes.add(NBox(30 / w, (y - 12) / h, 570 / w, (y + 36) / h));
  }
  final ys = top + _lines.length * step + 40;
  img.drawString(im, 'SUMME EUR 39,60', font: img.arial24, x: 300, y: ys, color: ink);
  final f = File('${dir.path}/bon.png')..writeAsBytesSync(img.encodePng(im));
  return (f.path, boxes);
}

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

Future<void> _fonts() async {
  // Direkt aus den Dateien (fasan_ui neben diesem Repo, FASAN_UI überschreibt), damit kein Bundle-Fehler stumm bleibt.
  final ui = Platform.environment['FASAN_UI'] ?? '../../fasan_ui';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  await load('packages/fasan_ui/FasanInter', [for (final w in [400, 500, 600, 700]) '$ui/fonts/Inter-$w.ttf']);
  await load('packages/fasan_ui/FasanGeistMono', ['$ui/fonts/GeistMono-Regular.ttf']);
  await load('MaterialIcons', ['${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

/// Real receipt (FASAN_ECHT=Pfad zum JPG aus fasan-diagnose/tests/echt): the real recognition runs once, like on the phone.
Bill? _real;
Bill _realBill(String photo, Directory dir) {
  if (_real != null) return _real!;
  final uv = File('assets/models/uvdoc.onnx');
  final ocr = PaddleOcr(
    OnnxModel.fromBytes(File('assets/models/det.onnx').readAsBytesSync(), threads: 2),
    OnnxModel.fromBytes(File('assets/models/rec-latin.onnx').readAsBytesSync(), threads: 2),
    File('assets/models/dict-latin.txt').readAsStringSync(),
    uvdoc: uv.existsSync() ? OnnxModel.fromBytes(uv.readAsBytesSync(), threads: 2) : null,
  );
  final bytes = File(photo).readAsBytesSync();
  final r = RecognitionService.fromRecognition(Recognizer(ocr).recognize(bytes));
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
    people: [for (final (i, n) in ['Angi', 'Alexis', 'Emmi', 'Bine', 'Achim', 'Chris'].indexed) Person(n, i)],
  );
}

void main() {
  final out = Platform.environment['FASAN_SCREENS'];
  final echt = Platform.environment['FASAN_ECHT'];
  final screens = <String, Widget Function(Bill)>{
    '0-einfuehrung': (_) => const OnboardingScreen(),
    '1-start': (_) => const HomeScreen(),
    '2-summe': (b) => ReviewScreen(bill: b),
    '3-personen': (b) => PeopleScreen(bill: b),
    '4a-fokus': (b) => AssignScreen(bill: b, initialMode: AssignMode.focus),
    '4b-liste': (b) => AssignScreen(bill: b, initialMode: AssignMode.list),
    '4c-bon': (b) => AssignScreen(bill: b, initialMode: AssignMode.receipt),
    '4d-karten': (b) => AssignScreen(bill: b, initialMode: AssignMode.cards),
    '4e-bon-digital': (b) => _ReceiptLayerProbe(bill: b, layer: ReceiptLayer.digital),
    '4f-bon-original': (b) => _ReceiptLayerProbe(bill: b, layer: ReceiptLayer.original),
    '5-bezahlt': (b) => PayScreen(bill: b..payer = 1),
    '6-ergebnis': (b) => ResultScreen(bill: b..payer = 1),
    '7-einstellungen': (_) => const SettingsScreen(),
  };
  for (final dark in [false, true]) {
    for (final land in [false, true]) {
      final tag = '${dark ? 'dunkel' : 'hell'}-${land ? 'quer' : 'hoch'}';
      for (final e in screens.entries) {
        testWidgets('$tag ${e.key}', (tester) async {
          await tester.runAsync(_fonts);
          tester.view.physicalSize = land ? const Size(2400, 1080) : const Size(1080, 2400);
          tester.view.devicePixelRatio = 2.75;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
          addTearDown(tester.platformDispatcher.clearLocalesTestValue);
          final dir = Directory(out!)..createSync(recursive: true);
          final (path, bx) = await tester.runAsync(() async => _receipt(dir)) ?? ('', <NBox>[]);
          Bill bill;
          if (echt != null) {
            bill = (await tester.runAsync(() async => _realBill(echt, dir)))!;
            final n = bill.ps.length;
            for (final (k, it) in bill.its.indexed) {
              it.shares = e.key.startsWith('4a') || k.isOdd ? {} : {k % n: 1, (k + 1) % n: 1};
            }
          } else {
            bill = _bill(path, bx, assigned: !e.key.startsWith('4a'));
          }
          final store = BillStore.memory([_bill(path, bx)..payer = 1])..onboarded = true;
          final ctl = FasanController(
              settings: FasanSettings(reduceMotion: true, themeMode: dark ? FasanThemeMode.dark : FasanThemeMode.light));
          final key = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(key: key, child: SplitApp(store: store, ui: ctl, home: e.value(bill))));
          // Bon-Foto und Shader laden echt asynchron; danach ein paar Bilder ohne Dauer-Animation.
          await tester.runAsync(() async {
            await precacheImage(FileImage(File(bill.imagePath ?? path)), key.currentContext!);
            if (bill.originalPath != null) await precacheImage(FileImage(File(bill.originalPath!)), key.currentContext!);
            await Future<void>.delayed(const Duration(milliseconds: 300));
          });
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1.25);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File('${dir.path}/$tag-${e.key}.png').writeAsBytesSync(png!.buffer.asUint8List());
          });
        }, skip: out == null);
      }
    }
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
