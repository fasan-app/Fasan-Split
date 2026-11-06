// Fasan Split – screens of the collaboration: joining, live sharing with the one-time consent, invitations, members,
// notes, chat and the account. The screens talk only to CollabService. Public relays are contacted only after the user
// has agreed in the consent dialog, and tests never reach them (they use MemoryRelay). MPL-2.0
import '../l10n/tr.dart' show trLang;
import 'dart:async';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zxing2/qrcode.dart';

import '../collab/activity.dart';
import '../collab/group.dart';
import '../collab/notes.dart';
import '../collab/service.dart';
import '../l10n.dart';
import '../l10n_collab.dart';
import '../platform/web_platform.dart';
import '../l10n_groups.dart';
import 'scope.dart';
import '../flows/scan_queue.dart';
import 'bill_tile.dart';
import 'common.dart' show TitleHelp, showNote;
import 'package:fasan_core/bill.dart' show money;
import 'groups.dart';
import 'pairing_ui.dart';
import 'marquee_text.dart';
import 'join_screen.dart';
// The screen an invitation link opens lives in join_screen.dart (exported here for the old imports).
export 'join_screen.dart' show JoinScreen, AccountSafetyCard;

const _kConsent = 'collab.consent';
bool _consentInMemory = false; // used when there are no preferences (tests)

/// The one-time agreement before the first contact with public relays. True when the user agreed.
Future<bool> ensureConsent(BuildContext context, CollabService s) async {
  if (s.prefs?.getBool(_kConsent) ?? _consentInMemory) return true;
  final t = S.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.consentTitle),
      content: SingleChildScrollView(child: Text(t.consentText)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel2)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.consentOk)),
      ],
    ),
  );
  if (ok != true) return false;
  _consentInMemory = true;
  await s.prefs?.setBool(_kConsent, true);
  return true;
}

/// Shares a group that already exists on this phone. Null when the user did not agree.
Future<CollabGroup?> shareLive(BuildContext context, String localName) async {
  final s = CollabScope.read(context);
  if (!await ensureConsent(context, s)) return null;
  return s.shareLocalGroup(localName);
}

/// Creates a new group that is shared live and adds it to the bill list. Null when the user did not agree.
Future<CollabGroup?> createLiveGroup(BuildContext context, String name) async {
  final s = CollabScope.read(context), store = StoreScope.read(context);
  if (!await ensureConsent(context, s)) return null;
  final g = await s.createGroup(name);
  store.addGroup(g.localName);
  return g;
}

/// A single line of text in a dialog. Null when cancelled or empty.
Future<String?> askText(BuildContext context, String title, String hint) async {
  final r = await showDialog<String>(context: context, builder: (_) => _TextDialog(title: title, hint: hint));
  if (r == null || r.trim().isEmpty) return null;
  return r.trim();
}

/// The dialog owns its controller: it is disposed with the dialog, not while the closing animation still uses it.
class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.hint});

  final String title, hint;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        TextButton(onPressed: () => Navigator.pop(context, _c.text), child: Text(t.ok)),
      ],
    );
  }
}

/// Yes/no question. True only when the user confirms.
Future<bool> confirmDialog(BuildContext context, String title, String text, String action) async {
  final t = S.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok == true;
}

/// The + on the groups page: a new live group, a new group only on this phone, or joining one.
Future<void> groupPlusAction(BuildContext context, {ScanQueue? queue}) async {
  final t = S.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.wifi_tethering_rounded), title: Text(t.newGroupLive), subtitle: Text(t.collabShareText), onTap: () => Navigator.pop(ctx, 'live')),
        ListTile(leading: const Icon(Icons.folder_outlined), title: Text(t.newGroupLocal), onTap: () => Navigator.pop(ctx, 'local')),
        ListTile(leading: const Icon(Icons.link_rounded), title: Text(t.joinGroup), subtitle: Text(t.joinText), onTap: () => Navigator.pop(ctx, 'join')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'join') {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JoinScreen()));
    return;
  }
  final name = await askText(context, t.newGroup, t.groupName);
  if (name == null || !context.mounted) return;
  if (choice == 'live') {
    await createLiveGroup(context, name);
  } else {
    StoreScope.read(context).addGroup(name);
    if (queue != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupScreen(name: name.trim(), queue: queue)));
  }
}

/// Rebuilds its child whenever a document of the group changes (members, notes, chat, bills of others).
class GroupChangeBuilder extends StatefulWidget {
  const GroupChangeBuilder({super.key, required this.group, required this.builder, this.docId});

  final CollabGroup group;
  final WidgetBuilder builder;
  final String? docId; // only changes of this document, or all when null

  @override
  State<GroupChangeBuilder> createState() => _GroupChangeBuilderState();
}

