// SPDX-License-Identifier: MPL-2.0
// Fasan Split – Members list, group notes and the note editor. Split out of collab_ui.dart (13.11., Umbau, behaviour unchanged). MPL-2.0
import 'person_profile.dart';
import '../l10n/tr.dart';
import 'dart:async';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../collab/group.dart';
import '../collab/notes.dart';
import '../collab/service.dart';
import '../l10n.dart';
import '../l10n_collab.dart';
import '../l10n_groups.dart';
import 'scope.dart';
import 'marquee_text.dart';
import 'collab_dialogs.dart';
// The screen an invitation link opens lives in join_screen.dart (exported here for the old imports).

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
            if (!group.secret.direct)
              SwitchListTile(
                key: const ValueKey('hide-new-bills'),
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('vis.defaultTitle')),
                subtitle: Text(context.tr('vis.defaultSub')),
                value: s.hidesNewBills(group),
                onChanged: (v) => s.setHideNewBills(group, v),
              ),
            SwitchListTile(
              key: const ValueKey('all-admins'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('admin.allTitle')),
              subtitle: Text(context.tr(me == admin ? 'admin.allSub' : 'admin.allSubOnlyFounder')),
              value: group.session.allAdmins,
              onChanged: me == admin ? (v) => s.setAllAdmins(group, v) : null,
            ),
            for (final k in keys)
              ListTile(
                leading: CircleAvatar(child: Text(group.session.nameOf(k).characters.first.toUpperCase())),
                title: Text(k == me ? '${group.session.nameOf(k)} (${t.you})' : group.session.nameOf(k)),
                subtitle: Text([
                  k == admin ? t.founder : (group.session.admins.contains(k) ? t.admin : k.substring(0, 12)),
                  if (group.session.personsOf(k) case final ps when ps.isNotEmpty) t.linkedTo(ps.join(', ')),
                  if (s.distrusted.contains(k)) t.confirmsAboutMe,
                  if (s.blocked.contains(k)) trLang(t.de ? 'de' : 'en', 'trust.blockShort'),
                ].join(' · ')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openProfile(context, groupName: group.localName, pub: k),
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
