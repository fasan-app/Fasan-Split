// Fasan Split – start: saved bills, scan button in the thumb zone. MPL-2.0
import 'dart:io';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n.dart';
import '../main.dart';
import '../model/bill.dart';
import 'common.dart';
import 'assign.dart';
import 'flow.dart';
import 'onboarding.dart';
import 'update_ui.dart';
import '../update.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UpdateInfo? _update;

  /// At most once a day, only if enabled (Settings → Updates); silent without network.
  Future<void> _checkUpdate() async {
    final store = StoreScope.read(context);
    final last = store.lastUpdateCheck;
    if (!store.autoUpdate || (last != null && DateTime.now().difference(last) < const Duration(hours: 20))) return;
    store.lastUpdateCheck = DateTime.now();
    final u = await Updates.available();
    if (mounted && u != null) setState(() => _update = u);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
    // first start: introduction (skippable, Beschluss 02.11.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = StoreScope.read(context);
      if (!store.onboarded && store.bills.isEmpty) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
      }
    });
  }

  Future<void> _pick(BuildContext context, ImageSource src) async {
    final nav = Navigator.of(context);
    XFile? f;
    try {
      // full resolution like the web app (it reads the whole photo); cap at 4000 px against memory spikes
      f = await ImagePicker().pickImage(source: src, maxWidth: 4000, maxHeight: 4000, imageQuality: 95);
    } catch (_) {
      f = null;
    }
    if (f == null) return;
    final bytes = await f.readAsBytes();
    nav.push(MaterialPageRoute(builder: (_) => ScanScreen(photo: bytes)));
  }

  void _manual(BuildContext context) {
    final b = Bill(id: DateTime.now().microsecondsSinceEpoch.toString(), created: DateTime.now(), items: []);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(bill: b)));
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final store = StoreScope.of(context);
    final tt = Theme.of(context).textTheme;
    final drafts = store.drafts, done = store.finished;
    final bills = [...drafts, ...done];
    return Scaffold(
      appBar: AppBar(
        title: Text(t.appName),
        actions: [
          IconButton(
            tooltip: t.settings,
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Stack(children: [
        if (bills.isEmpty && _update != null)
          Positioned(left: FasanSpace.l, right: FasanSpace.l, top: FasanSpace.s, child: UpdateBanner(info: _update!, onClose: () => setState(() => _update = null))),
        if (bills.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(FasanSpace.xxl, 0, FasanSpace.xxl, 160),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.receipt_long_outlined, size: 56, color: FasanLook.of(context).textMuted),
                const SizedBox(height: FasanSpace.l),
                Text(t.emptyTitle, style: tt.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: FasanSpace.s),
                Text(t.emptyText, style: tt.bodyMedium!.copyWith(color: FasanLook.of(context).textMuted), textAlign: TextAlign.center),
              ]),
            ),
          )
        else
          ListView(
            padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 200 + MediaQuery.paddingOf(context).bottom),
            children: [
              if (_update != null) Padding(padding: const EdgeInsets.only(top: FasanSpace.s), child: UpdateBanner(info: _update!, onClose: () => setState(() => _update = null))),
              for (final (title, list) in [(t.drafts, drafts), (t.finished, done)])
                if (list.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(4, FasanSpace.m, 4, FasanSpace.s), child: FasanLabel(title)),
                  for (final b in list) Padding(padding: const EdgeInsets.only(bottom: FasanSpace.s), child: _BillTile(bill: b)),
                ],
            ],
          ),
        Positioned(
          left: FasanSpace.m,
          right: FasanSpace.m,
          bottom: FasanSpace.m + MediaQuery.paddingOf(context).bottom,
          child: FasanGlass(
            padding: const EdgeInsets.all(6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(child: FasanButton(label: t.camera, icon: Icons.photo_camera_outlined, expand: true, onPressed: () => _pick(context, ImageSource.camera))),
                const SizedBox(width: 6),
                Expanded(child: FasanButton(label: t.gallery, icon: Icons.photo_library_outlined, kind: FasanButtonKind.secondary, expand: true, onPressed: () => _pick(context, ImageSource.gallery))),
              ]),
              TextButton(onPressed: () => _manual(context), child: Text(t.manual)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    final date = '${bill.date.day}.${bill.date.month}.${bill.date.year}';
    return Material(
      color: l.surface,
      borderRadius: BorderRadius.circular(l.radius * 0.7),
      child: InkWell(
        borderRadius: BorderRadius.circular(l.radius * 0.7),
        // unfinished bills continue where the user left (Karte 3.9: Schließen verwirft nie)
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => bill.done ? ResultScreen(bill: bill) : resumeScreen(bill))),
        child: Container(
          constraints: BoxConstraints(minHeight: l.minTap + 16),
          padding: const EdgeInsets.all(FasanSpace.m),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(l.radius * 0.7), border: Border.all(color: l.hairline)),
          child: Row(children: [
            if (bill.imagePath != null && File(bill.imagePath!).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(File(bill.imagePath!), width: 40, height: 52, fit: BoxFit.cover, cacheWidth: 120),
              )
            else
              Icon(Icons.receipt_outlined, color: l.textMuted),
            const SizedBox(width: FasanSpace.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bill.purpose.isEmpty ? t.appName : bill.purpose, style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(bill.done ? '$date · ${bill.ps.length} ${t.de ? 'Personen' : 'people'}' : '$date · ${t.stepOf(bill.step)}', style: tt.bodySmall),
              ]),
            ),
            FasanAvatarStack(people: [for (final p in bill.ps) (p.name, p.color)], size: 24, max: 3),
            const SizedBox(width: FasanSpace.s),
            Money(bill.effectiveTotal),
          ]),
        ),
      ),
    );
  }
}

/// Screen of the step a draft was left on.
Widget resumeScreen(Bill b) => switch (b.step) {
      2 => PeopleScreen(bill: b),
      3 => AssignScreen(bill: b),
      4 => PayScreen(bill: b),
      _ => ReviewScreen(bill: b),
    };