class _GroupChangeBuilderState extends State<GroupChangeBuilder> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.group.session.changes.listen((id) {
      if (mounted && (widget.docId == null || widget.docId == id)) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Pending join requests of this phone, shown on the groups page until the admin answers.
/// An invitation that was opened but not used yet (the join screen was closed or covered): one big card on the start
/// page until the request is out (Nutzer 04.11.: people have little patience, it must be impossible to miss).
/// Browser without storage (private window, blocked site data): everything lives in memory until the tab closes.
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
        borderRadius: BorderRadius.circular(FasanLook.of(context).radius * 0.7),
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
        borderRadius: BorderRadius.circular(l.radius * 0.7),
        child: InkWell(
          borderRadius: BorderRadius.circular(l.radius * 0.7),
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
            decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.7)),
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
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(l.radius * 0.7), border: Border.all(color: l.hairline)),
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
class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key, required this.group});

  final CollabGroup group;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), s = CollabScope.read(context);
    final me = s.identity?.pub, admin = group.secret.adminPub;
    return Scaffold(
      appBar: AppBar(title: Text(t.membersTitle)),
      body: GroupChangeBuilder(
        group: group,
        docId: GroupSession.members,
        builder: (context) {
          final keys = [admin, ...group.session.memberKeys.where((k) => k != admin)];
          return ListView(padding: const EdgeInsets.all(FasanSpace.l), children: [
            for (final k in keys)
              ListTile(
                leading: CircleAvatar(child: Text(group.session.nameOf(k).characters.first.toUpperCase())),
                title: Text(k == me ? '${group.session.nameOf(k)} (${t.you})' : group.session.nameOf(k)),
                subtitle: Text([
                  k == admin ? t.founder : (group.session.admins.contains(k) ? t.admin : k.substring(0, 12)),
                  if (group.session.personsOf(k) case final ps when ps.isNotEmpty) t.linkedTo(ps.join(', ')),
                  if (s.distrusted.contains(k)) t.confirmsAboutMe,
                ].join(' · ')),
                trailing: k == me ? null : const Icon(Icons.more_vert_rounded),
                onTap: k == me && !group.isAdmin ? null : () => memberActions(context, group, k),
              ),
          ]);
        },
      ),
    );
  }
}

/// Notes of a live group. Everyone sees new notes at once.
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key, required this.group});

  final CollabGroup group;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), s = CollabScope.read(context), tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.notesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: Text(t.newNote),
        onPressed: () async {
          final title = await askText(context, t.newNote, t.noteTitle);
          if (title == null || !context.mounted) return;
          final id = s.newNote(group, title);
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteEditor(group: group, noteId: id)));
        },
      ),
      body: GroupChangeBuilder(
        group: group,
        docId: GroupSession.notes,
        builder: (context) {
          final notes = s.notes(group);
          if (notes.isEmpty) {
            return Center(child: Padding(padding: const EdgeInsets.all(FasanSpace.l), child: Text(t.notesEmpty, style: tt.bodyMedium, textAlign: TextAlign.center)));
          }
          return ListView(padding: const EdgeInsets.all(FasanSpace.l), children: [
            for (final n in notes)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(n.title.isEmpty ? t.noteTitle : n.title),
                subtitle: MarqueeText(n.text.split('\n').first, style: Theme.of(context).textTheme.bodyMedium),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteEditor(group: group, noteId: n.id))),
              ),
          ]);
        },
      ),
    );
  }
}

/// One note. Saves a moment after typing. Changes from others are shown unless the field has the focus.
class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, required this.group, required this.noteId});

  final CollabGroup group;
  final String noteId;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final CollabService _service;
  late final TextEditingController _title, _text;
  final FocusNode _titleFocus = FocusNode(), _textFocus = FocusNode();
  StreamSubscription<String>? _sub;
  Timer? _timer;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _service = CollabScope.read(context);
    final n = _find();
    _title = TextEditingController(text: n?.title ?? '');
    _text = TextEditingController(text: n?.text ?? '');
    _sub = widget.group.session.changes.listen((id) {
      if (id != GroupSession.notes || !mounted) return;
      final cur = _find();
      if (cur == null) return;
      if (!_titleFocus.hasFocus && cur.title != _title.text) _title.text = cur.title;
      if (!_textFocus.hasFocus && cur.text != _text.text) _text.text = cur.text;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_dirty) _flush();
    _timer?.cancel();
    _title.dispose();
    _text.dispose();
    _titleFocus.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  NoteInfo? _find() {
    for (final n in _service.notes(widget.group)) {
      if (n.id == widget.noteId) return n;
    }
    return null;
  }

  void _changed() {
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), _flush);
  }

  void _flush() {
    _timer?.cancel();
    _timer = null;
    _dirty = false;
    _service.saveNote(widget.group, widget.noteId, title: _title.text.trim(), text: _text.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.notesTitle)),
      body: ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
        TextField(
          controller: _title,
          focusNode: _titleFocus,
          style: tt.titleLarge,
          decoration: InputDecoration(hintText: t.noteTitle, border: InputBorder.none),
          onChanged: (_) => _changed(),
        ),
        TextField(
          controller: _text,
          focusNode: _textFocus,
          minLines: 12,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(hintText: t.noteText, border: InputBorder.none),
          onChanged: (_) => _changed(),
        ),
      ]),
    );
  }
}

