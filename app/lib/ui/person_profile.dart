// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the profile of a person in a group (Nutzer 12.11., ANFORDERUNGEN 29): one screen for everything that is known about
// somebody and everything that can be done with them. Status (account linked or just a name), balance with its certainty, shared
// groups, what they entered or changed, and the actions that used to hide in two bottom sheets. Later packages add rights levels,
// admin, payment details (docs/VORSCHLAG-12-11-MITGLIEDER-PROFIL.md). MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../collab/service.dart';
import '../l10n.dart';
import '../l10n/tr.dart' show trLang;
import '../l10n_collab.dart';
import '../l10n_groups.dart';
import 'balance_state_ui.dart';
import 'collab_ui.dart';
import 'groups.dart' show groupNaming;
import 'history.dart' show openBillAt, whenShort;
import 'balance_breakdown.dart';
import 'scope.dart';

/// Opens the profile of [person] (a name from the bills) or of the member [pub] in the group [groupName].
void openProfile(BuildContext context, {required String groupName, String? person, String? pub}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonProfileScreen(groupName: groupName, person: person, pub: pub)));
}

class PersonProfileScreen extends StatelessWidget {
  const PersonProfileScreen({super.key, required this.groupName, this.person, this.pub}) : assert(person != null || pub != null);

  final String groupName;
  final String? person, pub;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), lang = t.de ? 'de' : 'en';
    final c = CollabScope.of(context);
    final live = c.groupByLocalName(groupName);
    final body = live == null ? _body(context, null) : GroupChangeBuilder(group: live, builder: (ctx) => _body(ctx, live));
    return Scaffold(appBar: AppBar(title: Text(trLang(lang, 'profile.title'))), body: body);
  }

  /// Who this is: the member key (if an account is linked) and the name to show.
  ({String? pub, String name}) _who(CollabGroup? g) {
    final k = pub ?? (g == null || person == null ? null : g.session.memberOfPerson(person!));
    final name = person ?? (g == null || k == null ? '' : (g.session.personOf(k) ?? g.session.nameOf(k)));
    return (pub: k, name: name);
  }

  Widget _body(BuildContext context, CollabGroup? g) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme, lang = t.de ? 'de' : 'en';
    final c = CollabScope.of(context), store = StoreScope.of(context);
    final who = _who(g);
    final k = who.pub, name = who.name;
    final isMe = k != null && k == c.identity?.pub;
    final (:keyOf, :label) = groupNaming(context, groupName);
    final key = k != null ? '@$k' : name;
    final cents = store.groupBalance(groupName, key: keyOf)[key] ?? 0;
    final gap = store.groupGaps(groupName, key: keyOf)[key];
    final tag = g?.secret.tag;
    final mine = [
      if (k != null && tag != null)
        for (final r in c.changeLog)
          if (r.whoKey == k && r.group == tag) r
    ];
    final shared = [
      for (final n in store.allGroups)
        if (c.peopleOf(n).any((p) => p.trim().toLowerCase() == name.trim().toLowerCase()) || (k != null && (c.groupByLocalName(n)?.session.memberKeys.contains(k) ?? false))) n
    ];
    return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
      Row(children: [
        FasanAvatar(name: name, index: 0, size: 64),
        const SizedBox(width: FasanSpace.l),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, key: const ValueKey('profile-name'), style: tt.headlineSmall),
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(key: const ValueKey('profile-status'), children: [
                  Icon(k != null ? Icons.link_rounded : Icons.badge_outlined, size: 18, color: k != null ? l.accent : l.textMuted),
                  const SizedBox(width: 6),
                  Flexible(child: Text(trLang(lang, k != null ? 'groups.linkedAccount' : 'groups.nameOnly'), style: tt.bodyMedium)),
                ]),
              ),
            if (k == null) Text(trLang(lang, 'groups.nameOnlySub'), style: tt.bodySmall!.copyWith(color: l.textMuted)),
            if (g != null && k != null && g.session.nameOf(k) != name) Text(trLang(lang, 'profile.account', [g.session.nameOf(k)]), style: tt.bodySmall!.copyWith(color: l.textMuted)),
            if (g != null && k != null)
              Text(
                [if (isMe) trLang(lang, 'profile.you'), if (k == g.secret.adminPub) t.founder else if (g.session.admins.contains(k)) t.admin].join(' · '),
                style: tt.bodySmall!.copyWith(color: l.textMuted),
              ),
          ]),
        ),
      ]),
      const SizedBox(height: FasanSpace.l),
      FasanLabel(trLang(lang, 'profile.balance', [groupName])),
      const SizedBox(height: FasanSpace.s),
      Row(key: const ValueKey('profile-balance'), children: [
        Expanded(
          child: gap != null && gap.uncertain
              ? Text(gapReasons(gap, lang).join(' · '), style: tt.bodySmall!.copyWith(color: l.textMuted))
              : Text(trLang(lang, 'groups.groupBalanceHint'), style: tt.bodySmall!.copyWith(color: l.textMuted)),
        ),
        PersonBalance(cents: cents, gap: gap, big: true, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupBreakdownScreen(name: groupName, person: key)))),
      ]),
      const SizedBox(height: FasanSpace.l),
      FasanLabel(trLang(lang, 'profile.sharedGroups')),
      for (final n in shared)
        Container(
          constraints: BoxConstraints(minHeight: l.minTap),
          alignment: Alignment.centerLeft,
          child: Text('$n · ${t.billsCount(store.inGroup(n).where((b) => !b.isTransfer).length)}', style: tt.bodyLarge),
        ),
      const SizedBox(height: FasanSpace.l),
      FasanLabel(trLang(lang, 'profile.changes')),
      if (k == null) Padding(padding: const EdgeInsets.symmetric(vertical: FasanSpace.s), child: Text(trLang(lang, 'profile.changesName'), style: tt.bodyMedium!.copyWith(color: l.textMuted))),
      if (g != null && k != null && mine.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: FasanSpace.s), child: Text(trLang(lang, 'profile.noChanges'), style: tt.bodyMedium!.copyWith(color: l.textMuted))),
      for (final r in mine.take(5))
        InkWell(
          key: ValueKey('profile-change-${r.at.millisecondsSinceEpoch}'),
          onTap: () => openBillAt(context, r.billId, r.lines.firstOrNull?.item),
          child: Container(
            constraints: BoxConstraints(minHeight: l.minTap),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(vertical: FasanSpace.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.lines.isEmpty ? r.title : r.lines.first.text(t.de), style: tt.bodyLarge),
              Text('${r.title} · ${whenShort(context, r.at)}', style: tt.bodySmall!.copyWith(color: l.textMuted)),
            ]),
          ),
        ),
      if (g != null) ...[
        const SizedBox(height: FasanSpace.l),
        _actions(context, g, k, name, isMe),
      ],
    ]);
  }

  Widget _actions(BuildContext context, CollabGroup g, String? k, String name, bool isMe) {
    final t = S.of(context), lang = t.de ? 'de' : 'en', s = CollabScope.read(context);
    final admin = g.isAdmin;
    // a function that cannot be used is shown greyed out with the reason, never left out (Prüfliste G1)
    Widget tile(IconData icon, String title, {String? sub, VoidCallback? onTap, Key? key}) =>
        ListTile(key: key, contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(title), subtitle: sub == null ? null : Text(sub), enabled: onTap != null, onTap: onTap);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      tile(Icons.chat_bubble_outline_rounded, trLang(lang, 'profile.chat'), key: const ValueKey('profile-chat'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(group: g)))),
      if (k == null) ...[
        tile(Icons.person_add_alt_1_outlined, t.inviteFor(name), key: const ValueKey('profile-invite'), sub: admin ? null : trLang(lang, 'profile.onlyAdmins'), onTap: admin ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(group: g, person: name))) : null),
        tile(Icons.link_rounded, trLang(lang, 'profile.linkTo'), key: const ValueKey('profile-link'), sub: admin ? null : trLang(lang, 'profile.onlyAdmins'), onTap: admin ? () => _linkTo(context, g, name) : null),
      ] else ...[
        tile(Icons.link_off_rounded, t.unlink, key: const ValueKey('profile-unlink'), sub: admin ? t.linkedTo(g.session.nameOf(k)) : trLang(lang, 'profile.onlyAdmins'), onTap: admin ? () => s.unlinkPerson(g, k, name) : null),
        if (!isMe || admin) tile(Icons.admin_panel_settings_outlined, trLang(lang, 'profile.manage'), key: const ValueKey('profile-manage'), onTap: () => memberActions(context, g, k)),
      ],
    ]);
  }

  /// Picks the member this name is (the choice that lived in the bottom sheet of the people list).
  Future<void> _linkTo(BuildContext context, CollabGroup g, String name) async {
    final s = CollabScope.read(context), t = S.of(context);
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(name, style: Theme.of(ctx).textTheme.titleMedium)),
          for (final m in g.session.memberKeys)
            ListTile(leading: const Icon(Icons.link_rounded), title: Text(g.session.nameOf(m)), subtitle: Text([t.linkMember, ...g.session.personsOf(m)].join(' · ')), onTap: () => Navigator.pop(ctx, m)),
        ]),
      ),
    );
    if (pick != null) s.linkPerson(g, pick, name);
  }
}
