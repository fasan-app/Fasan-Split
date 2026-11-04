// Fasan Split – „Sichern“ in the settings: save everything into one file, put a file back (state/backup.dart).
// Files through file_picker (saveFile / pickFiles, file_picker 13.3.2 API). MPL-2.0
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../state/backup.dart';
import 'common.dart';

extension _T on S {
  String get backupSave => de ? 'Sicherung speichern' : 'Save backup';
  String get backupSaveSub => de ? 'Alle Bons mit Fotos in eine Datei' : 'All receipts with photos in one file';
  String get backupRestore => de ? 'Sicherung einspielen' : 'Restore backup';
  String get backupRestoreSub => de ? 'Fehlende Bons kommen dazu, nichts wird gelöscht' : 'Missing receipts are added, nothing is deleted';
  String get backupWithAccount => de ? 'Konto und geteilte Gruppen mitsichern' : 'Include account and shared groups';
  String get backupSecretHint => de
      ? 'Dann ist die Datei so geheim wie deine 12 Wörter. Gib sie niemandem.'
      : 'Then the file is as secret as your 12 words. Never share it.';
  String get backupFailed => de ? 'Sicherung ging nicht' : 'Backup failed';
  String get backupSaved => de ? 'Sicherung gespeichert.' : 'Backup saved.';
  String get backupBad => de ? 'Das ist keine Sicherung von Fasan Split.' : 'This is not a Fasan Split backup.';
  String backupDone(int a, int s) => de ? '$a Bons eingespielt, $s waren schon da.' : '$a receipts restored, $s were here already.';
  String get backupRestart => de ? ' Konto und Gruppen sind zurück, wenn du die App neu startest.' : ' Account and groups are back after restarting the app.';
}

Future<void> saveBackupFlow(BuildContext context) async {
  final t = S.of(context);
  var withAccount = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(t.backupSave),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: withAccount, onChanged: (v) => set(() => withAccount = v ?? false), title: Text(t.backupWithAccount)),
          if (withAccount) Text(t.backupSecretHint, style: Theme.of(ctx).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.saveFile)),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final Uint8List bytes;
  try {
    bytes = await makeBackup(StoreScope.read(context), collab: withAccount ? CollabScope.read(context) : null);
  } catch (e) {
    // never silent (04.11.: with account nothing happened)
    if (context.mounted) showNote(context, '${t.backupFailed}: $e');
    return;
  }
  if (!context.mounted) return;
  final day = DateTime.now().toIso8601String().substring(0, 10);
  final uri = await FilePicker.saveFile(fileName: 'fasan-split-sicherung-$day.json', bytes: bytes, mimeType: 'application/json');
  if (uri != null && context.mounted) showNote(context, t.backupSaved);
}

Future<void> restoreBackupFlow(BuildContext context) async {
  final t = S.of(context);
  final files = await FilePicker.pickFiles(type: FileType.any);
  if (files.isEmpty || !context.mounted) return;
  final data = await files.first.readAsBytes();
  if (!context.mounted) return;
  try {
    final r = await restoreBackup(StoreScope.read(context), data, collab: CollabScope.read(context));
    if (context.mounted) showNote(context, t.backupDone(r.added, r.skipped) + (r.secret ? t.backupRestart : ''));
  } on FormatException {
    if (context.mounted) showNote(context, t.backupBad);
  }
}

/// The two rows for the settings list.
List<Widget> backupTiles(BuildContext context) {
  final t = S.of(context);
  return [
    ListTile(leading: const Icon(Icons.save_alt_rounded), title: Text(t.backupSave), subtitle: Text(t.backupSaveSub), onTap: () => saveBackupFlow(context)),
    ListTile(leading: const Icon(Icons.settings_backup_restore_rounded), title: Text(t.backupRestore), subtitle: Text(t.backupRestoreSub), onTap: () => restoreBackupFlow(context)),
  ];
}