/// Chat of a live group.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.group});

  final CollabGroup group;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();

  /// Message I answer (quote above the input) or edit (the input holds its text); at most one of the two.
  ChatMessage? _replyTo, _editing;

  /// People (public keys) picked with @ for the message being written.
  final Set<String> _mentions = {};

  /// Search in this chat: shown instead of the title while open.
  bool _searching = false;
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    _query.dispose();
    super.dispose();
  }

  /// Members of the group that can be mentioned (not me).
  List<(String, String)> _members() {
    final g = widget.group, me = CollabScope.read(context).identity?.pub;
    return [for (final k in g.session.memberKeys) if (k != me) (k, g.session.nameOf(k))]..sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
  }

  Future<void> _mention() async {
    final de = S.of(context).de, people = _members();
    final who = await showModalBottomSheet<(String, String)>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(trLang(de ? 'de' : 'en', 'collab_ui.mentionWhom'), style: Theme.of(ctx).textTheme.titleMedium)),
          if (people.isEmpty) ListTile(title: Text(trLang(de ? 'de' : 'en', 'collab_ui.nobodyElseInThe'))),
          for (final p in people) ListTile(leading: FasanAvatar(name: p.$2, index: 0, size: 32), title: Text(p.$2), onTap: () => Navigator.pop(ctx, p)),
        ]),
      ),
    );
    if (who == null || !mounted) return;
    _mentions.add(who.$1);
    final t = _input.text;
    _input.text = '${t.isEmpty || t.endsWith(' ') ? t : '$t '}@${who.$2} ';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  /// The message text with @names of mentioned people in bold.
  InlineSpan _rich(ChatMessage m, TextStyle? base, Color accent) {
    final names = {for (final k in m.mentions) widget.group.session.nameOf(k)}..removeWhere((n) => n.trim().isEmpty);
    if (names.isEmpty) return TextSpan(text: m.text, style: base);
    final re = RegExp('@(${names.map(RegExp.escape).join('|')})');
    final spans = <InlineSpan>[];
    var i = 0;
    for (final x in re.allMatches(m.text)) {
      if (x.start > i) spans.add(TextSpan(text: m.text.substring(i, x.start)));
      spans.add(TextSpan(text: x.group(0), style: TextStyle(fontWeight: FontWeight.w700, color: accent)));
      i = x.end;
    }
    if (i < m.text.length) spans.add(TextSpan(text: m.text.substring(i)));
    return TextSpan(style: base, children: spans);
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final c = CollabScope.read(context);
    final edit = _editing;
    if (edit != null) {
      c.editMessage(widget.group, edit.id, text);
    } else {
      c.sendMessage(widget.group, text, reply: _replyTo?.id, mentions: _mentions.toList());
    }
    _mentions.clear();
    _input.clear();
    setState(() => _replyTo = _editing = null);
  }

  static const _emojis = ['👍', '❤️', '😂', '😮', '🙏'];

  /// Long press on a message: react, answer, copy, and – for my own – edit or delete (Nutzer 04.11.).
  Future<void> _actions(ChatMessage m, bool mine) async {
    if (m.deleted) return;
    final de = S.of(context).de, c = CollabScope.read(context), me = c.identity?.pub;
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true, // many entries on a small or landscape screen: the menu scrolls instead of being cut off
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: FasanSpace.s),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final e in _emojis)
                IconButton(
                  tooltip: e,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  style: m.reactions[me] == e ? IconButton.styleFrom(backgroundColor: FasanLook.of(ctx).accent.withValues(alpha: 0.25)) : null,
                  icon: Text(e, style: const TextStyle(fontSize: 24)),
                  onPressed: () => Navigator.pop(ctx, 'react:$e'),
                ),
            ]),
          ),
          ListTile(leading: const Icon(Icons.reply_rounded), title: Text(trLang(de ? 'de' : 'en', 'collab_ui.reply')), onTap: () => Navigator.pop(ctx, 'reply')),
          if (m.text.isNotEmpty) ListTile(leading: const Icon(Icons.copy_rounded), title: Text(trLang(de ? 'de' : 'en', 'collab_ui.copy')), onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(leading: Icon(m.pinned ? Icons.push_pin : Icons.push_pin_outlined), title: Text(m.pinned ? (trLang(de ? 'de' : 'en', 'collab_ui.unpin')) : (trLang(de ? 'de' : 'en', 'collab_ui.pin'))), onTap: () => Navigator.pop(ctx, 'pin')),
          if (mine && m.bill == null) ListTile(leading: const Icon(Icons.edit_outlined), title: Text(trLang(de ? 'de' : 'en', 'collab_ui.edit')), onTap: () => Navigator.pop(ctx, 'edit')),
          if (mine) ListTile(leading: const Icon(Icons.delete_outline_rounded), title: Text(trLang(de ? 'de' : 'en', 'collab_ui.deleteForEveryone')), onTap: () => Navigator.pop(ctx, 'delete')),
          ]),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice.startsWith('react:')) {
      c.reactToMessage(widget.group, m.id, choice.substring(6));
    } else if (choice == 'reply') {
      setState(() {
        _replyTo = m;
        _editing = null;
      });
    } else if (choice == 'pin') {
      c.pinMessage(widget.group, m.id, !m.pinned);
    } else if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
    } else if (choice == 'edit') {
      setState(() {
        _editing = m;
        _replyTo = null;
        _input.text = m.text;
        _input.selection = TextSelection.collapsed(offset: m.text.length);
      });
    } else if (choice == 'delete') {
      c.deleteMessage(widget.group, m.id);
    }
  }

  /// Short one-line description of a message for quotes.
  String _preview(ChatMessage m, bool de) => m.deleted ? (trLang(de ? 'de' : 'en', 'collab_ui.messageDeleted')) : (m.bill != null ? (trLang(de ? 'de' : 'en', 'collab_ui.receipt', [m.text])) : m.text);

  /// Tag a bill in the chat: the bills of this group, or – writing to a friend – of the groups we share.
  Future<void> _attach() async {
    final c = CollabScope.read(context), store = StoreScope.read(context), de = S.of(context).de;
    final g = widget.group;
    final peer = g.secret.direct ? c.directPeer(g) : null;
    final groupsHere = g.secret.direct
        ? {for (final x in c.groups.values) if (!x.secret.direct && peer != null && x.session.memberKeys.contains(peer)) x.localName}
        : {g.localName};
    final bills = store.bills.where((b) => b.trashedAt == null && groupsHere.contains(b.group)).toList()..sort((a, b) => b.date.compareTo(a.date));
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: Text(trLang(de ? 'de' : 'en', 'collab_ui.whichReceipt'), style: Theme.of(ctx).textTheme.titleMedium)),
            if (bills.isEmpty) ListTile(title: Text(trLang(de ? 'de' : 'en', 'collab_ui.noSharedReceiptsYet'))),
            for (final b in bills)
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(b.purpose.isEmpty ? 'Bon' : b.purpose),
                subtitle: Text('${b.group ?? ''} · ${money(b.effectiveTotal, de: de)}'),
                onTap: () => Navigator.pop(ctx, b.id),
              ),
          ]),
        ),
      ),
    );
    if (id == null) return;
    final b = store.bills.firstWhere((x) => x.id == id);
    c.sendMessage(g, b.purpose.isEmpty ? 'Bon' : b.purpose, bill: id);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
          actions: [
            IconButton(
              tooltip: trLang(t.de ? 'de' : 'en', 'collab_ui.searchThisChat'),
              icon: Icon(_searching ? Icons.search_off_rounded : Icons.search_rounded),
              onPressed: () => setState(() {
                _searching = !_searching;
                _query.clear();
              }),
            ),
            IconButton(
              tooltip: CollabScope.of(context).isMuted(widget.group) ? (trLang(t.de ? 'de' : 'en', 'collab_ui.unmute')) : (trLang(t.de ? 'de' : 'en', 'collab_ui.mute')),
              icon: Icon(CollabScope.of(context).isMuted(widget.group) ? Icons.notifications_off_rounded : Icons.notifications_none_rounded),
              onPressed: () {
                final c = CollabScope.read(context), now = !c.isMuted(widget.group);
                c.setMuted(widget.group, now);
                showNote(context, now ? (trLang(t.de ? 'de' : 'en', 'collab_ui.mutedNoNotificationsFrom')) : (trLang(t.de ? 'de' : 'en', 'collab_ui.notificationsOnAgain')));
              },
            ),
          ],
          title: _searching
              ? TextField(controller: _query, autofocus: true, decoration: InputDecoration(hintText: trLang(t.de ? 'de' : 'en', 'collab_ui.search'), border: InputBorder.none), onChanged: (_) => setState(() {}))
              : GroupChangeBuilder(
              group: widget.group,
              docId: GroupSession.members,
              builder: (context) {
                final g = widget.group, c = CollabScope.of(context); // rebuilds with presence changes
                final n = g.secret.direct ? c.directName(g) : g.localName;
                final peer = g.secret.direct ? c.directPeer(g) : null;
                final seen = peer == null ? null : c.lastSeen(peer);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(n.isEmpty ? t.chatTitle : n),
                  if (peer != null && (c.isOnline(peer) || seen != null))
                    Text(
                      c.isOnline(peer) ? 'online' : trLang(t.de ? 'de' : 'en', 'collab_ui.lastSeen', [seen!.day, seen.month, seen.hour.toString().padLeft(2, '0'), seen.minute.toString().padLeft(2, '0')]),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ]);
              })),
      body: Column(children: [
        Expanded(
          child: GroupChangeBuilder(
            group: widget.group,
            docId: GroupSession.chat,
            builder: (context) {
              final s = CollabScope.of(context), me = s.identity?.pub; // read marks of others rebuild too
              final all = s.messages(widget.group);
              final q = _searching ? _query.text.trim().toLowerCase() : '';
              final msgs = q.isEmpty ? all : [for (final m in all) if (!m.deleted && m.text.toLowerCase().contains(q)) m];
              final pinned = all.where((m) => m.pinned && !m.deleted).lastOrNull;
              // open chat = read (after this frame: marking notifies)
              WidgetsBinding.instance.addPostFrameCallback((_) => s.markRead(widget.group));
              if (q.isNotEmpty && msgs.isEmpty) {
                return Center(child: Text(trLang(t.de ? 'de' : 'en', 'collab_ui.nothingFound'), style: tt.bodyMedium));
              }
              if (msgs.isEmpty) {
                return Center(child: Padding(padding: const EdgeInsets.all(FasanSpace.l), child: Text(t.chatEmpty, style: tt.bodyMedium, textAlign: TextAlign.center)));
              }
              return Column(children: [
                // the newest pinned message stays on top; the long-press menu unpins it
                if (pinned != null)
                  Material(
                    color: l.surfaceAlt,
                    child: InkWell(
                      onLongPress: () => _actions(pinned, pinned.from == me),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: l.minTap),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: FasanSpace.s),
                          child: Row(children: [
                            Icon(Icons.push_pin, size: 16, color: l.accent),
                            const SizedBox(width: FasanSpace.s),
                            Expanded(child: Text('${pinned.from == me ? t.you : widget.group.session.nameOf(pinned.from)}: ${_preview(pinned, t.de)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodySmall)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                    child: ListView.builder(
                padding: const EdgeInsets.all(FasanSpace.m),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m = msgs[i], mine = m.from == me;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () => _actions(m, mine),
                      child: Container(
                      margin: const EdgeInsets.only(bottom: FasanSpace.s),
                      padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: FasanSpace.s),
                      decoration: BoxDecoration(color: mine ? l.accent.withValues(alpha: 0.18) : l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.6), border: m.mentions.contains(me) ? Border.all(color: l.accent, width: 1.5) : null),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(mine ? t.you : widget.group.session.nameOf(m.from), style: tt.labelSmall),
                        // quote of the message this one answers
                        if (m.reply != null)
                          Builder(builder: (context) {
                            final q = msgs.where((x) => x.id == m.reply).firstOrNull;
                            return Container(
                              margin: const EdgeInsets.only(top: 2, bottom: 4),
                              padding: const EdgeInsets.only(left: FasanSpace.s),
                              decoration: BoxDecoration(border: Border(left: BorderSide(color: l.accent, width: 3))),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                if (q != null) Text(q.from == me ? t.you : widget.group.session.nameOf(q.from), style: tt.labelSmall),
                                Text(q == null ? (trLang(t.de ? 'de' : 'en', 'collab_ui.messageNoLongerAvailable')) : _preview(q, t.de), maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
                              ]),
                            );
                          }),
                        if (m.bill != null && !m.deleted)
                          // a tagged bill: the card opens it (Nutzer 04.11.)
                          switch (StoreScope.read(context).bills.where((b) => b.id == m.bill).firstOrNull) {
                            final b? => ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 300),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: BillTile(bill: b, queue: ScanQueue.current ?? ScanQueue(StoreScope.read(context)), selecting: false, selected: false, onToggle: () {}, onRetry: () {}),
                                ),
                              ),
                            _ => Text(trLang(t.de ? 'de' : 'en', 'collab_ui.receiptNotAvailable'), style: tt.bodySmall),
                          },
                        if (m.deleted)
                          Text(trLang(t.de ? 'de' : 'en', 'collab_ui.messageDeleted2'), style: tt.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: l.textMuted))
                        else if (m.text.isNotEmpty && m.bill == null)
                          Text.rich(_rich(m, tt.bodyMedium, l.accent)),
                        if (m.edited && !m.deleted) Text(trLang(t.de ? 'de' : 'en', 'collab_ui.edited'), style: tt.labelSmall),
                        // reactions: emoji with the number of people; changed through the long-press menu
                        if (m.reactions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(spacing: 6, children: [
                              for (final e in {...m.reactions.values})
                                Text('$e ${m.reactions.values.where((x) => x == e).length}', style: tt.labelMedium?.copyWith(fontWeight: m.reactions[me] == e ? FontWeight.w700 : null)),
                            ]),
                          ),
                        // ✓ sent, ✓✓ read (direct: the friend; group: how many have read it) – only with presence on
                        if (mine)
                          Builder(builder: (context) {
                            final readers = [
                              for (final k in widget.group.session.memberKeys)
                                if (k != me && (s.readUntil(widget.group, k)?.millisecondsSinceEpoch ?? 0) >= m.at.millisecondsSinceEpoch) k,
                            ];
                            final read = readers.isNotEmpty;
                            return Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(read ? Icons.done_all_rounded : Icons.done_rounded, size: 14, color: read ? l.accent : l.textMuted),
                              if (read && !widget.group.secret.direct) ...[const SizedBox(width: 3), Text(trLang(t.de ? 'de' : 'en', 'collab_ui.readBy', [readers.length]), style: tt.labelSmall)],
                            ]);
                          }),
                      ]),
                    ),
                    ),
                  );
                },
              )),
              ]);
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(FasanSpace.m, 0, FasanSpace.m, FasanSpace.s),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_replyTo != null || _editing != null)
                Container(
                  margin: const EdgeInsets.only(bottom: FasanSpace.s),
                  padding: const EdgeInsets.only(left: FasanSpace.m),
                  decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.6)),
                  child: Row(children: [
                    Icon(_editing != null ? Icons.edit_outlined : Icons.reply_rounded, size: 18, color: l.accent),
                    const SizedBox(width: FasanSpace.s),
                    Expanded(
                      child: Text(
                        _editing != null ? (trLang(t.de ? 'de' : 'en', 'collab_ui.editMessage')) : '${trLang(t.de ? 'de' : 'en', 'collab_ui.replyTo')} ${_replyTo!.from == CollabScope.read(context).identity?.pub ? t.you : widget.group.session.nameOf(_replyTo!.from)}: ${_preview(_replyTo!, t.de)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: trLang(t.de ? 'de' : 'en', 'collab_ui.cancel'),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        if (_editing != null) _input.clear();
                        _replyTo = _editing = null;
                      }),
                    ),
                  ]),
                ),
              Row(children: [
              IconButton(tooltip: trLang(t.de ? 'de' : 'en', 'collab_ui.attachAReceipt'), icon: const Icon(Icons.attach_file_rounded), onPressed: _attach),
              if (!widget.group.secret.direct) IconButton(tooltip: trLang(t.de ? 'de' : 'en', 'collab_ui.mentionSomeone'), icon: const Icon(Icons.alternate_email_rounded), onPressed: _mention),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: t.chatHint),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: FasanSpace.s),
              IconButton.filled(tooltip: t.chatSend, icon: const Icon(Icons.send_rounded), onPressed: _send),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Live part of one group: members, notes, chat, invitation (admin), leaving.
