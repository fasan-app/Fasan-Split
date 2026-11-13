// SPDX-License-Identifier: MPL-2.0
// Fasan Split – Invitations: cards on the start page, the invite screen with QR code, picking a person for a joined key. Split out of collab_ui.dart (13.11., Umbau, behaviour unchanged). MPL-2.0
import '../l10n/tr.dart';
import 'dart:async';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zxing2/qrcode.dart';

import '../collab/group.dart';
import '../collab/service.dart';
import '../l10n.dart';
import '../l10n_collab.dart';
import '../platform/web_platform.dart';
import '../l10n_groups.dart';
import 'scope.dart';
import 'common.dart' show showNote;
import 'join_screen.dart';
import 'shape_tokens.dart';
import 'collab_dialogs.dart';
// The screen an invitation link opens lives in join_screen.dart (exported here for the old imports).

class StorageWarningCard extends StatelessWidget {
  const StorageWarningCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (browserStorageWorks) return const SizedBox.shrink();
    final t = S.of(context), tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: FasanSpace.s),
      child: Material(
        color: Colors.orange.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(FasanLook.of(context).rCard),
        child: Padding(
          padding: const EdgeInsets.all(FasanSpace.m),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: FasanSpace.m),
            Expanded(
              child: Text(
                trLang(t.de ? 'de' : 'en', 'collab_ui.yourBrowserStoresNothing'),
                style: tt.bodySmall,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class OpenInviteCard extends StatelessWidget {
  const OpenInviteCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final code = takeJoinCode() ?? pendingInviteLink;
    if (code == null) return const SizedBox.shrink();
    final inv = Invite.parse(code);
    if (inv == null || inv.expired || CollabScope.of(context).groups.containsKey(inv.tag) || CollabScope.of(context).joins.any((j) => j.invite.tag == inv.tag)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: FasanSpace.s),
      child: Material(
        color: l.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(l.rCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(l.rCard),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JoinScreen(prefill: code.contains('#') ? code : '${Invite.inviteBase}#$code'))),
          child: Padding(
            padding: const EdgeInsets.all(FasanSpace.m),
            child: Row(children: [
              Icon(Icons.mail_outline_rounded, color: l.accent),
              const SizedBox(width: FasanSpace.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      inv.direct
                          ? (trLang(t.de ? 'de' : 'en', 'collab_ui.wantsToConnectWith', [inv.name]))
                          : (trLang(t.de ? 'de' : 'en', 'collab_ui.invitationTo', [inv.name])),
                      style: tt.titleMedium),
                  Text(trLang(t.de ? 'de' : 'en', 'collab_ui.tapHereEnterYour'), style: tt.bodySmall),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: l.accent),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Invitation link that opened the app (Android/iOS link or web page), kept until the request is sent.
String? pendingInviteLink;

class PendingJoinCards extends StatelessWidget {
  const PendingJoinCards({super.key});

  @override
  Widget build(BuildContext context) {
    final s = CollabScope.of(context), t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    if (s.joins.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (final p in s.joins)
        Padding(
          padding: const EdgeInsets.only(bottom: FasanSpace.s),
          child: Container(
            padding: const EdgeInsets.all(FasanSpace.m),
            decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.rCard)),
            child: Row(children: [
              Icon(Icons.hourglass_top_rounded, color: l.accent),
              const SizedBox(width: FasanSpace.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.invite.name.isEmpty ? t.joinWaiting : p.invite.name, style: tt.titleMedium),
                  Text(p.error == 'send' ? t.joinNoSend : (p.error != null ? t.joinTimeout : t.joinWaiting), style: tt.bodySmall),
                ]),
              ),
              IconButton(tooltip: t.cancel2, icon: const Icon(Icons.close_rounded), onPressed: () => s.cancelJoin(p)),
            ]),
          ),
        ),
    ]);
  }
}

/// Admin: choose which person of the group's bills a member is (or unlink). Names come from the bills and the people
/// added by hand (BillStore.groupMembers).
Future<void> pickPersonFor(BuildContext context, CollabGroup g, String pub) async {
  final t = S.of(context), s = CollabScope.read(context);
  final people = CollabScope.read(context).peopleOf(g.localName);
  final cur = g.session.personsOf(pub);
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(t.linkPerson, style: Theme.of(ctx).textTheme.titleMedium)),
        for (final p in people)
          ListTile(
            leading: Icon(cur.contains(p) ? Icons.link_rounded : Icons.person_outline_rounded),
            title: Text(p),
            subtitle: switch (g.session.memberOfPerson(p)) { final m? when m != pub => Text(t.linkedTo(g.session.nameOf(m))), _ => null },
            onTap: () => Navigator.pop(ctx, p),
          ),
      ]),
    ),
  );
  if (choice == null) return;
  // tap toggles: a linked name is unlinked, another one is added (a member can have several spellings)
  cur.contains(choice) ? s.unlinkPerson(g, pub, choice) : s.linkPerson(g, pub, choice);
}

