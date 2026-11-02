// Fasan Split – Gruppen and Freunde (local: nothing is sent anywhere), group page and the invitation draft. MPL-2.0
//
// Nutzer 02.11.: „Papierkorb, Archiv, Freunde, Gruppe, Einladungen“ each get a screen. Sharing over the network (encrypted
// Nostr events on public relays) needs the user's explicit release for every test (Beschluss 02.11.: nie in fremde Dienste
// schreiben), so the invitation here is a draft: a link with a fresh key and a QR code, shown on the phone only.
import 'dart:convert';
import 'dart:math';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:zxing2/qrcode.dart';

import '../l10n.dart';
import '../main.dart';
import '../model/bill.dart';
import '../state/scan_queue.dart';
import 'bill_tile.dart';

/// All groups with their number of bills and sum; tap opens the group.
class GroupsPage extends StatelessWidget {
  const GroupsPage({super.key, required this.queue});

  final ScanQueue queue;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final store = StoreScope.of(context);
    final names = store.allGroups;
    final bottom = 150 + MediaQuery.paddingOf(context).bottom;
    if (names.isEmpty) {
      return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottom), children: [
        const SizedBox(height: 80),
        Icon(Icons.folder_copy_outlined, size: 56, color: l.textMuted),
        const SizedBox(height: FasanSpace.l),
        Text(t.groupsEmptyTitle, style: tt.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: FasanSpace.s),
        Text(t.groupsEmptyText, style: tt.bodyMedium!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
      ]);
    }
    return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, bottom), children: [
      for (final g in names)
        Padding(
          padding: const EdgeInsets.only(bottom: FasanSpace.s),
          child: Builder(builder: (context) {
            final bills = store.inGroup(g);
            final sum = bills.fold<int>(0, (a, b) => a + b.effectiveTotal);
            return Material(
              color: l.surfaceAlt,
              borderRadius: BorderRadius.circular(l.radius * 0.7),
              child: InkWell(
                borderRadius: BorderRadius.circular(l.radius * 0.7),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupScreen(name: g, queue: queue))),
                child: Padding(
                  padding: const EdgeInsets.all(FasanSpace.m),
                  child: Row(children: [
                    Icon(Icons.folder_outlined, color: l.accent),
                    const SizedBox(width: FasanSpace.m),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(g, style: tt.titleMedium), Text(t.billsCount(bills.length), style: tt.bodySmall)])),
                    Text('${money(sum, de: t.de)} €', style: tt.titleMedium),
                  ]),
                ),
              ),
            );
          }),
        ),
    ]);
  }
}

/// One group: its bills (open and finished), the sum, and the invitation.
class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.name, required this.queue});

  final String name;
  final ScanQueue queue;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), tt = Theme.of(context).textTheme;
    final store = StoreScope.of(context);
    final bills = store.inGroup(name);
    final sum = bills.fold<int>(0, (a, b) => a + b.effectiveTotal);
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(tooltip: t.invite, icon: const Icon(Icons.person_add_alt_1_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(group: name)))),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                store.deleteGroup(name);
                Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Text(t.deleteGroup))],
          ),
        ],
      ),
      body: ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
        Padding(padding: const EdgeInsets.only(bottom: FasanSpace.m), child: Text('${t.billsCount(bills.length)} · ${money(sum, de: t.de)} €', style: tt.bodyMedium)),
        if (bills.isEmpty) Text(t.groupEmpty, style: tt.bodyMedium),
        for (final b in bills)
          Padding(padding: const EdgeInsets.only(bottom: FasanSpace.s), child: BillTile(bill: b, queue: queue, selecting: false, selected: false, onToggle: () {}, onRetry: () {})),
      ]),
    );
  }
}

/// People from the bills plus the ones added by hand, with their number of bills and what they consumed.
class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final store = StoreScope.of(context);
    final friends = store.friends;
    final bottom = 150 + MediaQuery.paddingOf(context).bottom;
    if (friends.isEmpty) {
      return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottom), children: [
        const SizedBox(height: 80),
        Icon(Icons.people_outline_rounded, size: 56, color: l.textMuted),
        const SizedBox(height: FasanSpace.l),
        Text(t.friendsEmptyTitle, style: tt.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: FasanSpace.s),
        Text(t.friendsEmptyText, style: tt.bodyMedium!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
      ]);
    }
    return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, bottom), children: [
      for (final f in friends)
        Padding(
          padding: const EdgeInsets.only(bottom: FasanSpace.s),
          child: Dismissible(
            key: ValueKey('friend-${f.name}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
              decoration: BoxDecoration(color: Colors.red.shade700.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(l.radius * 0.7)),
              child: Icon(Icons.person_remove_outlined, color: Colors.red.shade700),
            ),
            onDismissed: (_) => store.forgetFriend(f.name),
            child: Container(
              padding: const EdgeInsets.all(FasanSpace.m),
              decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.7)),
              child: Row(children: [
                FasanAvatar(name: f.name, index: f.color, size: 40),
                const SizedBox(width: FasanSpace.m),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(f.name, style: tt.titleMedium), Text(t.billsCount(f.bills), style: tt.bodySmall)])),
                if (f.bills > 0) Text('${money(f.sum, de: t.de)} €', style: tt.titleMedium),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// Invitation draft: a link with a fresh random key and its QR code. Nothing is sent (Beschluss 02.11.).
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, required this.group});

  final String group;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  late final String _link = () {
    final rnd = Random.secure();
    final key = base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256))).replaceAll('=', '');
    return 'fasan://join?g=${Uri.encodeComponent(widget.group)}&k=$key';
  }();

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final qr = Encoder.encode(_link, ErrorCorrectionLevel.m);
    return Scaffold(
      appBar: AppBar(title: Text(t.invite)),
      body: ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
        Text(t.inviteIntro(widget.group), style: tt.bodyMedium),
        const SizedBox(height: FasanSpace.l),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(l.radius * 0.7), border: Border.all(color: l.hairline)),
            child: SizedBox.square(dimension: 220, child: CustomPaint(painter: _QrPainter(qr))),
          ),
        ),
        const SizedBox(height: FasanSpace.l),
        SelectableText(_link, style: tt.bodySmall),
        const SizedBox(height: FasanSpace.l),
        Container(
          padding: const EdgeInsets.all(FasanSpace.m),
          decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.7)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lock_outline_rounded, size: 18, color: l.textMuted),
            const SizedBox(width: FasanSpace.s),
            Expanded(child: Text(t.inviteNotActive, style: tt.bodySmall)),
          ]),
        ),
      ]),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.code);

  final QRCode code;

  @override
  void paint(Canvas canvas, Size size) {
    final m = code.matrix!;
    final n = m.width, cell = size.width / n;
    final p = Paint()..color = Colors.black;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (m.get(x, y) == 1) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.code != code;
}