class CollabGroupPanel extends StatelessWidget {
  const CollabGroupPanel({super.key, required this.group});

  final CollabGroup group;

  /// One compact row (Nutzer 04.11.: invite and leave were large and doubled): members, notes, chat. Inviting sits in the
  /// app bar, leaving in its menu (leaveGroupFlow).
  @override
  Widget build(BuildContext context) {
    final t = S.of(context), g = group;
    return GroupChangeBuilder(
      group: g,
      // one compact row (notes, chat); the people sit in one section „Personen“ under the receipts (Nutzer 06.11.: one concept)
      builder: (context) {
        final c = CollabScope.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
        final unread = c.unread(g), held = c.held.where((h) => h.group.secret.tag == g.secret.tag).length;
        Widget button(IconData icon, String label, int badge, Widget page) => Expanded(
              child: Material(
                color: l.surfaceAlt,
                borderRadius: BorderRadius.circular(l.radius * 0.6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(l.radius * 0.6),
                  onTap: () => _open(context, page),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: l.minTap),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: Icon(icon, size: 18, color: l.accent)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.labelLarge)),
                    ]),
                  ),
                ),
              ),
            );
        return Padding(
          padding: const EdgeInsets.only(bottom: FasanSpace.m),
          child: Column(children: [
            Row(children: [
              button(Icons.edit_note_rounded, t.notesTitle, 0, NotesScreen(group: g)),
              const SizedBox(width: FasanSpace.s),
              button(Icons.chat_bubble_outline_rounded, trLang(t.de ? 'de' : 'en', 'collab_ui.chat'), unread, ChatScreen(group: g)),
            ]),
            if (held > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(icon: const Icon(Icons.pending_actions_outlined, size: 18), label: Text('${t.heldTitle} · $held'), onPressed: () => _open(context, HeldChangesScreen(group: g))),
              ),
          ]),
        );
      },
    );
  }

  static void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

