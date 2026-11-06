// Fasan Split – receipt photos for the whole group (Beschluss 06.11.; Nutzer 06.11.: in the browser the ⋮ menu showed one
// entry, the Original/Digital switch and the line pictures were missing – the photo never left the phone that scanned).
// Pieces ≤ 40 KB, encrypted with the group key, checked by hash; line pictures cut on the receiving device. Test relay only.
// MPL-2.0
import 'dart:io';
import 'dart:typed_data';

import 'package:fasan_split/collab/bill_sync.dart';
import 'package:fasan_split/collab/crypto.dart';
import 'package:fasan_split/collab/group.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/photo_sync.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/state/images.dart';
import 'package:fasan_split/state/snippets.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Docs extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _Docs(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// A receipt-like picture: white paper with dark text bars, [rows] lines.
Uint8List receipt({int w = 900, int h = 1600, int rows = 12, bool noisy = false}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(250, 250, 248));
  for (var r = 0; r < rows; r++) {
    final y = 120 + r * 100;
    img.fillRect(im, x1: 60, y1: y, x2: 560, y2: y + 40, color: img.ColorRgb8(20, 20, 20));
    img.fillRect(im, x1: 700, y1: y, x2: 840, y2: y + 40, color: img.ColorRgb8(20, 20, 20));
  }
  if (noisy) {
    // grain so the JPEG does not shrink to nothing (more pieces)
    for (var i = 0; i < w * h ~/ 3; i++) {
      final x = (i * 7919) % w, y = (i * 104729) % h, v = (i * 31) % 255;
      im.setPixelRgb(x, y, v, 255 - v, (v * 3) % 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 85));
}

GroupSecret secret() => GroupSecret(key: randomBytes(32), adminPub: KeyPair.generate().pub, name: 'Lisboa 26', relays: const ['memory']);