/// Invitation for this group (admin only): QR code, link, requests to accept or decline, revoke.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, required this.group, this.person});

  final CollabGroup group;

  /// Person of the group's bills this invitation is for; the new member is linked to it on approval.
  final String? person;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  Invite? _current;
  StreamSubscription<void>? _sub;
  int _days = 7; // how long the link works (Nutzer 04.11.: „sagen wie lange die gelten“)

  Invitations? get _inv => widget.group.invitations;

  @override
  void initState() {
    super.initState();
    _sub = _inv?.changes.stream.listen((_) {
      if (mounted) setState(() {});
    });
    // the link is there at once: nothing to press before sharing (Nutzer 04.11.: inviting was too complicated). A link
    // for the same person that still works for a day is used again instead of piling up new ones.
    final inv = _inv;
    if (inv != null) {
      final reuse = inv.open.where((i) => i.person == widget.person && i.expires.isAfter(DateTime.now().add(const Duration(days: 1)))).toList()
        ..sort((a, b) => b.expires.compareTo(a.expires));
      _current = reuse.firstOrNull ?? inv.create(valid: Duration(days: _days), person: widget.person);
      if (reuse.isNotEmpty) _days = [1, 7, 30].firstWhere((d) => reuse.first.expires.isBefore(DateTime.now().add(Duration(days: d, hours: 1))), orElse: () => 30);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _setDays(int d) => setState(() {
        _days = d;
        _current = _inv!.create(valid: Duration(days: d), person: widget.person);
      });

  Future<void> _revoke() async {
    final msg = ScaffoldMessenger.of(context), text = S.of(context).inviteRevoked, nav = Navigator.of(context);
    setState(() => _current = null);
    await CollabScope.read(context).revokeInvites(widget.group); // new group key: this screen's group is the old one
    msg.showSnackBar(SnackBar(content: Text(text)));
    if (mounted) nav.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme, s = CollabScope.read(context);
    final de = t.de;
    final g = widget.group, inv = _inv, link = _current?.link;
    final requests = inv?.pending.values.toList() ?? const <JoinRequest>[];
    final me = s.identity?.name.trim().isNotEmpty == true ? s.identity!.name.trim() : StoreScope.read(context).me;
    final shareText = g.secret.direct
        ? (trLang(de ? 'de' : 'en', 'collab_ui.invitesYouToFasan', [me, link]))
        : (trLang(de ? 'de' : 'en', 'collab_ui.invitesYouToFasan2', [me, g.localName, link]));
    return Scaffold(
      appBar: AppBar(title: Text(g.secret.direct ? (trLang(de ? 'de' : 'en', 'collab_ui.inviteAFriend')) : (trLang(de ? 'de' : 'en', 'collab_ui.inviteTo', [g.localName])))),
      body: ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
        Text(
            g.secret.direct
                ? (trLang(de ? 'de' : 'en', 'collab_ui.whoeverOpensTheLink'))
                : (trLang(de ? 'de' : 'en', 'collab_ui.whoeverOpensTheLink2')),
            style: tt.bodyMedium),
        const SizedBox(height: FasanSpace.l),
        Text(trLang(de ? 'de' : 'en', 'collab_ui.validFor'), style: tt.labelLarge!.copyWith(color: l.textMuted)),
        const SizedBox(height: FasanSpace.xs),
        FasanSegmented<int>(
          values: const [1, 7, 30],
          selected: _days,
          label: (d) => de ? (d == 1 ? '1 Tag' : '$d Tage') : (d == 1 ? '1 day' : '$d days'),
          onChanged: inv == null ? (_) {} : _setDays,
        ),
        const SizedBox(height: FasanSpace.l),
        // old bills for newcomers (Nutzer 09.11. 19:04, Anforderung 18): hide them before sharing the link
        if (!g.secret.direct && s.hideableBills(g).isNotEmpty) ...[
          FasanButton(
            key: const ValueKey('hide-old-bills'),
            label: context.tr('vis.oldBills', ['${s.hideableBills(g).length}']),
            icon: Icons.visibility_off_outlined,
            kind: FasanButtonKind.quiet,
            expand: true,
            onPressed: () async {
              final n = s.hideableBills(g).length;
              final ok = await confirmDialog(context, context.tr('vis.oldTitle'), context.tr('vis.oldText', ['$n']), context.tr('vis.action'));
              if (!ok || !context.mounted) return;
              final done = s.hideAllBills(g);
              if (context.mounted) showNote(context, context.tr('vis.oldDone', ['$done']));
              setState(() {});
            },
          ),
          const SizedBox(height: FasanSpace.l),
        ],
        if (link != null) ...[
          FasanButton(label: trLang(de ? 'de' : 'en', 'collab_ui.shareLink'), icon: Icons.ios_share_rounded, expand: true, onPressed: () => SharePlus.instance.share(ShareParams(text: shareText))),
          const SizedBox(height: FasanSpace.s),
          FasanButton(
            label: t.inviteCopy,
            icon: Icons.copy_rounded,
            kind: FasanButtonKind.secondary,
            expand: true,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.inviteCopied)));
            },
          ),
          const SizedBox(height: FasanSpace.l),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(l.rCard), border: Border.all(color: l.hairline)),
              child: SizedBox.square(dimension: 180, child: CustomPaint(painter: _QrPainter(Encoder.encode(link, ErrorCorrectionLevel.m)))),
            ),
          ),
          const SizedBox(height: FasanSpace.xs),
          Center(child: Text(trLang(de ? 'de' : 'en', 'collab_ui.orLetThemScan'), style: tt.bodySmall)),
        ] else if (inv == null)
          Text(trLang(de ? 'de' : 'en', 'collab_ui.onlyTheGroupAdmins'), style: tt.bodyMedium),
        // requests only appear for groups that let people in by hand
        if (requests.isNotEmpty) ...[
          const SizedBox(height: FasanSpace.l),
          Text(t.requests, style: tt.titleMedium),
          for (final r in requests)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r.name.isEmpty ? r.pub.substring(0, 8) : r.name),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(onPressed: () => s.decline(g, r), child: Text(t.decline)),
                FilledButton(
                  onPressed: () async {
                    await s.approve(g, r);
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.approved(r.name.isEmpty ? r.pub.substring(0, 8) : r.name))));
                  },
                  child: Text(t.approve),
                ),
              ]),
            ),
        ],
        // every open link, with whom it is for and until when, each one can be withdrawn (Nutzer 04.11.)
        if (inv != null && inv.open.isNotEmpty) ...[
          const SizedBox(height: FasanSpace.xl),
          Text(trLang(de ? 'de' : 'en', 'collab_ui.openInvitations'), style: tt.titleMedium),
          for (final i in (inv.open..sort((a, b) => b.expires.compareTo(a.expires))))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(i == _current ? Icons.link_rounded : Icons.link_outlined, color: i == _current ? l.accent : l.textMuted),
              title: Text(i.person != null ? (trLang(de ? 'de' : 'en', 'collab_ui.for', [i.person])) : (trLang(de ? 'de' : 'en', 'collab_ui.forAnyoneWithThe'))),
              subtitle: Text('${trLang(de ? 'de' : 'en', 'collab_ui.validUntil')} ${i.expires.day}.${i.expires.month}. ${i.expires.hour.toString().padLeft(2, '0')}:${i.expires.minute.toString().padLeft(2, '0')}${i == _current ? (trLang(de ? 'de' : 'en', 'collab_ui.shownAbove')) : ''}'),
              trailing: IconButton(
                tooltip: trLang(de ? 'de' : 'en', 'collab_ui.withdraw'),
                icon: Icon(Icons.close_rounded, color: Colors.red.shade600),
                onPressed: () {
                  s.revokeInvite(g, i);
                  setState(() {
                    if (i == _current) _current = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trLang(de ? 'de' : 'en', 'collab_ui.linkWithdrawnWhoeverIs'))));
                },
              ),
            ),
        ],
        if (link == null && inv != null) ...[
          const SizedBox(height: FasanSpace.m),
          FasanButton(label: trLang(de ? 'de' : 'en', 'collab_ui.createANewLink'), icon: Icons.add_link_rounded, expand: true, onPressed: () => _setDays(_days)),
        ],
        const SizedBox(height: FasanSpace.xl),
        if (inv != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(icon: const Icon(Icons.link_off_rounded), label: Text(trLang(de ? 'de' : 'en', 'collab_ui.makeAllLinksInvalid')), onPressed: _revoke),
          ),
      ]),
    );
  }
}

/// A QR code on a white square (readable in dark mode too).
class QrView extends StatelessWidget {
  const QrView(this.text, {super.key, this.size = 220});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: SizedBox.square(dimension: size, child: CustomPaint(painter: _QrPainter(Encoder.encode(text, ErrorCorrectionLevel.m)))),
      );
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

/// Members of a live group. The admin can remove people.