/// What can be done with one member: link a person, give or take the admin role, trust, remove (with a new group key).
Future<void> memberActions(BuildContext context, CollabGroup g, String pub) async {
  final t = S.of(context), s = CollabScope.read(context);
  final me = s.identity?.pub, isFounder = pub == g.secret.adminPub, isAdm = g.session.admins.contains(pub);
  final trusted = !s.distrusted.contains(pub);
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(g.session.nameOf(pub), style: Theme.of(ctx).textTheme.titleMedium)),
        if (g.isAdmin) ListTile(leading: const Icon(Icons.link_rounded), title: Text(t.linkPerson), onTap: () => Navigator.pop(ctx, 'link')),
        if (g.isAdmin && !isFounder && pub != me)
          ListTile(leading: Icon(isAdm ? Icons.remove_moderator_outlined : Icons.add_moderator_outlined), title: Text(isAdm ? t.takeAdmin : t.giveAdmin), onTap: () => Navigator.pop(ctx, 'admin')),
        if (pub != me)
          SwitchListTile(
            secondary: const Icon(Icons.verified_user_outlined),
            title: Text(t.trustAboutMe),
            subtitle: Text(t.trustAboutMeSub),
            value: trusted,
            onChanged: (v) => Navigator.pop(ctx, v ? 'trust' : 'distrust'),
          ),
        if (g.isAdmin && !isFounder && pub != me)
          ListTile(leading: Icon(Icons.person_remove_outlined, color: Colors.red.shade700), title: Text(t.removeMember), subtitle: Text(t.removeMemberSub), onTap: () => Navigator.pop(ctx, 'remove')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'link':
      await pickPersonFor(context, g, pub);
    case 'admin':
      s.setAdmin(g, pub, !isAdm);
    case 'trust' || 'distrust':
      s.setTrusted(pub, choice == 'trust');
    case 'remove':
      if (await confirmDialog(context, t.removeMember, '${g.session.nameOf(pub)}. ${t.removeMemberSub}', t.removeMember)) {
        await s.removeMember(g, pub);
        if (context.mounted) Navigator.of(context).maybePop(); // the group moved to its new key
      }
  }
}

