// Fasan Split – screens of the collaboration: joining, live sharing with the one-time consent, invitations, members,
// notes, chat and the account. The screens talk only to CollabService. Public relays are contacted only after the user
// has agreed in the consent dialog, and tests never reach them (they use MemoryRelay). MPL-2.0
import 'dart:async';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zxing2/qrcode.dart';

import '../collab/group.dart';
import '../collab/notes.dart';
import '../collab/service.dart';
import '../l10n.dart';
import '../l10n_collab.dart';
import '../l10n_web.dart';
import '../web_platform.dart';
import '../l10n_groups.dart';
import '../main.dart';
import '../state/scan_queue.dart';
import 'groups.dart';

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

/// Opens an invitation link (typed, pasted or from the link that started the app).
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, this.prefill});

  final String? prefill;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  late final TextEditingController _link = TextEditingController(text: widget.prefill ?? '');
  final TextEditingController _name = TextEditingController();
  String? _error;
  bool _busy = false, _sent = false;

  @override
  void initState() {
    super.initState();
    _name.text = CollabScope.read(context).identity?.name ?? '';
  }

  @override
  void dispose() {
    _link.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) _link.text = d!.text!.trim();
  }

  Future<void> _send() async {
    final t = S.of(context), s = CollabScope.read(context);
    final text = _link.text.trim();
    if (text.isEmpty) return;
    if (!await ensureConsent(context, s) || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await s.join(text, _name.text);
    if (!mounted) return;
    final msg = switch (err) {
      null => null,
      'invalid' => t.joinBad,
      'expired' => t.joinExpired,
      'member' => t.joinMember,
      _ => t.joinNoSend,
    };
    setState(() {
      _busy = false;
      _sent = err == null;
      _error = msg;
    });
    if (err == null) clearJoinCode(); // the request is out: the code may leave the tab now
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.joinGroup)),
      body: ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
        if (kIsWeb) const _WebAppHint(),
        Text(t.joinText, style: tt.bodyMedium),
        const SizedBox(height: FasanSpace.l),
        TextField(controller: _link, minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: t.joinLink)),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(icon: const Icon(Icons.content_paste_rounded), label: Text(t.joinPaste), onPressed: _paste)),
        const SizedBox(height: FasanSpace.s),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: t.joinName)),
        const SizedBox(height: FasanSpace.l),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: FasanSpace.m), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_sent) Padding(padding: const EdgeInsets.only(bottom: FasanSpace.m), child: Text(t.joinSent, style: tt.bodyMedium)),
        FilledButton(onPressed: _busy || _sent ? null : _send, child: Text(t.joinSend)),
      ]),
    );
  }
}

