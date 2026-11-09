// SPDX-License-Identifier: MPL-2.0
// Fasan Split – „Mein Stand“: what I get or owe, in total, per group and per person. No „who pays next“ (Nutzer 04.11.:
// the group may be incomplete and a program telling people to pay feels wrong; always visible at a glance; research docs/recherche/2026-11-04-konkurrenz-bedienung-saldo.md §3).
// Only finished bills with a payer count. Me = the name in Einstellungen → „Das bin ich“ and, in live groups, the
// names linked to my member key. MPL-2.0
import '../l10n/tr.dart' show trLang;
import 'dart:async';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import 'scope.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_core/settle.dart';
import 'backup_ui.dart';
import 'balance_breakdown.dart';
import 'collab_ui.dart';
import 'common.dart';
import 'group_header.dart' show HelpButton;
import 'groups.dart';
import 'history.dart';
import 'pairing_ui.dart';
import 'pay_ui.dart';
import 'settings_screen.dart';

class _T {
  const _T(this.de);
  final bool de;
  String get title => trLang(de ? 'de' : 'en', 'my_balance.myBalance');
  String get total => trLang(de ? 'de' : 'en', 'my_balance.total');
  String get youGet => trLang(de ? 'de' : 'en', 'my_balance.youGet');
  String get youOwe => trLang(de ? 'de' : 'en', 'my_balance.youOwe');
  String get even => trLang(de ? 'de' : 'en', 'my_balance.allSettled');
  String get perGroup => trLang(de ? 'de' : 'en', 'my_balance.perGroup');
  String get perPerson => trLang(de ? 'de' : 'en', 'my_balance.perPerson');
  String get noGroup => trLang(de ? 'de' : 'en', 'my_balance.noGroup');
  String get setMe => trLang(de ? 'de' : 'en', 'my_balance.firstTellWhoYou');
  String getsFrom(String p) => trLang(de ? 'de' : 'en', 'my_balance.owesYou', [p]);
  String owesTo(String p) => trLang(de ? 'de' : 'en', 'my_balance.youOwe2', [p]);
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
/// Includes the provisional part of unfinished bills (Nutzer 07.11.: confirmed and provisional together, the provisional part shown paler).
int myTotal(BuildContext context) => myConfirmed(context) + myProvisionalTotal(context);

int myConfirmed(BuildContext context) => myDebts(StoreScope.of(context).bills.where((b) => b.trashedAt == null), myNames(context)).values.fold(0, (a, x) => a + x);

int myProvisionalTotal(BuildContext context, {String? group, bool anyGroup = true}) =>
    myProvisional(StoreScope.of(context).bills.where((b) => b.trashedAt == null && (anyGroup || b.group == group)), myNames(context)).values.fold(0, (a, x) => a + x);

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
      message: trLang(t.de ? 'de' : 'en', 'my_balance.profile'),
      child: InkWell(
        customBorder: const StadiumBorder(),
        // the whole profile behind the avatar (Nutzer 04.11.: not hidden in the menu)
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
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
              Text('${money(v, de: t.de, sign: true)} ${signOf(context)}', style: Theme.of(context).textTheme.labelLarge!.copyWith(color: color, fontWeight: FontWeight.w700)),
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
    final store = StoreScope.of(context);
    CollabScope.of(context); // rebuild on group changes
    final isMe = myNames(context);
    final bills = store.bills.where((b) => b.trashedAt == null).toList();
    final per = myDebts(bills, isMe);
    final prov = myProvisional(bills, isMe);
    final provTotal = prov.values.fold(0, (a, x) => a + x);
    final total = per.values.fold(0, (a, x) => a + x) + provTotal;
    Color c(int v) => v > 0 ? Colors.green.shade600 : (v < 0 ? Colors.red.shade600 : l.textMuted);
    final groups = [...store.allGroups, null];
    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: ListView(padding: const EdgeInsets.all(FasanSpace.l), children: [
        if (store.me.isEmpty) Padding(padding: const EdgeInsets.only(bottom: FasanSpace.l), child: Text(t.setMe, style: tt.bodyMedium!.copyWith(color: l.textMuted))),
        Text(t.total, style: tt.labelLarge),
        Text(total == 0 ? t.even : '${total > 0 ? t.youGet : t.youOwe} ${money(total.abs(), de: t.de)} ${signOf(context)}', style: tt.headlineMedium!.copyWith(color: c(total))),
        if (provTotal != 0)
          Padding(
            padding: const EdgeInsets.only(top: FasanSpace.xs),
            child: Text('${trLang(t.de ? 'de' : 'en', 'my_balance.provisional', [money(provTotal, de: t.de, sign: true)])} ${signOf(context)}', style: tt.bodyMedium!.copyWith(color: c(provTotal).withValues(alpha: 0.7))),
          ),
        const SizedBox(height: FasanSpace.s),
        TextButton.icon(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
          icon: const Icon(Icons.calculate_outlined),
          label: Text(trLang(t.de ? 'de' : 'en', 'breakdown.myTitle')),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBreakdownScreen())),
        ),
        const SizedBox(height: FasanSpace.l),
        FasanLabel(t.perGroup),
        for (final g in groups)
          Builder(builder: (context) {
            final inG = bills.where((b) => b.group == g);
            final sure = myDebts(inG, isMe).values.fold(0, (a, x) => a + x);
            final soft = myProvisional(inG, isMe).values.fold(0, (a, x) => a + x);
            final mine = sure + soft;
            if (mine == 0) return const SizedBox.shrink();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(g == null ? Icons.receipt_long_outlined : Icons.folder_outlined, color: l.accent),
              title: Text(g ?? t.noGroup),
              trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${money(mine, de: t.de, sign: true)} ${signOf(context)}', style: tt.titleMedium!.copyWith(color: c(mine))),
                if (soft != 0) Text(trLang(t.de ? 'de' : 'en', 'my_balance.provisionalShort', [money(soft, de: t.de, sign: true)]), style: tt.bodySmall!.copyWith(color: c(soft).withValues(alpha: 0.7))),
              ]),
            );
          }),
        const SizedBox(height: FasanSpace.l),
        FasanLabel(t.perPerson),
        if (per.isEmpty && prov.isEmpty) Text(t.even, style: tt.bodyMedium),
        for (final e in (per.entries.toList()..sort((a, b) => a.value.compareTo(b.value))))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: FasanAvatar(name: e.key, index: e.key.hashCode % 8, size: 32),
            title: Text(e.value > 0 ? t.getsFrom(e.key) : t.owesTo(e.key)),
            trailing: Text('${money(e.value.abs(), de: t.de)} ${signOf(context)}', style: tt.titleMedium!.copyWith(color: c(e.value))),
          ),
        // provisional: unfinished bills, paler; recipient '' = nobody is known to have paid yet
        for (final e in (prov.entries.toList()..sort((a, b) => a.value.compareTo(b.value))))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Opacity(opacity: 0.6, child: e.key.isEmpty ? const Icon(Icons.help_outline_rounded) : FasanAvatar(name: e.key, index: e.key.hashCode % 8, size: 32)),
            title: Text(
              e.key.isEmpty ? trLang(t.de ? 'de' : 'en', 'my_balance.provisionalOpenPayer') : trLang(t.de ? 'de' : 'en', e.value > 0 ? 'my_balance.provisionalGets' : 'my_balance.provisionalOwes', [e.key]),
              style: tt.bodyLarge!.copyWith(color: l.textMuted),
            ),
            trailing: Text('${money(e.value.abs(), de: t.de)} ${signOf(context)}', style: tt.titleMedium!.copyWith(color: c(e.value).withValues(alpha: 0.7))),
          ),
      ]),
    );
  }
}