/// Changes of others that concern me and wait for my answer (trust settings).
class HeldChangesScreen extends StatelessWidget {
  const HeldChangesScreen({super.key, required this.group});

  final CollabGroup group;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), s = CollabScope.of(context), store = StoreScope.of(context);
    final list = s.held.where((h) => h.group.secret.tag == group.secret.tag).toList();
    String what(HeldChange h) {
      final id = h.docId.substring(5);
      final bill = store.bills.where((b) => b.id == id).firstOrNull;
      final kind = h.entry.key == 'meta/payer' ? t.heldPayer : (h.entry.key.startsWith('s/') ? t.heldShare : t.heldPerson);
      return '${group.session.nameOf(h.entry.author)}: $kind · ${bill?.purpose ?? id}';
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.heldTitle)),
      body: ListView(padding: const EdgeInsets.all(FasanSpace.l), children: [
        if (list.isEmpty) Text(t.heldNone),
        for (final h in list)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(FasanSpace.m),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(what(h)),
                const SizedBox(height: FasanSpace.s),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: () => s.decideHeld(h, false), child: Text(t.heldDecline)),
                  FilledButton(onPressed: () => s.decideHeld(h, true), child: Text(t.heldAccept)),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Leave a shared group, after asking. The admin is told that nobody can invite afterwards (handing over the admin role
/// is not built yet, STAND A3).
Future<void> leaveGroupFlow(BuildContext context, CollabGroup g) async {
  final t = S.of(context), s = CollabScope.read(context);
  // only a warning when nobody else can manage the group afterwards (several admins, 04.11.)
  final text = g.isAdmin && g.session.admins.length == 1
      ? '${t.leaveText} ${trLang(t.de ? 'de' : 'en', 'collab_ui.youAreTheOnly')}'
      : t.leaveText;
  if (!await confirmDialog(context, t.leaveGroup, text, t.leaveGroup)) return;
  await s.leave(g);
  if (context.mounted) Navigator.of(context).maybePop();
}

/// One row with an icon, title, optional subtitle and a chevron.
Widget collabTile(BuildContext context, IconData icon, String title, VoidCallback onTap, {String? subtitle}) {
  final l = FasanLook.of(context), tt = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: FasanSpace.s),
    child: Material(
      color: l.surfaceAlt,
      borderRadius: BorderRadius.circular(l.radius * 0.7),
      child: InkWell(
        borderRadius: BorderRadius.circular(l.radius * 0.7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(FasanSpace.m),
          child: Row(children: [
            Icon(icon, color: l.accent),
            const SizedBox(width: FasanSpace.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: tt.titleMedium),
                if (subtitle != null) Text(subtitle, style: tt.bodySmall),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: l.textMuted),
          ]),
        ),
      ),
    ),
  );
}

