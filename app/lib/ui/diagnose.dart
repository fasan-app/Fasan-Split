// Fasan Split – share the recognition log of a bill (Diagnose nur nach Zustimmung; ohne Namen). MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import '../model/bill.dart';

/// Asks first (with an opt-in for the original photo), then shares the log as JSON. People's names are never included.
Future<void> shareRecognitionLog(BuildContext context, Bill bill) async {
  final t = S.of(context);
  var withPhoto = false;
  final hasPhoto = bill.originalPath != null && File(bill.originalPath!).existsSync();
  final ok = await showDialog<bool>(
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t.share)),
        ],
      ),
    ),
  );
  if (ok != true) return;
  Map<String, Object?> log = {};
  if (bill.logPath != null && File(bill.logPath!).existsSync()) {
    try {
      log = (jsonDecode(File(bill.logPath!).readAsStringSync()) as Map).cast<String, Object?>();
    } catch (_) {}
  }
  final doc = {
    'app': 'app.fasan.split',
    'geraet': {'os': Platform.operatingSystem, 'version': Platform.operatingSystemVersion, 'kerne': Platform.numberOfProcessors},
    'erkennung': log,
    'rechnung': {
      'summe': bill.total,
      'geprueft': bill.checked,
      'posten': [for (final p in bill.its) {'t': p.name, 'klar': p.food?.name, 'b': p.amount, 'menge': p.qty, 'sicher': p.sure}],
    },
  };
  await SharePlus.instance.share(ShareParams(files: [
    XFile.fromData(Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(doc))), mimeType: 'application/json', name: 'fasan-split-protokoll.json'),
    if (withPhoto && hasPhoto) XFile(bill.originalPath!, mimeType: 'image/jpeg', name: 'fasan-split-bon.jpg'),
  ]));
}