/// Profile (Nutzer 04.11.): who I am, my balance, account and devices, friends – one tap from every main page.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _name = TextEditingController();
  Timer? _timer;
  // looked up once: dispose() saves the name and must not look up the tree
  late final _store = StoreScope.read(context);
  late final _collab = CollabScope.read(context);

  @override
  void initState() {
    super.initState();
    final n = _collab.identity?.name ?? '';
    _name.text = n.isNotEmpty ? n : _store.me;
  }

  @override
  void dispose() {
    _timer?.cancel();
    final n = _name.text.trim(), store = _store, collab = _collab;
    // after the frame: saving notifies listeners, which is not allowed while the tree is torn down
    if (n.isNotEmpty) {
      scheduleMicrotask(() {
        store.me = n;
        collab.setName(n);
      });
    }
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    _store.me = n;
    _collab.setName(n);
  }

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de, t = _T(de), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final collab = CollabScope.of(context);
    final total = myTotal(context);
    Color c(int v) => v > 0 ? Colors.green.shade600 : (v < 0 ? Colors.red.shade600 : l.textMuted);
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    // compact rows (Nutzer 09.11.): symbol, short title, state or chevron; the longer text sits behind the „?“ and never moves the row
    Widget tile(IconData i, String title, String? sub, VoidCallback onTap) => SizedBox(
          height: 52,
          child: InkWell(
            onTap: onTap,
            child: Row(children: [
              Icon(i, color: l.accent, size: 22),
              const SizedBox(width: FasanSpace.m),
              Expanded(child: Text(title, style: tt.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (sub != null) HelpButton(title: title, body: sub),
              Icon(Icons.chevron_right_rounded, color: l.textMuted),
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(trLang(de ? 'de' : 'en', 'my_balance.profile2')),
        // settings live inside the profile, top right (Nutzer 09.11.)
        actions: [IconButton(tooltip: trLang(de ? 'de' : 'en', 'my_balance.settings'), icon: const Icon(Icons.settings_outlined), onPressed: () => open(const SettingsScreen()))],
      ),
      body: ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
        Row(children: [
          ListenableBuilder(listenable: _name, builder: (context, _) => FasanAvatar(name: _name.text.trim().isEmpty ? '?' : _name.text.trim(), index: 0, size: 64)),
          const SizedBox(width: FasanSpace.m),
          Expanded(
            child: TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              style: tt.titleLarge,
              decoration: InputDecoration(labelText: trLang(de ? 'de' : 'en', 'my_balance.yourName')),
              onChanged: (_) {
                _timer?.cancel();
                _timer = Timer(const Duration(milliseconds: 600), _save);
              },
              onSubmitted: (_) => _save(),
            ),
          ),
        ]),
        const SizedBox(height: FasanSpace.l),
        Material(
          color: l.surfaceAlt,
          borderRadius: BorderRadius.circular(l.radius * 0.7),
          child: InkWell(
            borderRadius: BorderRadius.circular(l.radius * 0.7),
            onTap: () => open(const MyBalanceScreen()),
            child: Padding(
              padding: const EdgeInsets.all(FasanSpace.m),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title, style: tt.labelLarge!.copyWith(color: l.textMuted)),
                    Text(total == 0 ? t.even : '${total > 0 ? t.youGet : t.youOwe} ${money(total.abs(), de: de)} ${signOf(context)}', style: tt.titleLarge!.copyWith(color: c(total))),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: l.textMuted),
              ]),
            ),
          ),
        ),
        const SizedBox(height: FasanSpace.s),
        // stand-in (Nutzer 09.11.): may others change and enter things for me? On by default; off = their changes about me wait for me
        SizedBox(
          key: const ValueKey('profile-standin'),
          height: 52,
          child: Row(children: [
            Icon(Icons.group_add_outlined, color: l.accent, size: 22),
            const SizedBox(width: FasanSpace.m),
            Expanded(child: Text(trLang(de ? 'de' : 'en', 'profile.standIn'), style: tt.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
            HelpButton(title: trLang(de ? 'de' : 'en', 'profile.standIn'), body: trLang(de ? 'de' : 'en', 'profile.standInHelp')),
            Switch(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, value: !collab.confirmAll, onChanged: (v) => CollabScope.read(context).confirmAll = !v),
          ]),
        ),
        const SizedBox(height: FasanSpace.s),
        tile(Icons.history_rounded, trLang(de ? 'de' : 'en', 'history.title'), trLang(de ? 'de' : 'en', 'history.profileSub'), () => open(const HistoryScreen.all())),
        const SizedBox(height: FasanSpace.l),
        FasanLabel(trLang(de ? 'de' : 'en', 'my_balance.friends')),
        tile(Icons.person_add_alt_1_rounded, trLang(de ? 'de' : 'en', 'my_balance.inviteAFriend'), trLang(de ? 'de' : 'en', 'my_balance.sendALinkChat'), () => FriendsPage.inviteFriend(context)),
        if (collab.directs.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: FasanSpace.s), child: Text(trLang(de ? 'de' : 'en', 'my_balance.connected', [collab.directs.length]), style: tt.bodySmall)),
        const SizedBox(height: FasanSpace.m),
        FasanLabel(trLang(de ? 'de' : 'en', 'my_balance.accountAndDevices')),
        tile(Icons.qr_code_2_rounded, trLang(de ? 'de' : 'en', 'my_balance.addADevice'), trLang(de ? 'de' : 'en', 'my_balance.yourAccountOnA'), () => open(const PairSendScreen())),
        tile(Icons.login_rounded, trLang(de ? 'de' : 'en', 'my_balance.signInWithAnother'), null, () => open(const PairNewScreen())),
        tile(Icons.payments_outlined, trLang(de ? 'de' : 'en', 'my_balance.howPeopleCanPay'), trLang(de ? 'de' : 'en', 'my_balance.ibanPaypalMeWallet'), () => open(const PaySetupScreen())),
        tile(Icons.save_alt_rounded, trLang(de ? 'de' : 'en', 'my_balance.saveABackup'), trLang(de ? 'de' : 'en', 'my_balance.withAPasswordE'), () => saveBackupFlow(context)),
        tile(Icons.key_rounded, trLang(de ? 'de' : 'en', 'my_balance.wordsKeyTrust'), trLang(de ? 'de' : 'en', 'my_balance.wordsToRestore'), () => open(const AccountScreen())),
        const SizedBox(height: FasanSpace.m),
        const SizedBox(height: FasanSpace.xl),
        if (collab.identity != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_off_outlined, color: Colors.red.shade600),
            title: Text(trLang(de ? 'de' : 'en', 'my_balance.deleteAccount'), style: TextStyle(color: Colors.red.shade600)),
            onTap: () => _deleteAccount(context),
          ),
      ]),
    );
  }
}


/// Deleting the account (Nutzer 04.11.): asks once, says what happens and what cannot be promised.
Future<void> _deleteAccount(BuildContext context) async {
  final de = S.of(context).de;
  var alsoBills = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(trLang(de ? 'de' : 'en', 'my_balance.deleteTheAccount')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trLang(de ? 'de' : 'en', 'my_balance.yourGroupsAndFriends')),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: alsoBills,
            onChanged: (v) => set(() => alsoBills = v ?? false),
            title: Text(trLang(de ? 'de' : 'en', 'my_balance.alsoDeleteAllReceipts')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(trLang(de ? 'de' : 'en', 'my_balance.cancel'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600), onPressed: () => Navigator.pop(ctx, true), child: Text(trLang(de ? 'de' : 'en', 'my_balance.deleteForGood'))),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final nav = Navigator.of(context), messenger = ScaffoldMessenger.of(context);
  await CollabScope.read(context).deleteAccount(alsoBills: alsoBills);
  nav.popUntil((r) => r.isFirst);
  messenger.showSnackBar(SnackBar(content: Text(trLang(de ? 'de' : 'en', 'my_balance.accountDeleted'))));
}
