// SPDX-License-Identifier: MPL-2.0
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
import 'perf_test.dart';
import 'onboarding.dart';
import 'tutorial.dart';
import 'update_ui.dart';
import '../flows/update.dart';
import '../platform/web_platform.dart' show isBrowserApp, reloadPage, webBuildDate, webBuildShort, webNewsText, webUpdateCheck, webVersion;

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

  /// "Version 0.1.84 · 09.11.2026 02:10 · Stand f49f346" (browser). Parts that a local build does not know are left out.
  String _webVersionLine(String lang) {
    final parts = <String>[];
    final v = webVersion();
    if (v != null) parts.add(trLang(lang, 's.webVersion', [v]));
    final d = webBuildDate()?.toLocal();
    if (d != null) {
      String two(int n) => n.toString().padLeft(2, '0');
      parts.add('${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}');
    }
    parts.add(trLang(lang, 's.webBuild', [webBuildShort() ?? trLang(lang, 's.webBuildLocal')]));
    return parts.join(' · ');
  }

  /// Sheet with the curated news of the last versions (browser; the APK shows them in its update sheet).
  Future<void> _showNews(BuildContext context, String lang) async {
    final text = await webNewsText(lang);
    if (!context.mounted) return;
    if (text == null) {
      showNote(context, trLang(lang, 's.noConnectionWeb'));
      return;
    }
    final sections = Updates.newsSections(text);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          shrinkWrap: true,
          children: [
            Text(trLang(lang, 's.whatsNew'), style: Theme.of(ctx).textTheme.titleLarge),
            for (final (version, items) in sections) ...[
              Padding(padding: const EdgeInsets.only(top: 16, bottom: 4), child: Text(trLang(lang, 's.webVersion', [version]), style: Theme.of(ctx).textTheme.titleSmall)),
              for (final i in items) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('• $i')),
            ],
          ],
        ),
      ),
    );
  }

  /// Browser: asks the server for the newest build; a newer one is loaded at once (location.reload keeps localStorage and IndexedDB,
  /// so the login stays; everything typed is saved first, like in the automatic check in home.dart).
  Future<void> _webCheck(BuildContext context, S t) async {
    final lang = t.de ? 'de' : 'en';
    final store = StoreScope.read(context);
    final newer = await webUpdateCheck();
    if (!context.mounted) return;
    if (newer == null) {
      showNote(context, trLang(lang, 's.noConnectionWeb'));
    } else if (newer) {
      showNote(context, trLang(lang, 's.webReloading'));
      store.flush();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      reloadPage();
    } else {
      showNote(context, trLang(lang, 's.webUpToDate', [webBuildShort() ?? '']));
    }
  }

  /// The settings as sections (Apple-style: a calm list, each row opens one page; Nutzer 09.11.). Built again by every page, so the
  /// pages follow the store.
  List<_Sec> _sections(BuildContext context) {
    final t = S.of(context);
    final store = StoreScope.of(context);
    final l = FasanLook.of(context);
    final withLog = [for (final b in store.bills) if (b.logPath != null) b]..sort((a, b) => b.updated.compareTo(a.updated));
    // ignore: unused_local_variable
    Widget head(String s) => Padding(padding: const EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.l, FasanSpace.l, FasanSpace.xs), child: FasanLabel(s));
    return [
      _Sec(Icons.translate_rounded, 'Sprache · Language', [

        // always in both languages, so it can be found when the app is in the wrong one
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
      ]),
      _Sec(Icons.receipt_long_outlined, t.setBill, [
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
          title: TitleHelp(trLang(t.de ? 'de' : 'en', 'settings_screen.focusAndCardsWhen'), trLang(t.de ? 'de' : 'en', 'settings_screen.inAdditionToReceipt')),
          value: store.assignExtraModes,
          onChanged: (v) => store.assignExtraModes = v,
        ),
      ]),
      _Sec(Icons.people_outline_rounded, t.setPeople, [
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
      ]),
      _Sec(Icons.euro_rounded, trLang(t.de ? 'de' : 'en', 'settings_screen.currency'), [
        ...currencyTiles(context),
      ]),
      _Sec(Icons.cloud_upload_outlined, trLang(t.de ? 'de' : 'en', 'settings_screen.backup'), [
        ...backupTiles(context),
        // one place for notifications (Nutzer 04.11.: no contradicting settings hidden in sub menus)
      ]),
      _Sec(Icons.notifications_none_rounded, trLang(t.de ? 'de' : 'en', 'settings_screen.notifications'), [
        if (deviceNotifier != null) const _DeviceNotifyTile(),
        if (proxySupported) const _TorTile(),
        SwitchListTile(
          secondary: const Icon(Icons.visibility_outlined),
          title: TitleHelp(
            trLang(t.de ? 'de' : 'en', 'settings_screen.shareOnlineStatusAnd'),
            trLang(t.de ? 'de' : 'en', 'settings_screen.onYourGroupsAnd'),
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
      ]),
      _Sec(Icons.palette_outlined, t.setLook, [
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(t.appearance),
          subtitle: Text(trLang(t.de ? 'de' : 'en', 'settings_screen.styleColourFontMotion')),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FasanAppearancePage())),
        ),
        ListTile(
          leading: const Icon(Icons.grid_view_outlined),
          title: Text(trLang(t.de ? 'de' : 'en', 'settings_screen.compareAllStyles')),
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
        SwitchListTile(
          secondary: const Icon(Icons.tips_and_updates_outlined),
          title: Text(trLang(t.de ? 'de' : 'en', 'tip.setTitle')),
          subtitle: Text(trLang(t.de ? 'de' : 'en', 'tip.setSub')),
          value: store.showTips,
          onChanged: (v) => store.showTips = v,
        ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: Text(trLang(t.de ? 'de' : 'en', 'tutorial.title')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TutorialScreen())),
        ),
      ]),
      _Sec(Icons.storage_outlined, t.setData, [
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
      ]),
      _Sec(Icons.speed_rounded, t.setDiagnose, [
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text(t.shareLog),
          subtitle: Text(withLog.isEmpty ? t.noLogYet : t.setLogSub(withLog.first.purpose.isEmpty ? t.appName : withLog.first.purpose)),
          enabled: withLog.isNotEmpty,
          onTap: withLog.isEmpty ? null : () => shareRecognitionLog(context, withLog.first),
        ),
        ListTile(
          leading: const Icon(Icons.speed_rounded),
          title: Text(trLang(t.de ? 'de' : 'en', 'perf.test')),
          subtitle: Text(trLang(t.de ? 'de' : 'en', 'perf.testSub')),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PerfTestScreen())),
        ),
      ]),
      _Sec(Icons.system_update_alt_rounded, t.setUpdates, [
        FutureBuilder<String>(
          future: Updates.currentVersion(),
          builder: (context, v) => ListTile(
            leading: const Icon(Icons.system_update_rounded),
            title: Text(t.checkNow),
            subtitle: Text(isBrowserApp ? _webVersionLine(t.de ? 'de' : 'en') : t.version(v.data ?? '…')),
            onTap: isBrowserApp
                ? () => _webCheck(context, t)
                : () async {
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
        if (isBrowserApp)
          ListTile(
            leading: const Icon(Icons.new_releases_outlined),
            title: Text(trLang(t.de ? 'de' : 'en', 's.whatsNew')),
            subtitle: Text(trLang(t.de ? 'de' : 'en', 's.whatsNewSub')),
            onTap: () => _showNews(context, t.de ? 'de' : 'en'),
          ),
        FasanSwitchTile(
          padded: true,
          secondary: const Icon(Icons.update_rounded),
          title: TitleHelp(t.autoUpdate, t.autoUpdateSub),
          value: store.autoUpdate,
          onChanged: (v) => store.autoUpdate = v,
        ),
      ]),
      _Sec(Icons.info_outline, t.about, [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Fasan Split'),
          subtitle: Text(trLang(t.de ? 'de' : 'en', 'settings_screen.freeMplOfflineNo')),
          onTap: () => showLicensePage(context: context, applicationName: 'Fasan Split', applicationLegalese: 'MPL-2.0 · fasan-app'),
        ),
        Padding(
          padding: const EdgeInsets.all(FasanSpace.l),
          child: Text(t.setFewNote, style: Theme.of(context).textTheme.bodySmall!.copyWith(color: l.textMuted)),
        ),

      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context);
    final secs = _sections(context);
    // blocks like the system settings: look and bill, then data, then the rest
    const blocks = [[6, 0, 1, 2, 3], [5, 4, 7], [8, 9, 10]];
    return Scaffold(
      appBar: AppBar(title: Text(t.settings)),
      body: ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, FasanSpace.xxl + MediaQuery.paddingOf(context).bottom), children: [
        for (final blk in blocks) ...[
          Material(
            color: l.surfaceAlt,
            borderRadius: BorderRadius.circular(l.radius * 0.7),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var k = 0; k < blk.length; k++) ...[
                if (k > 0) Divider(height: 1, indent: 56, color: l.hairline),
                SizedBox(
                  height: 52,
                  child: InkWell(
                    key: ValueKey('settings-${blk[k]}'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SectionPage(owner: this, index: blk[k]))),
                    child: Row(children: [
                      const SizedBox(width: FasanSpace.m),
                      Icon(secs[blk[k]].icon, color: l.accent, size: 22),
                      const SizedBox(width: FasanSpace.m),
                      Expanded(child: Text(secs[blk[k]].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyLarge)),
                      Icon(Icons.chevron_right_rounded, color: l.textMuted),
                      const SizedBox(width: FasanSpace.s),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: FasanSpace.l),
        ],
      ]),
    );
  }
}

/// One section of the settings: symbol, title, the rows.
class _Sec {
  const _Sec(this.icon, this.title, this.children);

  final IconData icon;
  final String title;
  final List<Widget> children;
}

/// The page of one section; it asks the owner for its rows on every build, so a changed setting shows at once.
class _SectionPage extends StatelessWidget {
  const _SectionPage({required this.owner, required this.index});

  final SettingsScreen owner;
  final int index;

  @override
  Widget build(BuildContext context) {
    final sec = owner._sections(context)[index];
    return Scaffold(
      appBar: AppBar(title: Text(sec.title)),
      body: ListView(padding: EdgeInsets.only(top: FasanSpace.s, bottom: FasanSpace.xxl + MediaQuery.paddingOf(context).bottom), children: sec.children),
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
        trLang(t.de ? 'de' : 'en', 'settings_screen.showOnTheDevice'),
        trLang(t.de ? 'de' : 'en', 'settings_screen.whileTheAppRuns'),
      ),
      value: n.enabled,
      onChanged: (v) async {
        final messenger = ScaffoldMessenger.of(context);
        final ok = await n.setEnabled(v);
        if (!mounted) return;
        setState(() {});
        if (v && !ok) {
          messenger.showSnackBar(SnackBar(content: Text(trLang(t.de ? 'de' : 'en', 'settings_screen.notificationsAreBlockedIn'))));
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
        trLang(t.de ? 'de' : 'en', 'settings_screen.connectThroughTorOrbot'),
        trLang(t.de ? 'de' : 'en', 'settings_screen.allRelayConnectionsGo'),
      ),
      value: on,
      onChanged: (v) async {
        final messenger = ScaffoldMessenger.of(context);
        if (v && !await proxyReachable('127.0.0.1:8118')) {
          messenger.showSnackBar(SnackBar(content: Text(trLang(t.de ? 'de' : 'en', 'settings_screen.orbotIsNotRunning'))));
          return;
        }
        await prefs?.setBool('net.tor', v);
        if (!mounted) return;
        setState(() => _on = v);
        messenger.showSnackBar(SnackBar(content: Text(trLang(t.de ? 'de' : 'en', 'settings_screen.takesEffectAfterThe'))));
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
