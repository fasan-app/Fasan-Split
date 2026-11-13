// SPDX-License-Identifier: MPL-2.0
// Fasan Split – Dialogs and helpers of the live part: one-time consent, share live, text and confirm dialogs, the plus action of a group. Split out of collab_ui.dart (13.11., Umbau, behaviour unchanged). MPL-2.0
import 'dart:async';

import 'package:flutter/material.dart';

import '../collab/service.dart';
import 'notify_prompt.dart';
import '../l10n.dart';
import '../l10n_collab.dart';
import 'scope.dart';
import '../flows/scan_queue.dart';
import 'groups.dart';
import 'join_screen.dart';

// The screen an invitation link opens lives in join_screen.dart (exported here for the old imports).

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
  if (context.mounted) await askNotificationsOnce(context);
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
Future<void> groupPlusAction(BuildContext context, {ScanQueue? queue, String? preset}) async {
  final t = S.of(context);
  final choice = preset ?? await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
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
