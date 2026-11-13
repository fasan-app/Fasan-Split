// SPDX-License-Identifier: MPL-2.0
// Fasan Split – Live part of one group: panel, member actions, held changes, leaving. Split out of collab_ui.dart (13.11., Umbau, behaviour unchanged). MPL-2.0
import '../l10n/tr.dart';
import 'dart:async';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../collab/service.dart';
import '../l10n.dart';
import '../l10n_collab.dart';
import '../l10n_groups.dart';
import 'scope.dart';
import 'shape_tokens.dart';
import 'collab_dialogs.dart';
import 'collab_invite.dart';
import 'collab_notes.dart';
import 'collab_chat.dart';
// The screen an invitation link opens lives in join_screen.dart (exported here for the old imports).

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
                borderRadius: BorderRadius.circular(l.rInner),
                child: InkWell(
                  borderRadius: BorderRadius.circular(l.rInner),
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
  final trustLevel = s.trustOf(pub), de = S.of(context).de;
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(g.session.nameOf(pub), style: Theme.of(ctx).textTheme.titleMedium)),
        if (g.isAdmin) ListTile(leading: const Icon(Icons.link_rounded), title: Text(t.linkPerson), onTap: () => Navigator.pop(ctx, 'link')),
        if (g.isAdmin && !isFounder && pub != me)
          ListTile(leading: Icon(isAdm ? Icons.remove_moderator_outlined : Icons.add_moderator_outlined), title: Text(isAdm ? t.takeAdmin : t.giveAdmin), onTap: () => Navigator.pop(ctx, 'admin')),
        if (pub != me)
          ListTile(
            key: const ValueKey('member-trust'),
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(t.trustAboutMe),
            subtitle: Text(trLang(de ? 'de' : 'en', 'trust.${trustLevel.name}')),
            onTap: () => Navigator.pop(ctx, 'level'),
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
    case 'level':
      await pickTrust(context, s, pub);
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
  await s.leave(g, announce: true);
  if (context.mounted) Navigator.of(context).maybePop();
}

/// One row with an icon, title, optional subtitle and a chevron.
Widget collabTile(BuildContext context, IconData icon, String title, VoidCallback onTap, {String? subtitle}) {
  final l = FasanLook.of(context), tt = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: FasanSpace.s),
    child: Material(
      color: l.surfaceAlt,
      borderRadius: BorderRadius.circular(l.rCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(l.rCard),
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

/// Asks which stand-in level [pub] gets for entries about me (full, confirm, block) and stores the choice (Nutzer 12.11., Paket 4).
Future<void> pickTrust(BuildContext context, CollabService s, String pub) async {
  final t = S.of(context), de = t.de, trustLevel = s.trustOf(pub);
  final pick = await showModalBottomSheet<TrustLevel>(
    context: context,
    builder: (ctx) => SafeArea(
      child: RadioGroup<TrustLevel>(
        groupValue: trustLevel,
        onChanged: (v) => Navigator.pop(ctx, v),
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(t.trustAboutMe, style: Theme.of(ctx).textTheme.titleMedium), subtitle: Text(t.trustAboutMeSub)),
          for (final l in TrustLevel.values)
            RadioListTile<TrustLevel>(
              key: ValueKey('trust-${l.name}'),
              value: l,
              title: Text(trLang(de ? 'de' : 'en', 'trust.${l.name}')),
              subtitle: Text(trLang(de ? 'de' : 'en', 'trust.${l.name}Sub')),
            ),
        ]),
      ),
    ),
  );
  if (pick != null) s.setTrust(pub, pick);
}
