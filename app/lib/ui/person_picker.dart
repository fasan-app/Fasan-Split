// SPDX-License-Identifier: MPL-2.0
// Fasan Split – choose a person for a bill (Nutzer 05.11.): everyone from the group, then friends, then recent names, filtered while
// typing; a new name as the last row. A friend who is not in the bill's group can be invited on the spot (and the invitation taken
// back). MPL-2.0
import 'person_avatar.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import 'scope.dart';
import 'package:fasan_core/bill.dart';
import 'common.dart';
import 'flow.dart' show addPersonTo;

enum PersonSource { group, friend, recent }

class PickedPerson {
  const PickedPerson(this.name, {this.pub, this.source = PersonSource.recent, this.isNew = false});

  final String name;

  /// Member key when the person is a friend or group member of this phone's groups.
  final String? pub;
  final PersonSource source;
  final bool isNew;
}

class _Candidate {
  const _Candidate(this.name, this.pub, this.source);

  final String name;
  final String? pub;
  final PersonSource source;
}

/// Lower case without accents, so „jose“ finds „José“ and „muller“ finds „Müller“.
String _norm(String s) {
  const from = 'äöüßáàâãéèêëíìîïóòôõúùûçñ';
  const to = 'aousaaaaeeeeiiiioooouuucn';
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(c == 'ß' ? 'ss' : (i >= 0 ? to[i] : c));
  }
  return b.toString().trim();
}

/// Everyone who can be added to [b]: group first, then friends, then recent names; nobody twice, nobody already in the bill.
List<_Candidate> _candidates(BuildContext context, Bill b) {
  final collab = CollabScope.read(context), store = StoreScope.read(context);
  final group = b.group == null ? null : collab.groupByLocalName(b.group!);
  final seen = <String>{for (final p in b.ps) _norm(p.name)};
  final out = <_Candidate>[];
  void add(String name, String? pub, PersonSource s) {
    final k = _norm(name);
    if (k.isEmpty || name.trim() == '—' || !seen.add(k)) return;
    out.add(_Candidate(name.trim(), pub, s));
  }

  final me = (collab.identity?.name ?? store.me).trim();
  if (b.group != null) {
    final pubByName = <String, String>{};
    if (group != null) {
      for (final k in group.session.memberKeys) {
        pubByName[_norm(group.session.personOf(k) ?? group.session.nameOf(k))] = k;
      }
    }
    if (me.isNotEmpty) add(me, collab.identity?.pub, PersonSource.group);
    for (final n in collab.peopleOf(b.group!)) {
      add(n, pubByName[_norm(n)], PersonSource.group);
    }
  } else if (me.isNotEmpty) {
    add(me, collab.identity?.pub, PersonSource.recent);
  }
  for (final e in collab.memberFriends.entries) {
    add(e.value, e.key, PersonSource.friend);
  }
  for (final n in store.recentNames) {
    add(n, null, PersonSource.recent);
  }
  return out;
}

