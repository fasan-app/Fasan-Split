// SPDX-License-Identifier: MPL-2.0
// Fasan Split – what opens when an invitation link is tapped (Nutzer 05.11.: „nicht selbsterklärend“; friends did not know what would
// happen, what to do with a broken link, whether they were in, and what happens to the new account when the browser is closed).
// States: asking (who invites to what, what happens, name, one button) → done (really connected? the account safety card). All
// texts come from lib/l10n (context.tr). MPL-2.0
import 'dart:async';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../collab/group.dart';
import '../collab/service.dart';
import '../l10n/tr.dart';
import 'scope.dart';
import '../flows/scan_queue.dart';
import '../platform/web_platform.dart';
import 'backup_ui.dart';
import 'collab_ui.dart' show AccountScreen, ChatScreen, ensureConsent, pendingInviteLink;
import 'groups.dart' show GroupScreen;

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
  bool _busy = false, _showLink = false;
  String? _sendError;

  /// Set when joining worked: the group (or friend chat) we are in now.
  String? _doneTag;
  DateTime? _doneAt;
  Timer? _poll;
  late final CollabService _service = CollabScope.read(context);

  @override
  void initState() {
    super.initState();
    // prefilled with the account name, else „Das bin ich“
    final n = _service.identity?.name ?? '';
    _name.text = n.isNotEmpty ? n : StoreScope.read(context).me;
    _link.addListener(() => setState(() => _sendError = null));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _link.dispose();
    _name.dispose();
    super.dispose();
  }

  ({Invite? invite, String problem}) get _parsed => Invite.parseDetailed(_link.text);

  String get _problem {
    final p = _parsed;
    if (p.invite == null) return p.problem; // empty, incomplete, invalid
    return p.invite!.expired ? 'expired' : '';
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null && mounted) _link.text = d!.text!.trim();
  }

  Future<void> _join() async {
    final inv = _parsed.invite;
    if (inv == null || _problem.isNotEmpty) return;
    if (!await ensureConsent(context, _service) || !mounted) return;
    setState(() {
      _busy = true;
      _sendError = null;
    });
    final err = await _service.join(_link.text, _name.text);
    if (!mounted) return;
    if (err == 'member') {
      // not an error: they are in already
      setState(() {
        _busy = false;
        _doneTag = inv.tag;
        _doneAt = DateTime.now();
      });
      return;
    }
    if (err != null) {
      setState(() {
        _busy = false;
        _sendError = err;
      });
      return;
    }
    clearJoinCode(); // the join is under way: the code may leave the tab now
    pendingInviteLink = null;
    setState(() {
      _busy = false;
      _doneTag = inv.tag;
      _doneAt = DateTime.now();
    });
    // while waiting for „connected“: look again every second (the service does not announce successful sends)
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  CollabGroup? get _group => _doneTag == null ? null : _service.groups[_doneTag];

  /// At least one document of the group was accepted by a relay: the others can see us.
  bool get _connected => (_group?.session.published ?? 0) > 0;

  void _openGroup() {
    final g = _group;
    if (g == null) return;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute(builder: (_) => g.secret.direct ? ChatScreen(group: g) : GroupScreen(name: g.localName, queue: ScanQueue.current ?? ScanQueue(StoreScope.read(context)))));
  }

  @override
  Widget build(BuildContext context) {
    final direct = _parsed.invite?.direct == true;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr(direct ? 'join.titleDirect' : 'join.title'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom),
        children: _doneTag != null ? _done(context) : _asking(context),
      ),
    );
  }

  // ---- asking ----

  List<Widget> _asking(BuildContext context) {
    final l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final p = _parsed, inv = p.invite, problem = _problem;
    final direct = inv?.direct == true;
    final de = context.langCode == 'de';
    String two(int n) => n.toString().padLeft(2, '0');
    final until = inv == null ? '' : '${two(inv.expires.day)}.${two(inv.expires.month)}.${inv.expires.year}';
    return [
      // who invites to what
      Container(
        padding: const EdgeInsets.all(FasanSpace.l),
        decoration: BoxDecoration(color: l.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(l.radius * 0.8)),
        child: Row(children: [
          Icon(direct ? Icons.person_add_alt_1_rounded : Icons.group_add_rounded, size: 36, color: l.accent),
          const SizedBox(width: FasanSpace.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                inv == null ? context.tr('join.heroNone') : (direct ? context.tr('join.heroDirect', [inv.name]) : context.tr('join.heroGroup', [inv.name])),
                style: tt.titleLarge,
              ),
              if (inv != null && problem.isEmpty) Text(context.tr('join.expires', [de ? until : until]), style: tt.bodySmall!.copyWith(color: l.textMuted)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: FasanSpace.m),
      if (kIsWeb) _WebAppHint(code: _link.text),

      // something wrong with the link: say what and how to fix it – never a dead end
      if (problem.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(FasanSpace.m),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(l.radius * 0.6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.link_off_rounded, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: FasanSpace.s),
              Expanded(child: Text(context.tr('join.problem.$problem'), style: tt.bodyMedium!.copyWith(fontWeight: FontWeight.w600))),
            ]),
            if (problem == 'incomplete' || problem == 'invalid') ...[const SizedBox(height: FasanSpace.s), Text(context.tr('join.problem.fix'), style: tt.bodySmall)],
          ]),
        ),
        const SizedBox(height: FasanSpace.m),
      ],

      // what happens next
      if (problem.isEmpty) ...[
        Text(context.tr('join.stepsTitle'), style: tt.titleSmall),
        const SizedBox(height: FasanSpace.xs),
        for (final (i, k) in (direct ? const ['join.step1', 'join.step2Direct', 'join.step3Direct'] : const ['join.step1', 'join.step2', 'join.step3']).indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 11, backgroundColor: l.accent.withValues(alpha: 0.2), child: Text('${i + 1}', style: tt.labelSmall)),
              const SizedBox(width: FasanSpace.s),
              Expanded(child: Text(context.tr(k), style: tt.bodyMedium)),
            ]),
          ),
        const SizedBox(height: FasanSpace.l),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: context.tr('join.name'))),
        const SizedBox(height: FasanSpace.m),
        if (_sendError != null) Padding(padding: const EdgeInsets.only(bottom: FasanSpace.s), child: Text(context.tr('join.sendFailed'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('join-button'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _join,
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.tr(direct ? 'join.buttonDirect' : 'join.button')),
          ),
        ),
        const SizedBox(height: FasanSpace.s),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: l.textMuted),
          const SizedBox(width: FasanSpace.xs),
          Expanded(child: Text(context.tr('join.privacy'), style: tt.bodySmall!.copyWith(color: l.textMuted))),
        ]),
        const SizedBox(height: FasanSpace.m),
      ],

      // the link itself: shown when something is wrong or on demand
      if (problem.isNotEmpty || _showLink)
        ...[
          TextField(
            key: const ValueKey('join-link'),
            controller: _link,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(labelText: context.tr('join.linkLabel')),
          ),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(icon: const Icon(Icons.content_paste_rounded), label: Text(context.tr('join.paste')), onPressed: _paste)),
        ]
      else
        Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setState(() => _showLink = true), child: Text(context.tr('join.showLink')))),
    ];
  }

  // ---- done ----

  List<Widget> _done(BuildContext context) {
    final l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final g = _group, connected = _connected;
    final waited = _doneAt == null ? Duration.zero : DateTime.now().difference(_doneAt!);
    final direct = g?.secret.direct == true;
    final name = g == null ? '' : (direct ? _service.directName(g) : g.localName);
    return [
      Icon(connected ? Icons.check_circle_rounded : Icons.sync_rounded, size: 64, color: l.accent),
      const SizedBox(height: FasanSpace.m),
      Text(context.tr(connected ? 'join.doneTitle' : 'join.doneTitleWait'), style: tt.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: FasanSpace.xs),
      Text(context.tr(direct ? 'join.doneDirect' : 'join.doneText', [name]), style: tt.bodyLarge, textAlign: TextAlign.center),
      const SizedBox(height: FasanSpace.l),
      // really connected? (a join that is saved but not yet received by a relay is not seen by the others)
      Container(
        key: const ValueKey('join-status'),
        padding: const EdgeInsets.all(FasanSpace.m),
        decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.6)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          connected ? Icon(Icons.check_rounded, color: l.accent) : const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2))),
          const SizedBox(width: FasanSpace.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr(connected ? 'join.connected' : (waited.inSeconds < 6 ? 'join.connecting' : 'join.notConnected')), style: tt.bodyMedium),
              if (!connected && waited.inSeconds >= 6) TextButton(onPressed: _service.wake, child: Text(context.tr('join.retry'))),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: FasanSpace.l),
      AccountSafetyCard(key: const ValueKey('account-safety'), onDone: null),
      const SizedBox(height: FasanSpace.l),
      SizedBox(
        width: double.infinity,
        child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), onPressed: _group == null ? null : _openGroup, child: Text(context.tr('join.openGroup'))),
      ),
    ];
  }
}

