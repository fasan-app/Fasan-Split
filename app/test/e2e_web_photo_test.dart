// Fasan Split – phone side of the browser end-to-end test for shared receipt photos (Nutzer 06.11.: in the browser the ⋮ menu
// showed one entry, the Original/Digital switch and the line pictures were missing). Runs only with FASAN_E2E_RELAY (a local
// relay, never public relays) and FASAN_FILE (a real receipt photo, e.g. from the private fasan-diagnose). Recognises the
// photo like the app (billFromScan), shares the bill in a new group, writes the invitation to FASAN_E2E_DIR/link.txt and
// stays online until the browser (tool/e2e/photo.js) wrote photo-done.txt. MPL-2.0
import 'dart:io';
import 'dart:typed_data';

import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/model/scan_bill.dart';
import 'package:fasan_split/recognition/pipeline.dart';
import 'package:fasan_split/recognition_service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ocr_cache.dart';

class _Docs extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _Docs(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

Uint8List _drawn() {
  final im = img.Image(width: 900, height: 1600);
  img.fill(im, color: img.ColorRgb8(250, 250, 248));
  for (var r = 0; r < 12; r++) {
    final y = 120 + r * 100;
    img.fillRect(im, x1: 60, y1: y, x2: 560, y2: y + 40, color: img.ColorRgb8(20, 20, 20));
    img.fillRect(im, x1: 700, y1: y, x2: 840, y2: y + 40, color: img.ColorRgb8(20, 20, 20));
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 85));
}

void main() {
  final env = Platform.environment;
  final relayUrl = env['FASAN_E2E_RELAY'], file = env['FASAN_FILE'];
  final dir = env['FASAN_E2E_DIR'] ?? '/tmp';
  test('Bon mit Foto teilen, Browser bekommt Scan, Original und Ausschnitte (Telefon-Seite)', () async {
    final tmp = await Directory.systemTemp.createTemp('fasan_e2e_photo');
    PathProviderPlatform.instance = _Docs(tmp.path);
    SharedPreferences.setMockInitialValues({});
    // with FASAN_FILE: a real photo recognised like the app does; without (CI): a drawn receipt with item places, no recognition
    final photo = file != null ? File(file).readAsBytesSync() : _drawn();
    ScanResultData? r;
    if (file != null) {
      final ocr = testOcr('assets/models', 2);
      cacheFor(ocr, file);
      final x = await Recognizer(ocr).recognize(photo);
      cacheDone(ocr);
      r = RecognitionService.fromRecognition(x);
    }
    final store = BillStore.memory()..me = 'Chris';
    final a = CollabService(store: store, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => RelayPool([WsRelay(relayUrl!)]));
    await a.init();
    await a.setName('Chris');
    final g = await a.createGroup('Lissabon', relays: [relayUrl!]);
    final b = r != null
        ? await billFromScan(r, photo, id: 'e2e-photo', group: 'Lissabon')
        : (Bill(id: 'e2e-photo', created: DateTime(2026, 11, 6), total: 2400, people: [Person('Chris', 0)], items: [
            BillItem(name: 'Pizza', amount: 1400, boxes: const [NBox(0.06, 0.075, 0.94, 0.1)]),
            BillItem(name: 'Wein', amount: 1000, boxes: const [NBox(0.06, 0.1375, 0.94, 0.1625)]),
          ])
          ..group = 'Lissabon'
          ..imagePath = await BillStore.saveFile('e2e-scan.jpg', photo)
          ..originalPath = await BillStore.saveFile('e2e-orig.jpg', photo));
    b.purpose = 'Foto-Test';
    store.upsert(b);
    File('$dir/items.txt').writeAsStringSync([for (final it in b.its) '${it.name}\t${it.amount}\t${it.snippet != null}'].join('\n'));
    final link = g.invitations!.create(person: 'Angi').link;
    for (var i = 0; i < 60 && (store.bills.single.photoRef == null || store.bills.single.origRef == null); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await g.session.flush();
    File('$dir/link.txt').writeAsStringSync(link);
    File('$dir/phone.txt').writeAsStringSync('photoRef ${store.bills.single.photoRef} origRef ${store.bills.single.origRef}');
    // stay online while the browser joins and fetches (pieces go out after the bill; a refused piece is sent again)
    for (var i = 0; i < 300 && !File('$dir/photo-done.txt').existsSync(); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    a.dispose();
    await tmp.delete(recursive: true);
  }, skip: relayUrl == null ? 'nur mit FASAN_E2E_RELAY' : false, timeout: const Timeout(Duration(minutes: 8)));
}