/// Admin: choose which person of the group's bills a member is (or unlink). Names come from the bills and the people
/// added by hand (BillStore.groupMembers).
Future<void> pickPersonFor(BuildContext context, CollabGroup g, String pub) async {
  final t = S.of(context), s = CollabScope.read(context);
  final people = StoreScope.read(context).groupMembers(g.localName);
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

/// Browser only: says what the web app can do and offers the Android app. „In der App öffnen“ uses the old scheme
/// fasansplit://join, which the installed app always handles (the https App Link needs assetlinks.json, docs/WEB.md).
class _WebAppHint extends StatelessWidget {
  const _WebAppHint();

  static final _apk = Uri.parse('https://github.com/fasan-app/Fasan-Split/releases/tag/neueste');

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context);
    final code = context.findAncestorStateOfType<_JoinScreenState>()?._link.text ?? '';
    final i = code.indexOf('#');
    return Container(
      margin: const EdgeInsets.only(bottom: FasanSpace.l),
      padding: const EdgeInsets.all(FasanSpace.m),
      decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.7)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.webHint, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: FasanSpace.s),
        Wrap(spacing: FasanSpace.s, runSpacing: FasanSpace.s, children: [
          if (i >= 0)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(t.webOpenApp),
              onPressed: () => launchUrl(Uri.parse('fasansplit://join${code.substring(i)}')),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.android_rounded),
            label: Text(t.webGetApp),
            onPressed: () => launchUrl(_apk, mode: LaunchMode.externalApplication),
          ),
        ]),
      ]),
    );
  }
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

  Invitations? get _inv => widget.group.invitations;

  @override
  void initState() {
    super.initState();
    _sub = _inv?.changes.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _create() => setState(() => _current = _inv!.create(person: widget.person));

  void _revoke() {
    _inv?.revokeAll();
    setState(() => _current = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).inviteRevoked)));
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme, s = CollabScope.read(context);
    final g = widget.group, inv = _inv, link = _current?.link;
    final requests = inv?.pending.values.toList() ?? const <JoinRequest>[];
    return Scaffold(
      appBar: AppBar(title: Text(widget.person == null ? t.invite : t.inviteFor(widget.person!))),
      body: ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
        Text(t.inviteLive(g.localName), style: tt.bodyMedium),
        const SizedBox(height: FasanSpace.l),
        if (link == null) FilledButton.icon(icon: const Icon(Icons.add_link_rounded), label: Text(t.inviteCreate), onPressed: inv == null ? null : _create),
        if (link != null) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(l.radius * 0.7), border: Border.all(color: l.hairline)),
              child: SizedBox.square(dimension: 220, child: CustomPaint(painter: _QrPainter(Encoder.encode(link, ErrorCorrectionLevel.m)))),
            ),
          ),
          const SizedBox(height: FasanSpace.m),
          SelectableText(link, style: tt.bodySmall),
          const SizedBox(height: FasanSpace.m),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: Text(t.inviteCopy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.inviteCopied)));
                },
              ),
            ),
            const SizedBox(width: FasanSpace.s),
            Expanded(child: FilledButton.icon(icon: const Icon(Icons.ios_share_rounded), label: Text(t.inviteShare), onPressed: () => SharePlus.instance.share(ShareParams(text: link)))),
          ]),
          TextButton(onPressed: _create, child: Text(t.inviteCreate)),
        ],
        const SizedBox(height: FasanSpace.l),
        Text(t.requests, style: tt.titleMedium),
        if (requests.isEmpty) Padding(padding: const EdgeInsets.only(top: FasanSpace.s), child: Text(t.noRequests, style: tt.bodySmall)),
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
        const SizedBox(height: FasanSpace.l),
        if (inv != null) TextButton.icon(icon: const Icon(Icons.link_off_rounded), label: Text(t.inviteRevoke), onPressed: _revoke),
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
                onTap: k == me && !group.isAdmin ? null : () => _memberActions(context, group, k),
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
                subtitle: Text(n.text.split('\n').first, maxLines: 1, overflow: TextOverflow.ellipsis),
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

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    CollabScope.read(context).sendMessage(widget.group, text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.chatTitle)),
      body: Column(children: [
        Expanded(
          child: GroupChangeBuilder(
            group: widget.group,
            docId: GroupSession.chat,
            builder: (context) {
              final s = CollabScope.read(context), me = s.identity?.pub;
              final msgs = s.messages(widget.group);
              if (msgs.isEmpty) {
                return Center(child: Padding(padding: const EdgeInsets.all(FasanSpace.l), child: Text(t.chatEmpty, style: tt.bodyMedium, textAlign: TextAlign.center)));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(FasanSpace.m),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m = msgs[i], mine = m.from == me;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: FasanSpace.s),
                      padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: FasanSpace.s),
                      decoration: BoxDecoration(color: mine ? l.accent.withValues(alpha: 0.18) : l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.6)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(mine ? t.you : widget.group.session.nameOf(m.from), style: tt.labelSmall),
                        Text(m.text, style: tt.bodyMedium),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(FasanSpace.m, 0, FasanSpace.m, FasanSpace.s),
            child: Row(children: [
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
      builder: (context) => Padding(
        padding: const EdgeInsets.only(bottom: FasanSpace.m),
        child: Wrap(spacing: FasanSpace.s, runSpacing: FasanSpace.s, children: [
          ActionChip(avatar: const Icon(Icons.group_outlined, size: 18), label: Text('${t.membersTitle} · ${g.session.memberKeys.length}'), onPressed: () => _open(context, MembersScreen(group: g))),
          ActionChip(avatar: const Icon(Icons.edit_note_rounded, size: 18), label: Text(t.notesTitle), onPressed: () => _open(context, NotesScreen(group: g))),
          ActionChip(avatar: const Icon(Icons.chat_bubble_outline_rounded, size: 18), label: Text(t.chatTitle), onPressed: () => _open(context, ChatScreen(group: g))),
          if (CollabScope.of(context).held.where((h) => h.group.secret.tag == g.secret.tag).length case final n when n > 0)
            ActionChip(avatar: const Icon(Icons.pending_actions_outlined, size: 18), label: Text('${t.heldTitle} · $n'), onPressed: () => _open(context, HeldChangesScreen(group: g))),
        ]),
      ),
    );
  }

  static void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

/// What can be done with one member: link a person, give or take the admin role, trust, remove (with a new group key).
Future<void> _memberActions(BuildContext context, CollabGroup g, String pub) async {
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
      ? '${t.leaveText} ${t.de ? 'Du bist die einzige Verwaltung: gib die Verwaltung vorher in „Mitglieder“ weiter, sonst kann niemand mehr einladen.' : 'You are the only admin: hand it over in “Members” first, or nobody can invite any more.'}'
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

  @override
  void initState() {
    super.initState();
    _name.text = CollabScope.read(context).identity?.name ?? '';
  }

  @override
  void dispose() {
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
          title: Text(t.confirmAllTitle),
          subtitle: Text(t.trustAboutMeSub),
          value: CollabScope.of(context).confirmAll,
          onChanged: (v) => CollabScope.read(context).confirmAll = v,
        ),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: t.accountName),
          onSubmitted: (v) => s.setName(v.trim()),
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
