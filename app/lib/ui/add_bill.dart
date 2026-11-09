// SPDX-License-Identifier: MPL-2.0
// Fasan Split – starting a new bill: camera, gallery/file or by hand. Used by the plus on the overview and by the plus inside a
// group (Nutzer 07.11.: „keinen Plus Button direkt in der Gruppe“); a bill started in a group lands in that group. MPL-2.0
import 'dart:typed_data';

import 'package:fasan_core/bill.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../flows/scan_queue.dart';
import '../l10n.dart';
import '../platform/web_platform.dart';
import 'common.dart';
import 'flow.dart';
import 'scan_screen.dart';

/// One photo from camera or gallery, then the scan page. [group]: the bill is put into this group.
Future<void> pickBillPhoto(BuildContext context, ImageSource src, {String? group}) async {
  final nav = Navigator.of(context);
  XFile? f;
  try {
    // full resolution like the web app (it reads the whole photo); cap at 4000 px against memory spikes
    f = await ImagePicker().pickImage(source: src, maxWidth: photoMaxSide, maxHeight: photoMaxSide, imageQuality: photoQuality);
  } catch (_) {
    f = null;
  }
  if (f == null) return;
  final bytes = await f.readAsBytes();
  if (context.mounted) markBillOrigin(context);
  nav.push(MaterialPageRoute(builder: (_) => ScanScreen(photo: bytes, group: group)));
}

/// Gallery: one or many photos. One photo opens the scan page; several are saved and read one after the other
/// (Nutzer 02.11.: mehrere Bons auf einmal hochladen). Package source: `pickMultiImage` returns an empty list on cancel.
/// [onQueued] tells the caller how many photos went into the queue (it shows the message).
Future<void> pickBillPhotos(BuildContext context, ScanQueue queue, {String? group, void Function(int n)? onQueued}) async {
  final nav = Navigator.of(context);
  List<XFile> files;
  try {
    files = await ImagePicker().pickMultiImage(maxWidth: photoMaxSide, maxHeight: photoMaxSide, imageQuality: photoQuality);
  } catch (_) {
    files = const [];
  }
  if (files.isEmpty) return;
  final bytes = <Uint8List>[for (final f in files) await f.readAsBytes()];
  if (bytes.length == 1) {
    if (context.mounted) markBillOrigin(context);
    nav.push(MaterialPageRoute(builder: (_) => ScanScreen(photo: bytes.first, group: group)));
    return;
  }
  await queue.add(bytes, group: group);
  onQueued?.call(bytes.length);
}

/// A bill without a photo.
void startManualBill(BuildContext context, {String? group}) {
  final b = Bill(id: DateTime.now().microsecondsSinceEpoch.toString(), created: DateTime.now(), items: [], group: group);
  markBillOrigin(context);
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(bill: b)));
}

/// The plus: asks how (Kamera, Galerie/Datei, ohne Bon).
Future<void> addBillSheet(BuildContext context, ScanQueue queue, {String? group, void Function(int n)? onQueued}) async {
  final t = S.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(t.camera), onTap: () => Navigator.pop(ctx, 'camera')),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(t.galleryOrFile), onTap: () => Navigator.pop(ctx, 'gallery')),
        ListTile(leading: const Icon(Icons.edit_note_rounded), title: Text(t.manual), onTap: () => Navigator.pop(ctx, 'manual')),
        const SizedBox(height: FasanSpace.s),
      ]),
    ),
  );
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case 'camera':
      await pickBillPhoto(context, ImageSource.camera, group: group);
    case 'gallery':
      await pickBillPhotos(context, queue, group: group, onQueued: onQueued);
    case 'manual':
      startManualBill(context, group: group);
  }
}
