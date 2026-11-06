// Fasan Split – settings (docs/recherche/2026-11-02-einstellungen.md): groups with headings, at most two levels,
// every entry explains itself, defaults fit most people; only what works today is shown. MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import '../l10n/tr.dart';
import '../l10n_collab.dart';
import 'scope.dart';
import '../perf/perf_governor.dart';
import '../collab/activity.dart';
import '../collab/ws_connect.dart' show proxySupported, proxyReachable;
import 'backup_ui.dart';
import 'currency_ui.dart';
import 'collab_ui.dart';
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
    if (v != null && v.trim().isNotEmpty) {
      store.me = v;
      if (context.mounted) CollabScope.read(context).setName(v); // one name everywhere (04.11.)
    }
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
        // always in both languages, so it can be found when the app is in the wrong one
        head('Sprache · Language'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'system', label: Text('System'), icon: Icon(Icons.smartphone_rounded)),
              ButtonSegment(value: 'de', label: Text('Deutsch')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {store.language},
            showSelectedIcon: false,
            onSelectionChanged: (s) => store.language = s.first,
          ),
        ),
        head(t.setBill),
        FasanSwitchTile(
          padded: true,
          secondary: const Icon(Icons.translate_rounded),
          title: TitleHelp(t.setPlainNames, t.setPlainNamesSub),
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
        FasanSwitchTile(
          padded: true,
          secondary: const Icon(Icons.view_carousel_outlined),
          title: TitleHelp(t.de ? 'Fokus und Karten beim Zuordnen' : 'Focus and cards when assigning', t.de ? 'Zusätzlich zu Bon und Liste.' : 'In addition to receipt and list.'),
          value: store.assignExtraModes,
          onChanged: (v) => store.assignExtraModes = v,
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
        ListTile(
          leading: const Icon(Icons.group_outlined),
          title: Text(t.collabTitle),
          subtitle: Text(t.accountOpen),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
        ),
        head(t.de ? 'Währung' : 'Currency'),
        ...currencyTiles(context),
        head(t.de ? 'Sichern' : 'Backup'),
        ...backupTiles(context),
        // one place for notifications (Nutzer 04.11.: no contradicting settings hidden in sub menus)
        head(t.de ? 'Benachrichtigungen' : 'Notifications'),
        if (deviceNotifier != null) const _DeviceNotifyTile(),
        if (proxySupported) const _TorTile(),
        SwitchListTile(
          secondary: const Icon(Icons.visibility_outlined),
          title: TitleHelp(
            t.de ? 'Online-Status und „gelesen“ teilen' : 'Share online status and “read”',
            t.de
                ? 'An: Deine Gruppen und Freunde sehen, ob du gerade online bist, wann zuletzt, und ob du ihre Nachrichten gelesen hast. Aus: Nichts davon geht hinaus – und du siehst es bei den anderen auch nicht.'
                : 'On: your groups and friends see whether you are online, when you were last, and whether you read their messages. Off: none of it goes out – and you do not see it from others either.',
          ),
          value: CollabScope.of(context).presence,
          onChanged: (v) => CollabScope.read(context).presence = v,
        ),
        for (final (k, de, en) in [
          (ActivityKind.message, 'Nachrichten', 'Messages'),
          (ActivityKind.mention, 'Erwähnungen in Notizen', 'Mentions in notes'),
          (ActivityKind.joined, 'Jemand tritt bei (Einladung angenommen)', 'Someone joins (invitation accepted)'),
          (ActivityKind.billNew, 'Neue und geänderte Bons', 'New and changed receipts'),
        ])
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: Text(t.de ? de : en),
            value: CollabScope.of(context).notifies(k),
            onChanged: (v) => CollabScope.read(context).setNotifies(k, v),
          ),
        head(t.setLook),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(t.appearance),
          subtitle: Text(t.de ? 'Stil, Farbe, Schrift, Bewegung' : 'Style, colour, font, motion'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FasanAppearancePage())),
        ),
        ListTile(
          leading: const Icon(Icons.grid_view_outlined),
          title: Text(t.de ? 'Alle Stile vergleichen' : 'Compare all styles'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FasanGalleryPage())),
        ),
        if (perfGovernor != null) _PerfTile(governor: perfGovernor!),
        ListTile(
          leading: const Icon(Icons.school_outlined),
          title: TitleHelp(t.setIntro, t.setIntroSub),
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
          title: TitleHelp(t.setLocal, t.setLocalSub),
        ),
        ListTile(
          leading: const Icon(Icons.ios_share_rounded),
          title: TitleHelp(t.setExport, t.setExportSub),
          onTap: () => SharePlus.instance.share(ShareParams(files: [
            XFile.fromData(Uint8List.fromList(utf8.encode(store.exportJson())), mimeType: 'application/json', name: 'fasan-split-export.json'),
          ])),
        ),
        ListTile(
          leading: Icon(Icons.hide_image_outlined, color: Theme.of(context).colorScheme.error),
          title: TitleHelp(t.setDeletePhotos, t.setDeletePhotosSub),
          onTap: () async {
            if (await _confirm(context, t.setDeletePhotos, t.setDeletePhotosSub, t.delete) && context.mounted) {
              final n = StoreScope.read(context).removePhotos();
              showNote(context, t.photosDeleted(n));
            }
          },
        ),
        ListTile(
          leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
          title: TitleHelp(t.setDeleteAll, t.setDeleteAllSub(store.bills.length)),
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
          title: TitleHelp(t.autoUpdate, t.autoUpdateSub),
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


/// „Auf dem Handy anzeigen“: asks for the permission only here (Android 13+, browsers).
class _DeviceNotifyTile extends StatefulWidget {
  const _DeviceNotifyTile();

  @override
  State<_DeviceNotifyTile> createState() => _DeviceNotifyTileState();
}

class _DeviceNotifyTileState extends State<_DeviceNotifyTile> {
  @override
  Widget build(BuildContext context) {
    final t = S.of(context), n = deviceNotifier!;
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_active_outlined),
      title: TitleHelp(
        t.de ? 'Auf dem Gerät anzeigen' : 'Show on the device',
        t.de
            ? 'Solange die App läuft oder im Hintergrund ist, zeigt dein Gerät Neuigkeiten als Benachrichtigung. Ist die App ganz geschlossen, siehst du sie beim nächsten Öffnen in der Glocke – Fasan nutzt keinen Push-Dienst von Google.'
            : 'While the app runs or is in the background, your device shows news as notifications. When the app is fully closed you see them in the bell next time – Fasan uses no Google push service.',
      ),
      value: n.enabled,
      onChanged: (v) async {
        final messenger = ScaffoldMessenger.of(context);
        final ok = await n.setEnabled(v);
        if (!mounted) return;
        setState(() {});
        if (v && !ok) {
          messenger.showSnackBar(SnackBar(content: Text(t.de ? 'Benachrichtigungen sind in den Geräte-Einstellungen gesperrt.' : 'Notifications are blocked in the device settings.')));
        }
      },
    );
  }
}