Future<void> settle([int ms = 600]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('Stücke ≤ 40 KB, verschlüsselt, zurück zusammengesetzt und geprüft', () async {
    final s = secret(), me = KeyPair.generate();
    final photo = receipt(noisy: true);
    final ref = PhotoSync.refOf(photo);
    expect(ref.pieces, greaterThan(1), reason: 'Test braucht mehrere Stücke');
    final evs = PhotoSync.events(me, s, photo);
    expect(evs.length, ref.pieces);
    for (final e in evs) {
      expect(e.content.length, lessThan(40 * 1024), reason: 'Relay-Grenze (nos.lol lehnt ab 64 KB ab, Ziel ≤ 40 KB)');
      expect(e.content.contains('JFIF'), isFalse);
    }
    final hub = MemoryRelayHub();
    final relay = MemoryRelay(hub);
    // pieces arrive in any order
    for (final e in evs.reversed) {
      await relay.publish(e);
    }
    final got = await PhotoSync.fetch(relay, s, ref, authors: {me.pub}, timeout: const Duration(seconds: 5));
    expect(got, photo);
    // what the relay operator sees: no JPEG bytes in any stored event
    for (final e in hub.stored) {
      expect(e.content.contains('/9j/'), isFalse, reason: 'base64 of a JPEG header must not be visible');
    }
  });

  test('Falscher Schlüssel, fremder Absender oder verändertes Stück: kein Bild', () async {
    final s = secret(), me = KeyPair.generate(), stranger = KeyPair.generate();
    final photo = receipt(noisy: true), ref = PhotoSync.refOf(photo);
    final relay = MemoryRelay(MemoryRelayHub());
    for (final e in PhotoSync.events(me, s, photo)) {
      await relay.publish(e);
    }
    final other = GroupSecret(key: randomBytes(32), adminPub: s.adminPub, name: s.name, relays: s.relays);
    expect(await PhotoSync.fetch(relay, other, ref, timeout: const Duration(seconds: 1)), isNull);
    expect(await PhotoSync.fetch(relay, s, ref, authors: {stranger.pub}, timeout: const Duration(seconds: 1)), isNull);
    // a stranger publishes a different picture under the known hash: the hash check refuses it
    final relay2 = MemoryRelay(MemoryRelayHub());
    final fake = receipt(rows: 3, noisy: true);
    for (final (i, e) in PhotoSync.events(stranger, s, fake).indexed) {
      final d = PhotoSync.dOf(s, ref.hash, i);
      await relay2.publish(NostrEvent.create(stranger, kind: kindData, tags: [['d', d], ['t', PhotoSync.tagOf(s, ref.hash)]], content: e.content));
    }
    expect(await PhotoSync.fetch(relay2, s, ref, timeout: const Duration(seconds: 1)), isNull);
  });

  test('Rechnungsdokument trägt Fotoverweis und Lage der Posten, Ausschnitte entstehen beim Empfänger', () async {
    final photo = receipt();
    final b = Bill(id: 'x', created: DateTime(2026, 11, 6), total: 1000, people: [Person('Chris', 0)], items: [
      BillItem(name: 'Essen', amount: 600, boxes: const [NBox(0.06, 0.075, 0.94, 0.1)]),
      BillItem(name: 'Wein', amount: 400, boxes: const [NBox(0.06, 0.1375, 0.94, 0.1625)]),
    ])
      ..photoRef = PhotoSync.refOf(photo).toJson();
    final doc = LwwDoc('aa');
    BillSync.write(doc, b);
    final r = BillSync.read(doc, id: 'x');
    expect(PhotoRef.fromJson(r.photoRef), PhotoSync.refOf(photo));
    expect(r.its.map((i) => i.boxes.length), [1, 1]);
    expect(r.its.first.boxes.first.y0, closeTo(0.075, 1e-4));
    expect(r.its.every((i) => i.snippet == null), isTrue);
    final aspect = await fillSnippets(r, photo);
    expect(aspect, closeTo(900 / 1600, 1e-3));
    for (final it in r.its) {
      expect(it.snippet, isNotNull);
      final pic = img.decodePng(it.snippet!)!;
      expect(pic.height, lessThanOrEqualTo(56));
      expect(pic.width, greaterThan(pic.height * 5), reason: 'eine Zeile über die ganze Textbreite');
    }
  });

  test('Zwei Telefone: Bon mit Foto teilen – das andere bekommt Scan, Original und Ausschnitte', () async {
    final tmp = await Directory.systemTemp.createTemp('fasan_photo');
    PathProviderPlatform.instance = _Docs(tmp.path);
    SharedPreferences.setMockInitialValues({});
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Chris';
    final a = CollabService(store: storeA, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Chris');
    storeA.addGroup('Lisboa 26');
    final scan = await saveImage('scan_a.jpg', receipt());
    final orig = await saveImage('orig_a.jpg', receipt(w: 1800, h: 3200));
    storeA.upsert(Bill(id: 'b1', created: DateTime(2026, 11, 6), purpose: 'Abendessen', total: 1000, people: [Person('Chris', 0), Person('Angi', 1)], items: [
      BillItem(name: 'Essen', amount: 600, boxes: const [NBox(0.06, 0.075, 0.94, 0.1)], shares: {0: 1}),
      BillItem(name: 'Wein', amount: 400, boxes: const [NBox(0.06, 0.1375, 0.94, 0.1625)], shares: {1: 1}),
    ])
      ..imagePath = scan
      ..originalPath = orig
      ..group = 'Lisboa 26');
    final g = await a.shareLocalGroup('Lisboa 26');
    final link = g.invitations!.create().link;
    for (var i = 0; i < 20 && (storeA.bills.single.photoRef == null || storeA.bills.single.origRef == null); i++) {
      await settle(300);
    }
    expect(storeA.bills.single.photoRef, isNotNull, reason: 'verkleinerter Scan vorbereitet');
    expect(storeA.bills.single.origRef, isNotNull, reason: 'verkleinertes Original vorbereitet');

    final storeB = BillStore.memory()..me = 'Angi';
    final b = CollabService(store: storeB, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    expect(await b.join(link, 'Angi'), isNull);
    for (var i = 0; i < 40 && (storeB.bills.isEmpty || !imageExists(storeB.bills.single.originalPath)); i++) {
      await settle(300);
    }
    final got = storeB.bills.single;
    expect(imageExists(got.imagePath), isTrue, reason: 'Scan beim zweiten Gerät');
    expect(imageExists(got.originalPath), isTrue, reason: 'Original beim zweiten Gerät');
    expect(got.its.every((i) => i.snippet != null), isTrue, reason: 'Ausschnitte unter den Posten');
    expect(got.imageAspect, closeTo(900 / 1600, 0.01));
    final scanB = await readImage(got.imagePath!);
    expect(PhotoSync.hashOf(scanB!), PhotoRef.fromJson(storeA.bills.single.photoRef)!.hash);
    // the original arrives downscaled (Blossom will carry the full resolution)
    final o = img.decodeJpg((await readImage(got.originalPath!))!)!;
    expect(o.height, lessThanOrEqualTo(1200));

    // „Bonfotos löschen“ on the second phone: they do not come back by themselves
    storeB.removePhotos();
    storeA.upsert(storeA.bills.single..purpose = 'Abendessen Belém'); // a change arrives
    await settle(1500);
    expect(storeB.bills.single.purpose, 'Abendessen Belém');
    expect(storeB.bills.single.imagePath, isNull);
    a.dispose();
    b.dispose();
    await tmp.delete(recursive: true);
  });
}