/// The sheet: returns the chosen or newly typed person, or null.
Future<PickedPerson?> pickPerson(BuildContext context, Bill b) {
  final all = _candidates(context, b);
  return showModalBottomSheet<PickedPerson>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PickerSheet(all: all, hasGroup: b.group != null),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.all, required this.hasGroup});

  final List<_Candidate> all;
  final bool hasGroup;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// With a text: names that start with it, then names that contain it (at most 8: short lists are easier on a phone). Without:
  /// the whole group and a few friends and recent names.
  List<_Candidate> get _shown {
    final n = _norm(_q.text);
    if (n.isEmpty) {
      var friends = 0, recent = 0;
      return [
        for (final c in widget.all)
          if (c.source == PersonSource.group || (c.source == PersonSource.friend && friends++ < 6) || (c.source == PersonSource.recent && recent++ < 6)) c
      ];
    }
    final starts = [for (final c in widget.all) if (_norm(c.name).startsWith(n)) c];
    final has = [for (final c in widget.all) if (!_norm(c.name).startsWith(n) && _norm(c.name).contains(n)) c];
    return [...starts, ...has].take(8).toList();
  }

  bool get _exact => widget.all.any((c) => _norm(c.name) == _norm(_q.text));

  void _pick(_Candidate c) => Navigator.pop(context, PickedPerson(c.name, pub: c.pub, source: c.source));

  void _submit() {
    final shown = _shown;
    final t = _q.text.trim();
    if (shown.isNotEmpty) {
      _pick(shown.first);
    } else if (t.isNotEmpty) {
      Navigator.pop(context, PickedPerson(t, isNew: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final shown = _shown, text = _q.text.trim();
    String heading(PersonSource s) => switch (s) {
          PersonSource.group => context.tr('picker.group'),
          PersonSource.friend => context.tr('picker.friends'),
          PersonSource.recent => context.tr('picker.recent'),
        };
    final rows = <Widget>[];
    PersonSource? last;
    for (final c in shown) {
      // headings only without a filter (with one, the list is short and a heading per row is noise)
      if (text.isEmpty && c.source != last && (widget.hasGroup || c.source != PersonSource.recent || shown.any((x) => x.source != c.source))) {
        rows.add(Padding(padding: const EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, FasanSpace.xs), child: FasanLabel(heading(c.source))));
      }
      last = c.source;
      rows.add(ListTile(
        key: ValueKey('pick-${c.name}'),
        leading: PersonAvatar(name: c.name, index: c.name.hashCode.abs() % 8, size: 32),
        title: Text(c.name),
        subtitle: widget.hasGroup && c.source == PersonSource.friend ? Text(context.tr('picker.notInGroup'), style: tt.bodySmall!.copyWith(color: l.textMuted)) : null,
        onTap: () => _pick(c),
      ));
    }
    if (text.isNotEmpty && !_exact) {
      rows.add(ListTile(
        key: const ValueKey('pick-new'),
        leading: const CircleAvatar(radius: 16, child: Icon(Icons.person_add_alt_1_rounded, size: 18)),
        title: Text(context.tr('picker.new', [text])),
        onTap: () => Navigator.pop(context, PickedPerson(text, isNew: true)),
      ));
    }
    if (rows.isEmpty) rows.add(Padding(padding: const EdgeInsets.all(FasanSpace.l), child: Text(context.tr('picker.none'), style: tt.bodyMedium)));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 0),
          child: TextField(
            controller: _q,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: context.tr('picker.search'), prefixIcon: const Icon(Icons.search_rounded)),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ),
        Flexible(child: ListView(shrinkWrap: true, children: rows)),
      ]),
    );
  }
}

/// Picks a person and adds them to the bill; returns their index, or null. A friend who is not in the bill's group is offered an
/// invitation to it (sent straight to them, no confirmation needed here, and it can be taken back).
Future<int?> addPersonWithPicker(BuildContext context, Bill b) async {
  final picked = await pickPerson(context, b);
  if (picked == null || !context.mounted) return null;
  addPersonTo(b, picked.name);
  final idx = b.ps.indexWhere((p) => p.name.toLowerCase() == picked.name.toLowerCase());
  if (picked.source == PersonSource.friend && picked.pub != null && b.group != null) {
    await _offerInvitation(context, b, picked);
  }
  return idx < 0 ? null : idx;
}

Future<void> _offerInvitation(BuildContext context, Bill b, PickedPerson p) async {
  final collab = CollabScope.read(context);
  final g = collab.groupByLocalName(b.group!);
  if (g == null || g.secret.direct || g.session.memberKeys.contains(p.pub)) return;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('invite.askTitle', [p.name])),
      content: Text(ctx.tr('invite.askText', [p.name, g.localName])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('invite.notNow'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('invite.send'))),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  final message = context.tr('invite.message', [g.localName]);
  final sent = await collab.inviteFriendToGroup(g, p.pub!, p.name, message: message);
  if (!context.mounted) return;
  if (sent == null) {
    showNote(context, context.tr('invite.cannot'));
    return;
  }
  showNote(
    context,
    context.tr('invite.sent', [p.name]),
    actionLabel: context.tr('invite.undo'),
    duration: const Duration(seconds: 10),
    onAction: () async {
      await collab.undoFriendInvite(sent);
      if (context.mounted) showNote(context, context.tr('invite.withdrawn', [p.name]));
    },
  );
}
