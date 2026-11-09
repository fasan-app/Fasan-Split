// SPDX-License-Identifier: MPL-2.0
// Fasan Split – share the recognition log of a bill (Diagnose nur nach Zustimmung; ohne Namen). MPL-2.0
import 'scope.dart' show StoreScope;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../perf/frame_stats.dart';
import '../platform/web_platform.dart' show webGlInfo;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import 'package:fasan_core/bill.dart';
import 'common.dart';
import '../state/images.dart';

/// Asks first (with an opt-in for the original photo), then shares the log as JSON. People's names are never included.
Future<void> shareRecognitionLog(BuildContext context, Bill bill) async {
  final t = S.of(context);
  var withPhoto = false;
  final hasPhoto = imageExists(bill.originalPath);
  final how = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(t.shareLog),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.logConsent),
          if (hasPhoto)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: withPhoto,
              onChanged: (v) => setState(() => withPhoto = v ?? false),
              title: Text(t.logWithPhoto),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
          // save as a file via the system dialog (Storage Access Framework; file_picker, MIT, no permission needed)
          TextButton(onPressed: () => Navigator.pop(context, 'save'), child: Text(t.saveFile)),
          TextButton(onPressed: () => Navigator.pop(context, 'share'), child: Text(t.share)),
        ],
      ),
    ),
  );
  if (how == null) return;
  final storeWrite = context.mounted ? StoreScope.read(context).lastWrite : null;
  final storeHistory = context.mounted ? StoreScope.read(context).historyChanges(bill) : const <Map<String, Object?>>[];
  Map<String, Object?> log = {};
  final logBytes = bill.logPath == null ? null : await readImage(bill.logPath!);
  if (logBytes != null) {
    try {
      log = (jsonDecode(utf8.decode(logBytes)) as Map).cast<String, Object?>();
    } catch (_) {}
  }
  final doc = {
    'app': 'app.fasan.split',
    'geraet': kIsWeb ? {'os': 'web'} : {'os': Platform.operatingSystem, 'version': Platform.operatingSystemVersion, 'kerne': Platform.numberOfProcessors},
    // what the screen can draw (Nutzer 02.11.: „Glas ist kein Glas“): the result of the glass probe and whether the grain
    // shader and its template loaded. Lets the next version be built from facts, not guesses.
    'darstellung': {
      'glas': {'stufe': FasanGlassShader.tier.value.name, 'grund': FasanGlassShader.reason, 'pixel': FasanGlassShader.probePixels, 'kopfueber': FasanGlassShader.flipY, 'shaderFilter': ui.ImageFilter.isShaderFilterSupported},
      'ton': {'modus': FasanSound.mode, 'gespielt': FasanSound.plays, 'fehler': FasanSound.lastError, 'ausfaelle': FasanSound.failures},
      'korn': {'programm': FasanFilm.grainProgram != null, 'vorlage': FasanFilm.grainTemplate != null},
    },
    'erkennung': log,
    'bildzeiten': FrameStats.summary(),
    'grafik': webGlInfo(), // browser: webgl2 / webgl / none (none = drawn on the processor, very slow)
    'speichern': storeWrite == null ? null : {'ms': storeWrite.ms, 'zeichen': storeWrite.chars, 'rechnungen': storeWrite.bills},
    'rechnung': {
      'summe': bill.total,
      'geprueft': bill.checked,
      'posten': [for (final p in bill.its) {'t': p.name, 'klar': p.food?.name, 'b': p.amount, 'menge': p.qty, 'sicher': p.sure, 'zuteilung': p.fill.name, 'personen': p.shares.length, 'proStueck': p.perUnit,
        'anteile': {for (final e in p.shares.entries) '${e.key}': e.value}, if (p.fixed.isNotEmpty) 'fest': p.fixed, 'einzel': p.unit,
        'erkannt': p.rec, 'korrigiert': p.rec != null && (p.rec!['t'] != p.name || p.rec!['menge'] != p.qty || p.rec!['b'] != p.amount)}],
      'personen': bill.ps.length,
      'verlauf': storeHistory,
    },
  };
  final json = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(doc)));
  final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-');
  if (how == 'save') {
    final uri = await FilePicker.saveFile(fileName: 'fasan-split-protokoll-$stamp.json', bytes: json, mimeType: 'application/json');
    if (uri != null && withPhoto && hasPhoto) {
      await FilePicker.saveFile(fileName: 'fasan-split-bon-$stamp.jpg', bytes: (await readImage(bill.originalPath!))!, mimeType: 'image/jpeg');
    }
    if (uri != null && context.mounted) showNote(context, t.savedFile);
    return;
  }
  await SharePlus.instance.share(ShareParams(files: [
    XFile.fromData(json, mimeType: 'application/json', name: 'fasan-split-protokoll-$stamp.json'),
    if (withPhoto && hasPhoto) XFile(bill.originalPath!, mimeType: 'image/jpeg', name: 'fasan-split-bon-$stamp.jpg'),
  ]));
}

/// Saves (system dialog) or shares a JSON report without asking again; used by the performance test (no names, no bills in it).
Future<void> exportDocument(BuildContext context, Map<String, Object?> doc, {required String prefix, required bool share}) async {
  final t = S.of(context);
  final json = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(doc)));
  final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-');
  final name = 'fasan-split-$prefix-$stamp.json';
  if (!share) {
    final uri = await FilePicker.saveFile(fileName: name, bytes: json, mimeType: 'application/json');
    if (uri != null && context.mounted) showNote(context, t.savedFile);
    return;
  }
  await SharePlus.instance.share(ShareParams(files: [XFile.fromData(json, mimeType: 'application/json', name: name)]));
}
