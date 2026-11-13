// SPDX-License-Identifier: MPL-2.0
// Fasan Split – Activity bell and screen. Split out of collab_ui.dart (13.11., Umbau, behaviour unchanged). MPL-2.0
import '../l10n/tr.dart';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../collab/activity.dart';
import '../collab/service.dart';
import '../l10n.dart';
import 'scope.dart';
import '../flows/scan_queue.dart';
import 'group_header.dart' show openBill;
import 'groups.dart';
import 'collab_chat.dart';
// The screen an invitation link opens lives in join_screen.dart (exported here for the old imports).

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
          ActivityKind.proposal => Icons.help_outline_rounded,
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
      final store = StoreScope.read(context);
      // a proposal leads to the item itself: ref = '<bill id>#<item uid>'
      final refBill = a.ref?.split('#').first, refItem = a.ref != null && a.ref!.contains('#') ? a.ref!.split('#').last : null;
      final bill = refBill == null ? null : store.bills.where((b) => b.id == refBill && b.trashedAt == null).firstOrNull;
      if (a.kind == ActivityKind.message || g.secret.direct || a.kind == ActivityKind.mention && c.messages(g).any((m) => m.id == a.ref)) {
        // lead to the exact message: centred, one pulse (Nutzer 09.11. 18:44)
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(group: g, focusMessage: a.ref)));
      } else if ((a.kind == ActivityKind.billNew || a.kind == ActivityKind.billChanged || a.kind == ActivityKind.mention || a.kind == ActivityKind.proposal) && bill != null) {
        // straight into the bill the news is about (a proposal: to the item, one pulse)
        final fi = refItem == null ? -1 : bill.its.indexWhere((x) => x.uid == refItem);
        openBill(context, bill, focusItem: fi < 0 ? null : fi);
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