/// „Über Tor verbinden“ (Nutzer 04.11.): all relay connections through Orbot (Guardian Project), so relays do not see
/// the IP address. Needs Orbot running; takes effect after a restart of the app.
class _TorTile extends StatefulWidget {
  const _TorTile();

  @override
  State<_TorTile> createState() => _TorTileState();
}

class _TorTileState extends State<_TorTile> {
  bool? _on;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final prefs = CollabScope.read(context).prefs;
    final on = _on ?? prefs?.getBool('net.tor') ?? false;
    return SwitchListTile(
      secondary: const Icon(Icons.security_rounded),
      title: TitleHelp(
        t.de ? 'Über Tor verbinden (Orbot)' : 'Connect through Tor (Orbot)',
        t.de
            ? 'Alle Verbindungen zu den Relays laufen über Tor. Dann sehen die Relays deine IP-Adresse nicht. Dafür muss die App Orbot (Guardian Project) installiert sein und laufen. Verbindungen werden langsamer. Gilt nach dem nächsten Start von Fasan Split.'
            : 'All relay connections go through Tor, so relays do not see your IP address. Needs the Orbot app (Guardian Project) installed and running. Connections get slower. Takes effect after the next start of Fasan Split.',
      ),
      value: on,
      onChanged: (v) async {
        final messenger = ScaffoldMessenger.of(context);
        if (v && !await proxyReachable('127.0.0.1:8118')) {
          messenger.showSnackBar(SnackBar(content: Text(t.de ? 'Orbot läuft nicht. Erst Orbot starten, dann einschalten.' : 'Orbot is not running. Start Orbot first.')));
          return;
        }
        await prefs?.setBool('net.tor', v);
        if (!mounted) return;
        setState(() => _on = v);
        messenger.showSnackBar(SnackBar(content: Text(t.de ? 'Gilt nach dem nächsten Start der App.' : 'Takes effect after the next start.')));
      },
    );
  }
}


/// „Performance“: automatic (measured at the start), always full effects, always light. Shows what the measurement found.
class _PerfTile extends StatefulWidget {
  const _PerfTile({required this.governor});
  final PerfGovernor governor;

  @override
  State<_PerfTile> createState() => _PerfTileState();
}

class _PerfTileState extends State<_PerfTile> {
  @override
  Widget build(BuildContext context) {
    final g = widget.governor, tt = Theme.of(context).textTheme, l = FasanLook.of(context);
    final state = switch (g.ui.tier) {
      PerfTier.good => context.tr('perf.nowGood'),
      PerfTier.slow => context.tr('perf.nowSlow'),
      PerfTier.veryslow => context.tr('perf.nowVerySlow'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, FasanSpace.s),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr('perf.title'), style: tt.titleMedium),
        const SizedBox(height: FasanSpace.xs),
        SegmentedButton<PerfMode>(
          key: const ValueKey('perf-mode'),
          segments: [
            ButtonSegment(value: PerfMode.auto, label: Text(context.tr('perf.auto'))),
            ButtonSegment(value: PerfMode.full, label: Text(context.tr('perf.full'))),
            ButtonSegment(value: PerfMode.light, label: Text(context.tr('perf.light'))),
          ],
          selected: {g.mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) async {
            await g.setMode(s.first);
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: FasanSpace.xs),
        Text('${context.tr('perf.sub')} $state', style: tt.bodySmall?.copyWith(color: l.textMuted)),
      ]),
    );
  }
}
