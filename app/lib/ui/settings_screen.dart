// Fasan Split – settings (docs/recherche/2026-11-02-einstellungen.md): groups with headings, at most two levels,
// every entry explains itself, defaults fit most people; only what works today is shown. MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import '../main.dart';
import 'common.dart';
import 'diagnose.dart';
import 'onboarding.dart';
import 'update_ui.dart';
import '../update.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<bool> _confirm(BuildContext context, String title, String text, String action) async {
    final t = S.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(text),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _editMe(BuildContext context) async {
    final t = S.of(context);
    final store = StoreScope.read(context);
    final c = TextEditingController(text: store.me);
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.meTitle),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: t.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, c.text), child: Text(t.saveClose)),
        ],
      ),
    );
    if (v != null) store.me = v;
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final store = StoreScope.of(context);
    final l = FasanLook.of(context);
    final withLog = [for (final b in store.bills) if (b.logPath != null) b]..sort((a, b) => b.updated.compareTo(a.updated));
    Widget head(String s) => Padding(padding: const EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.l, FasanSpace.l, FasanSpace.xs), child: FasanLabel(s));
    return Scaffold(
      appBar: AppBar(title: Text(t.settings)),
      body: ListView(padding: EdgeInsets.only(bottom: FasanSpace.xxl + MediaQuery.paddingOf(context).bottom), children: [
        head(t.setBill),
        FasanSwitchTile(
          padded: true,
          secondary: const Icon(Icons.translate_rounded),
          title: Text(t.setPlainNames),
          subtitle: Text(t.setPlainNamesSub),
          value: store.plainNames,
          onChanged: (v) => store.plainNames = v,
        ),
        ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(t.setReceiptLayer),
          subtitle: Text(store.receiptLayer == 'original' ? t.layerOriginal : t.layerScan),
          trailing: SizedBox(
            width: 170,
            child: FasanSegmented<String>(
              values: const ['scan', 'original'],
              selected: store.receiptLayer,
              label: (v) => v == 'original' ? t.layerOriginal : t.layerScan,
              onChanged: (v) => store.receiptLayer = v,
            ),
          ),
        ),
        head(t.setPeople),
        ListTile(
          leading: const Icon(Icons.person_outline_rounded),
          title: Text(t.meTitle),
          subtitle: Text(store.me.isEmpty ? t.meUnset : store.me),
          onTap: () => _editMe(context),
        ),
        ExpansionTile(
          leading: const Icon(Icons.people_outline_rounded),
          title: Text(t.setRemembered),
          subtitle: Text(t.setRememberedSub(store.recentNames.length)),
          children: [
            for (final n in store.recentNames)
              ListTile(
                dense: false,
                title: Text(n),
                trailing: IconButton(tooltip: t.forget, icon: const Icon(Icons.close_rounded), onPressed: () => store.forget(n)),
              ),
          ],
        ),
        head(t.setLook),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(t.appearance),
          subtitle: Text(t.de ? 'Stil, Akzent, Schrift, Filmeffekte, Bewegung, Akku, Haptik, große Bedienung' : 'Style, accent, font, film effects, motion, battery, haptics, large controls'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FasanAppearancePage())),
        ),
        ListTile(
          leading: const Icon(Icons.grid_view_outlined),
          title: Text(t.de ? 'Alle Stile vergleichen' : 'Compare all styles'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FasanGalleryPage())),
        ),
        ListTile(
          leading: const Icon(Icons.school_outlined),
          title: Text(t.setIntro),
          subtitle: Text(t.setIntroSub),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.skip_next_rounded),
          title: Text(t.setAutoNext),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: FasanSpace.s),
            child: FasanSegmented<int>(values: const [0, 1, 2], selected: store.autoNext, label: t.autoNextLabel, onChanged: (v) => store.autoNext = v),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.lightbulb_outline_rounded),
          title: Text(t.setHints),
          onTap: () {
            store.resetHints();
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.setHintsDone)));
          },
        ),
        head(t.setData),
        ListTile(
          leading: const Icon(Icons.auto_delete_outlined),
          title: Text(t.setTrash),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: FasanSpace.s),
            child: FasanSegmented<int>(values: const [7, 30, 0], selected: store.trashDays, label: t.trashAfter, onChanged: (v) {
              store.trashDays = v;
              store.purgeTrash();
            }),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline_rounded),
          title: Text(t.setLocal),
          subtitle: Text(t.setLocalSub),
        ),
        ListTile(
          leading: const Icon(Icons.ios_share_rounded),
          title: Text(t.setExport),
          subtitle: Text(t.setExportSub),
          onTap: () => SharePlus.instance.share(ShareParams(files: [
            XFile.fromData(Uint8List.fromList(utf8.encode(store.exportJson())), mimeType: 'application/json', name: 'fasan-split-export.json'),
          ])),
        ),
        ListTile(
          leading: Icon(Icons.hide_image_outlined, color: Theme.of(context).colorScheme.error),
          title: Text(t.setDeletePhotos),
          subtitle: Text(t.setDeletePhotosSub),
          onTap: () async {
            if (await _confirm(context, t.setDeletePhotos, t.setDeletePhotosSub, t.delete) && context.mounted) {
              final n = StoreScope.read(context).removePhotos();
              showNote(context, t.photosDeleted(n));
            }
          },
        ),
        ListTile(
          leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
          title: Text(t.setDeleteAll),
          subtitle: Text(t.setDeleteAllSub(store.bills.length)),
          onTap: () async {
            if (await _confirm(context, t.setDeleteAll, t.setDeleteAllSub(store.bills.length), t.delete) && context.mounted) {
              StoreScope.read(context).removeAll();
            }
          },
        ),
        head(t.setDiagnose),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text(t.shareLog),
          subtitle: Text(withLog.isEmpty ? t.noLogYet : t.setLogSub(withLog.first.purpose.isEmpty ? t.appName : withLog.first.purpose)),
          enabled: withLog.isNotEmpty,
          onTap: withLog.isEmpty ? null : () => shareRecognitionLog(context, withLog.first),
        ),
        head(t.setUpdates),
        FutureBuilder<String>(
          future: Updates.currentVersion(),
          builder: (context, v) => ListTile(
            leading: const Icon(Icons.system_update_rounded),
            title: Text(t.checkNow),
            subtitle: Text(t.version(v.data ?? '…')),
            onTap: () async {
              final u = await Updates.latest();
              final cur = await Updates.currentRun();
              if (!context.mounted) return;
              if (u == null) {
                showNote(context, t.noConnection);
              } else if (cur != null && u.run <= cur) {
                showNote(context, t.upToDate);
              } else {
                showUpdateSheet(context, u);
              }
            },
          ),
        ),
        FasanSwitchTile(
          padded: true,
          secondary: const Icon(Icons.update_rounded),
          title: Text(t.autoUpdate),
          subtitle: Text(t.autoUpdateSub),
          value: store.autoUpdate,
          onChanged: (v) => store.autoUpdate = v,
        ),
        head(t.about),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Fasan Split'),
          subtitle: Text(t.de
              ? 'Frei (MPL-2.0), offline, ohne Konto, ohne Telemetrie. Texterkennung: PaddleOCR (Apache-2.0), UVDoc (MIT), ONNX Runtime (MIT).'
              : 'Free (MPL-2.0), offline, no account, no telemetry. Text recognition: PaddleOCR (Apache-2.0), UVDoc (MIT), ONNX Runtime (MIT).'),
          onTap: () => showLicensePage(context: context, applicationName: 'Fasan Split', applicationLegalese: 'MPL-2.0 · fasan-app'),
        ),
        Padding(
          padding: const EdgeInsets.all(FasanSpace.l),
          child: Text(t.setFewNote, style: Theme.of(context).textTheme.bodySmall!.copyWith(color: l.textMuted)),
        ),
      ]),
    );
  }
}