/// Account: name, public key, the 12 recovery words (on request), restore from words, the relays in use.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final TextEditingController _name = TextEditingController(), _words = TextEditingController();
  bool _showWords = false;

  Timer? _nameTimer;
  late final CollabService _svc = CollabScope.read(context); // dispose() must not look up the tree

  @override
  void initState() {
    super.initState();
    final n = _svc.identity?.name ?? '';
    _name.text = n.isNotEmpty ? n : StoreScope.read(context).me;
  }

  @override
  void dispose() {
    _nameTimer?.cancel();
    if (_name.text.trim().isNotEmpty) _svc.setName(_name.text);
    _name.dispose();
    _words.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final t = S.of(context), s = CollabScope.read(context), messenger = ScaffoldMessenger.of(context);
    final text = _words.text.trim();
    if (text.isEmpty) return;
    if (!await confirmDialog(context, t.accountRestore, t.accountRestoreText, t.accountRestore)) return;
    try {
      if (!mounted || !await ensureConsent(context, s)) return; // the group list comes from the relays
      final n = await s.restoreIdentity(text, name: _name.text.trim());
      _words.clear();
      messenger.showSnackBar(SnackBar(content: Text('${t.accountRestoreOk} ${t.de ? (n == 0 ? 'Keine Gruppen gefunden.' : '$n Gruppen sind zurück.') : (n == 0 ? 'No groups found.' : '$n groups are back.')}')));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.accountRestoreBad)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), s = CollabScope.read(context), tt = Theme.of(context).textTheme;
    final id = s.identity;
    return Scaffold(
      appBar: AppBar(title: Text(t.collabTitle)),
      body: ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
        // trust (Nutzer 04.11.): default everyone; switch on to confirm changes of others about me
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.verified_user_outlined),
          title: TitleHelp(t.confirmAllTitle, t.trustAboutMeSub),
          value: CollabScope.of(context).confirmAll,
          onChanged: (v) => CollabScope.read(context).confirmAll = v,
        ),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: t.accountName, helperText: trLang(t.de ? 'de' : 'en', 'collab_ui.usedEverywhereReceiptsGroups')),
          // saved while typing (04.11.: only Enter saved, leaving the field lost the name)
          onChanged: (v) {
            _nameTimer?.cancel();
            _nameTimer = Timer(const Duration(milliseconds: 600), () => s.setName(v));
          },
          onSubmitted: (v) => s.setName(v),
        ),
        const SizedBox(height: FasanSpace.l),
        if (id == null) Text(t.accountMissing, style: tt.bodyMedium),
        if (id != null) ...[
          Text(t.accountKey, style: tt.titleSmall),
          SelectableText(id.pub, style: tt.bodySmall),
          const SizedBox(height: FasanSpace.l),
          if (id.mnemonic != null) ...[
            Text(t.accountWords, style: tt.titleSmall),
            const SizedBox(height: FasanSpace.s),
            Text(t.accountWordsText, style: tt.bodySmall),
            TextButton(onPressed: () => setState(() => _showWords = !_showWords), child: Text(_showWords ? t.accountHide : t.accountShow)),
            if (_showWords)
              Wrap(spacing: FasanSpace.s, runSpacing: FasanSpace.s, children: [
                for (final (i, w) in id.mnemonic!.split(' ').indexed) Chip(label: Text('${i + 1}. $w')),
              ]),
          ],
        ],
        const Divider(height: FasanSpace.xl),
        // several devices, one account (Nutzer 04.11.): no typing of the 12 words
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.qr_code_2_rounded),
          title: Text(trLang(t.de ? 'de' : 'en', 'collab_ui.signInWithAnother')),
          subtitle: Text(trLang(t.de ? 'de' : 'en', 'collab_ui.thisDeviceShowsA')),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairNewScreen())),
        ),
        if (id != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add_to_home_screen_rounded),
            title: Text(trLang(t.de ? 'de' : 'en', 'collab_ui.addDevice')),
            subtitle: Text(trLang(t.de ? 'de' : 'en', 'collab_ui.scanTheCodeOf')),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairSendScreen())),
          ),
        const Divider(height: FasanSpace.xl),
        Text(t.accountRestore, style: tt.titleSmall),
        const SizedBox(height: FasanSpace.s),
        Text(t.accountRestoreText, style: tt.bodySmall),
        const SizedBox(height: FasanSpace.s),
        TextField(controller: _words, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: t.accountWords)),
        const SizedBox(height: FasanSpace.s),
        OutlinedButton(onPressed: _restore, child: Text(t.accountRestore)),
        const Divider(height: FasanSpace.xl),
        Text(t.relaysTitle, style: tt.titleSmall),
        const SizedBox(height: FasanSpace.s),
        Text(t.relaysText, style: tt.bodySmall),
        for (final r in defaultRelays) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(r)),
      ]),
    );
  }
}

