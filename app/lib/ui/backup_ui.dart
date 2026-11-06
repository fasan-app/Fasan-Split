// Fasan Split – „Sichern“ in the settings: save everything into one file, put a file back (state/backup.dart).
// Files through file_picker (saveFile / pickFiles, file_picker 13.3.2 API). MPL-2.0
import '../l10n/tr.dart' show trLang;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import 'scope.dart';
import '../flows/backup.dart';
import 'collab_ui.dart' show askText;
import 'common.dart';

extension _T on S {
  String get backupSave => trLang(de ? 'de' : 'en', 'backup_ui.saveBackup');
  String get backupSaveSub => trLang(de ? 'de' : 'en', 'backup_ui.allReceiptsWithPhotos');
  String get backupRestore => trLang(de ? 'de' : 'en', 'backup_ui.restoreBackup');
  String get backupRestoreSub => trLang(de ? 'de' : 'en', 'backup_ui.missingReceiptsAreAdded');
  String get backupWithAccount => trLang(de ? 'de' : 'en', 'backup_ui.includeAccountAndShared');
  String get backupSecretHint => trLang(de ? 'de' : 'en', 'backup_ui.backupSecretHint');
  String get backupFailed => trLang(de ? 'de' : 'en', 'backup_ui.backupFailed');
  String get backupPassword => trLang(de ? 'de' : 'en', 'backup_ui.passwordOptional');
  String get backupPasswordHint => trLang(de ? 'de' : 'en', 'backup_ui.backupPasswordHint');
  String get backupShare => trLang(de ? 'de' : 'en', 'backup_ui.send');
  String get backupWrongPassword => trLang(de ? 'de' : 'en', 'backup_ui.wrongPassword');
  String get backupSaved => trLang(de ? 'de' : 'en', 'backup_ui.backupSaved');
  String get backupBad => trLang(de ? 'de' : 'en', 'backup_ui.thisIsNotA');
  String backupDone(int a, int s) => trLang(de ? 'de' : 'en', 'backup_ui.receiptsRestoredWereHere', [a, s]);
  String get backupRestart => trLang(de ? 'de' : 'en', 'backup_ui.accountAndGroupsAre');
}

Future<void> saveBackupFlow(BuildContext context) async {
  final t = S.of(context);
  var withAccount = true;
  final pw = TextEditingController();
  // 'save' = file on the device, 'share' = send it somewhere (e.g. mail to myself), null = cancel
  final how = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(t.backupSave),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: withAccount, onChanged: (v) => set(() => withAccount = v ?? false), title: Text(t.backupWithAccount)),
          if (withAccount) Text(t.backupSecretHint, style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: FasanSpace.s),
          // optional password (NIP-49-like, state/backup.dart): then the file may go by mail or into a cloud folder
          TextField(controller: pw, obscureText: true, decoration: InputDecoration(labelText: t.backupPassword, helperText: t.backupPasswordHint, helperMaxLines: 3)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, 'share'), child: Text(t.backupShare)),
          TextButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(t.saveFile)),
        ],
      ),
    ),
  );
  final password = pw.text;
  pw.dispose();
  if (how == null || !context.mounted) return;
  Uint8List bytes;
  try {
    bytes = await makeBackup(StoreScope.read(context), collab: withAccount ? CollabScope.read(context) : null);
    if (password.isNotEmpty) bytes = await lockBackup(bytes, password);
  } catch (e) {
    // never silent (04.11.: with account nothing happened)
    if (context.mounted) showNote(context, '${t.backupFailed}: $e');
    return;
  }
  if (!context.mounted) return;
  final day = DateTime.now().toIso8601String().substring(0, 10);
  final name = 'fasan-split-sicherung-$day${password.isNotEmpty ? '-passwort' : ''}.json';
  if (how == 'share') {
    await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, mimeType: 'application/json', name: name)], subject: name));
    if (context.mounted) StoreScope.read(context).backupDone();
    return;
  }
  final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: 'application/json');
  if (uri != null && context.mounted) {
    StoreScope.read(context).backupDone();
    showNote(context, t.backupSaved);
  }
}

Future<void> restoreBackupFlow(BuildContext context) async {
  final t = S.of(context);
  final files = await FilePicker.pickFiles(type: FileType.any);
  if (files.isEmpty || !context.mounted) return;
  var data = await files.first.readAsBytes();
  if (!context.mounted) return;
  if (isLockedBackup(data)) {
    final p = await askText(context, t.backupPassword, t.backupPassword);
    if (p == null || !context.mounted) return;
    try {
      data = await unlockBackup(data, p);
    } on FormatException {
      if (context.mounted) showNote(context, t.backupWrongPassword);
      return;
    }
    if (!context.mounted) return;
  }
  try {
    final r = await restoreBackup(StoreScope.read(context), data, collab: CollabScope.read(context));
    if (context.mounted) showNote(context, t.backupDone(r.added, r.skipped) + (r.secret ? t.backupRestart : ''));
  } on FormatException {
    if (context.mounted) showNote(context, t.backupBad);
  }
}

/// Banner on the start page when a backup is due (BillStore.backupDue).
class BackupReminder extends StatelessWidget {
  const BackupReminder({super.key});

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), store = StoreScope.of(context);
    final last = store.lastBackup;
    return Material(
      color: l.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(l.radius * 0.6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FasanSpace.m, FasanSpace.s, FasanSpace.xs, FasanSpace.s),
        child: Row(children: [
          Icon(Icons.save_alt_rounded, color: l.accent),
          const SizedBox(width: FasanSpace.m),
          Expanded(
            child: Text(
              last == null
                  ? (trLang(t.de ? 'de' : 'en', 'backup_ui.noBackupYetSave'))
                  : (trLang(t.de ? 'de' : 'en', 'backup_ui.changesSinceTheLast', [store.changesSinceBackup])),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TextButton(onPressed: () => saveBackupFlow(context), child: Text(trLang(t.de ? 'de' : 'en', 'backup_ui.backUp'))),
          IconButton(tooltip: trLang(t.de ? 'de' : 'en', 'backup_ui.later'), onPressed: store.snoozeBackupHint, icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
      ),
    );
  }
}

/// iPhone in Safari: add to the home screen, else Safari may delete the data after 7 days without a visit.
class HomeScreenHint extends StatelessWidget {
  const HomeScreenHint({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context);
    return Material(
      color: l.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(l.radius * 0.6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FasanSpace.m, FasanSpace.s, FasanSpace.xs, FasanSpace.s),
        child: Row(children: [
          Icon(Icons.add_to_home_screen_rounded, color: l.accent),
          const SizedBox(width: FasanSpace.m),
          Expanded(
            child: Text(
              t.de
                  ? 'Tipp: Teilen → „Zum Home-Bildschirm“. Sonst löscht Safari deine Daten, wenn du 7 Tage nicht hier warst.'
                  : 'Tip: Share → “Add to Home Screen”. Otherwise Safari deletes your data after 7 days without a visit.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(tooltip: t.close, onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
      ),
    );
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