/// „Open in the app“ / „Get the Android app“ for someone who came in through the browser.
class _WebAppHint extends StatelessWidget {
  const _WebAppHint({required this.code});

  final String code;

  static final _apk = Uri.parse('https://github.com/fasan-app/Fasan-Split/releases/tag/neueste');

  @override
  Widget build(BuildContext context) {
    final i = code.indexOf('#');
    return Padding(
      padding: const EdgeInsets.only(bottom: FasanSpace.m),
      child: Wrap(spacing: FasanSpace.s, runSpacing: FasanSpace.s, children: [
        if (i >= 0)
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(context.tr('join.openApp')),
            onPressed: () => launchUrl(Uri.parse('fasansplit://join${code.substring(i)}')),
          ),
        OutlinedButton.icon(icon: const Icon(Icons.android_rounded), label: Text(context.tr('join.getApp')), onPressed: () => launchUrl(_apk, mode: LaunchMode.externalApplication)),
      ]),
    );
  }
}

/// The account was just made on this device: how it is kept, what happens when the browser is closed, how to secure and restore it.
/// On the join screen and (until it is secured or closed) as a banner on the start page.
class AccountSafetyCard extends StatelessWidget {
  const AccountSafetyCard({super.key, this.onDone, this.compact = false});

  /// Called when the user says „later“ or „secured“ (the banner uses it to go away); null: no such buttons.
  final VoidCallback? onDone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(FasanSpace.m),
      decoration: BoxDecoration(color: l.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(l.radius * 0.7), border: Border.all(color: l.accent.withValues(alpha: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.shield_outlined, color: l.accent),
          const SizedBox(width: FasanSpace.s),
          Expanded(child: Text(context.tr('safe.title'), style: tt.titleMedium)),
        ]),
        const SizedBox(height: FasanSpace.s),
        Text(context.tr('safe.body'), style: tt.bodyMedium),
        if (!compact) ...[
          const SizedBox(height: FasanSpace.xs),
          Text(context.tr('safe.browser'), style: tt.bodySmall),
          if (kIsWeb && needsHomeScreenHint()) ...[const SizedBox(height: FasanSpace.xs), Text(context.tr('safe.ios'), style: tt.bodySmall)],
        ],
        const SizedBox(height: FasanSpace.s),
        Wrap(spacing: FasanSpace.s, runSpacing: FasanSpace.xs, children: [
          FilledButton.tonalIcon(
            key: const ValueKey('safe-words'),
            icon: const Icon(Icons.pin_outlined),
            label: Text(context.tr('safe.words')),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
          ),
          OutlinedButton.icon(
            key: const ValueKey('safe-backup'),
            icon: const Icon(Icons.save_alt_rounded),
            label: Text(context.tr('safe.backup')),
            onPressed: () => saveBackupFlow(context),
          ),
          if (onDone != null) TextButton(onPressed: onDone, child: Text(context.tr('safe.later'))),
        ]),
      ]),
    );
  }
}
