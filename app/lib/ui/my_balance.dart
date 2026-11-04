// Fasan Split – „Mein Stand“: what I get or owe, in total, per group and per person, and who should pay next
// (Nutzer 04.11.: always visible at a glance; research docs/recherche/2026-11-04-konkurrenz-bedienung-saldo.md §3).
// Only finished bills with a payer count. Me = the name in Einstellungen → „Das bin ich“ and, in live groups, the
// names linked to my member key. MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../model/bill.dart';
import '../model/settle.dart';

class _T {
  const _T(this.de);
  final bool de;
  String get title => de ? 'Mein Stand' : 'My balance';
  String get total => de ? 'Gesamt' : 'Total';
  String get youGet => de ? 'Du bekommst' : 'You get';
  String get youOwe => de ? 'Du schuldest' : 'You owe';
  String get even => de ? 'Alles ausgeglichen' : 'All settled';
  String get perGroup => de ? 'Je Gruppe' : 'Per group';
  String get perPerson => de ? 'Je Person' : 'Per person';
  String get noGroup => de ? 'Ohne Gruppe' : 'No group';
  String get setMe => de ? 'Sag zuerst, wer du bist: Einstellungen → Das bin ich.' : 'First tell who you are: Settings → This is me.';
  String nextPays(String p) => de ? 'Als Nächstes zahlt: $p' : 'Next to pay: $p';
  String getsFrom(String p) => de ? '$p gibt dir' : '$p owes you';
  String owesTo(String p) => de ? 'Du gibst $p' : 'You owe $p';
}

/// My names: the own name and every name linked to my key in a live group.
bool Function(String) myNames(BuildContext context) {
  final store = StoreScope.read(context), collab = CollabScope.read(context);
  final me = store.me.trim().toLowerCase();
  final pub = collab.identity?.pub;
  final linked = <String>{
    if (pub != null)
      for (final g in collab.groups.values) ...g.session.personsOf(pub).map((n) => n.toLowerCase()),
  };
  return (n) => n.trim().toLowerCase() == me && me.isNotEmpty || linked.contains(n.trim().toLowerCase());
}

/// My balance over all bills (+ get, − owe).
int myTotal(BuildContext context) => myDebts(StoreScope.of(context).bills.where((b) => b.trashedAt == null), myNames(context)).values.fold(0, (a, x) => a + x);

/// The round badge on every main page: my initial, ring and amount in the colour of the balance. Tap opens „Mein Stand“.
class MyBalanceBadge extends StatelessWidget {
  const MyBalanceBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final t = _T(S.of(context).de), l = FasanLook.of(context);
    final store = StoreScope.of(context);
    CollabScope.of(context); // rebuild on group changes
    final v = myTotal(context);
    final color = v > 0 ? Colors.green.shade600 : (v < 0 ? Colors.red.shade600 : l.textMuted);
    return Tooltip(
      message: t.title,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBalanceScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
              child: FasanAvatar(name: store.me.isEmpty ? '?' : store.me, index: 0, size: 28),
            ),
            if (v != 0) ...[
              const SizedBox(width: 6),
              Text('${money(v, de: t.de, sign: true)} €', style: Theme.of(context).textTheme.labelLarge!.copyWith(color: color, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    );
  }
}

class MyBalanceScreen extends StatelessWidget {
  const MyBalanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = _T(S.of(context).de), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final store = StoreScope.of(context), collab = CollabScope.of(context);
    final isMe = myNames(context);
    final bills = store.bills.where((b) => b.trashedAt == null).toList();
    final per = myDebts(bills, isMe);
    final total = per.values.fold(0, (a, x) => a + x);
    Color c(int v) => v > 0 ? Colors.green.shade600 : (v < 0 ? Colors.red.shade600 : l.textMuted);
    final groups = [...store.allGroups, null];
    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: ListView(padding: const EdgeInsets.all(FasanSpace.l), children: [
        if (store.me.isEmpty) Padding(padding: const EdgeInsets.only(bottom: FasanSpace.l), child: Text(t.setMe, style: tt.bodyMedium!.copyWith(color: l.textMuted))),
        Text(t.total, style: tt.labelLarge),
        Text(total == 0 ? t.even : '${total > 0 ? t.youGet : t.youOwe} ${money(total.abs(), de: t.de)} €', style: tt.headlineMedium!.copyWith(color: c(total))),
        const SizedBox(height: FasanSpace.xl),
        FasanLabel(t.perGroup),
        for (final g in groups)
          Builder(builder: (context) {
            final inG = bills.where((b) => b.group == g);
            final mine = myDebts(inG, isMe).values.fold(0, (a, x) => a + x);
            final live = g == null ? null : collab.groupByLocalName(g);
            String keyOf(String p) => switch (live?.session.memberOfPerson(p)) { final m? => '@$m', _ => p };
            String label(String k) => k.startsWith('@') ? (live!.session.personOf(k.substring(1)) ?? live.session.nameOf(k.substring(1))) : k;
            final next = g == null ? null : nextPayer(balances(inG, key: keyOf));
            if (mine == 0 && next == null) return const SizedBox.shrink();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(g == null ? Icons.receipt_long_outlined : Icons.folder_outlined, color: l.accent),
              title: Text(g ?? t.noGroup),
              subtitle: next == null ? null : Text(t.nextPays(label(next))),
              trailing: Text(mine == 0 ? '–' : '${money(mine, de: t.de, sign: true)} €', style: tt.titleMedium!.copyWith(color: c(mine))),
            );
          }),
        const SizedBox(height: FasanSpace.l),
        FasanLabel(t.perPerson),
        if (per.isEmpty) Text(t.even, style: tt.bodyMedium),
        for (final e in (per.entries.toList()..sort((a, b) => a.value.compareTo(b.value))))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: FasanAvatar(name: e.key, index: e.key.hashCode % 8, size: 32),
            title: Text(e.value > 0 ? t.getsFrom(e.key) : t.owesTo(e.key)),
            trailing: Text('${money(e.value.abs(), de: t.de)} €', style: tt.titleMedium!.copyWith(color: c(e.value))),
          ),
      ]),
    );
  }
}