/// The bell on the main pages (Nutzer 04.11.: notifications about joins, messages, new and changed bills).
class ActivityBell extends StatelessWidget {
  const ActivityBell({super.key});

  @override
  Widget build(BuildContext context) {
    final c = CollabScope.of(context), n = c.unseenActivity;
    return IconButton(
      tooltip: trLang(S.of(context).de ? 'de' : 'en', 'collab_ui.news'),
      icon: Badge(isLabelVisible: n > 0, label: Text(n > 99 ? '99+' : '$n'), child: Icon(n > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded)),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ActivityScreen())),
    );
  }
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late final CollabService _c = CollabScope.read(context);
  late final int _seenBefore = _c.prefs?.getInt('collab.activitySeen') ?? 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.markActivitySeen());
  }

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de, l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final c = CollabScope.of(context);
    final list = c.activity;
    IconData icon(ActivityKind k) => switch (k) {
          ActivityKind.joined => Icons.waving_hand_rounded,
          ActivityKind.billNew => Icons.receipt_long_rounded,
          ActivityKind.billChanged => Icons.edit_note_rounded,
          ActivityKind.message => Icons.chat_bubble_rounded,
          ActivityKind.mention => Icons.alternate_email_rounded,
        };
    String when(DateTime d) {
      final m = DateTime.now().difference(d).inMinutes;
      if (m < 1) return trLang(de ? 'de' : 'en', 'collab_ui.now');
      if (m < 60) return trLang(de ? 'de' : 'en', 'collab_ui.minAgo', [m]);
      if (m < 24 * 60) return trLang(de ? 'de' : 'en', 'collab_ui.hAgo', [m ~/ 60]);
      return '${d.day}.${d.month}.';
    }

    void open(Activity a) {
      final g = c.groups[a.group];
      if (g == null) return;
      if (a.kind == ActivityKind.message || g.secret.direct || a.kind == ActivityKind.mention && c.messages(g).any((m) => m.id == a.ref)) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(group: g)));
      } else {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupScreen(name: g.localName, queue: ScanQueue.current ?? ScanQueue(StoreScope.read(context)))));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(trLang(de ? 'de' : 'en', 'collab_ui.news2'))),
      body: list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(FasanSpace.xl),
                child: Text(trLang(de ? 'de' : 'en', 'collab_ui.nothingNewYetJoins'),
                    style: tt.bodyMedium!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: FasanSpace.s),
              itemCount: list.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: l.hairline),
              itemBuilder: (_, i) {
                final a = list[i], fresh = a.at.millisecondsSinceEpoch > _seenBefore;
                return ListTile(
                  leading: CircleAvatar(backgroundColor: l.accent.withValues(alpha: fresh ? 0.25 : 0.1), child: Icon(icon(a.kind), color: l.accent, size: 20)),
                  title: Text(a.shown, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: fresh ? FontWeight.w700 : null)),
                  subtitle: Text(when(a.at)),
                  onTap: () => open(a),
                );
              },
            ),
    );
  }
}
