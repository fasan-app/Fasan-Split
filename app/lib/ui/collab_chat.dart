// SPDX-License-Identifier: MPL-2.0
// Fasan Split – The chat of a group or a direct chat. Split out of collab_ui.dart (13.11., Umbau, behaviour unchanged). MPL-2.0
import 'person_profile.dart';
import '../l10n/tr.dart';
import 'dart:async';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../collab/group.dart';
import '../collab/notes.dart';
import '../collab/service.dart';
import '../l10n.dart';
import '../l10n_collab.dart';
import 'scope.dart';
import '../flows/scan_queue.dart';
import 'bill_tile.dart';
import 'common.dart' show showNote;
import 'package:fasan_core/bill.dart' show money;
import 'pulse_focus.dart';
import 'shape_tokens.dart';
import 'collab_dialogs.dart';
import 'collab_notes.dart';
import 'collab_sent_items.dart';
// The screen an invitation link opens lives in join_screen.dart (exported here for the old imports).

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.group, this.focusMessage});

  final CollabGroup group;

  /// Message the person is led to (from a notification or the bell): scrolled to the middle, one pulse (pulse_focus.dart).
  final String? focusMessage;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _jumped = false;

  /// Message I answer (quote above the input) or edit (the input holds its text); at most one of the two.
  ChatMessage? _replyTo, _editing;

  /// People (public keys) picked with @ for the message being written.
  final Set<String> _mentions = {};

  /// Search in this chat: shown instead of the title while open.
  bool _searching = false;
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    _query.dispose();
    super.dispose();
  }

  /// Members of the group that can be mentioned (not me).
  List<(String, String)> _members() {
    final g = widget.group, me = CollabScope.read(context).identity?.pub;
    return [for (final k in g.session.memberKeys) if (k != me) (k, g.session.nameOf(k))]..sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
  }

  Future<void> _mention() async {
    final de = S.of(context).de, people = _members();
    final who = await showModalBottomSheet<(String, String)>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(trLang(de ? 'de' : 'en', 'collab_ui.mentionWhom'), style: Theme.of(ctx).textTheme.titleMedium)),
          if (people.isEmpty) ListTile(title: Text(trLang(de ? 'de' : 'en', 'collab_ui.nobodyElseInThe'))),
          for (final p in people) ListTile(leading: FasanAvatar(name: p.$2, index: 0, size: 32), title: Text(p.$2), onTap: () => Navigator.pop(ctx, p)),
        ]),
      ),
    );
    if (who == null || !mounted) return;
    _mentions.add(who.$1);
    final t = _input.text;
    _input.text = '${t.isEmpty || t.endsWith(' ') ? t : '$t '}@${who.$2} ';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  /// The message text with @names of mentioned people in bold.
  InlineSpan _rich(ChatMessage m, TextStyle? base, Color accent) {
    final names = {for (final k in m.mentions) widget.group.session.nameOf(k)}..removeWhere((n) => n.trim().isEmpty);
    if (names.isEmpty) return TextSpan(text: m.text, style: base);
    final re = RegExp('@(${names.map(RegExp.escape).join('|')})');
    final spans = <InlineSpan>[];
    var i = 0;
    for (final x in re.allMatches(m.text)) {
      if (x.start > i) spans.add(TextSpan(text: m.text.substring(i, x.start)));
      spans.add(TextSpan(text: x.group(0), style: TextStyle(fontWeight: FontWeight.w700, color: accent)));
      i = x.end;
    }
    if (i < m.text.length) spans.add(TextSpan(text: m.text.substring(i)));
    return TextSpan(style: base, children: spans);
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final c = CollabScope.read(context);
    final edit = _editing;
    if (edit != null) {
      c.editMessage(widget.group, edit.id, text);
    } else {
      c.sendMessage(widget.group, text, reply: _replyTo?.id, mentions: _mentions.toList());
    }
    _mentions.clear();
    _input.clear();
    setState(() => _replyTo = _editing = null);
  }

  static const _emojis = ['👍', '❤️', '😂', '😮', '🙏'];

  /// Long press on a message: react, answer, copy, and – for my own – edit or delete (Nutzer 04.11.).
  Future<void> _actions(ChatMessage m, bool mine) async {
    if (m.deleted) return;
    final de = S.of(context).de, c = CollabScope.read(context), me = c.identity?.pub;
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true, // many entries on a small or landscape screen: the menu scrolls instead of being cut off
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: FasanSpace.s),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final e in _emojis)
                IconButton(
                  tooltip: e,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  style: m.reactions[me] == e ? IconButton.styleFrom(backgroundColor: FasanLook.of(ctx).accent.withValues(alpha: 0.25)) : null,
                  icon: Text(e, style: const TextStyle(fontSize: 24)),
                  onPressed: () => Navigator.pop(ctx, 'react:$e'),
                ),
            ]),
          ),
          ListTile(leading: const Icon(Icons.reply_rounded), title: Text(trLang(de ? 'de' : 'en', 'collab_ui.reply')), onTap: () => Navigator.pop(ctx, 'reply')),
          if (m.text.isNotEmpty) ListTile(leading: const Icon(Icons.copy_rounded), title: Text(trLang(de ? 'de' : 'en', 'collab_ui.copy')), onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(leading: Icon(m.pinned ? Icons.push_pin : Icons.push_pin_outlined), title: Text(m.pinned ? (trLang(de ? 'de' : 'en', 'collab_ui.unpin')) : (trLang(de ? 'de' : 'en', 'collab_ui.pin'))), onTap: () => Navigator.pop(ctx, 'pin')),
          if (mine && m.bill == null) ListTile(leading: const Icon(Icons.edit_outlined), title: Text(trLang(de ? 'de' : 'en', 'collab_ui.edit')), onTap: () => Navigator.pop(ctx, 'edit')),
          if (mine) ListTile(leading: const Icon(Icons.delete_outline_rounded), title: Text(trLang(de ? 'de' : 'en', 'collab_ui.deleteForEveryone')), onTap: () => Navigator.pop(ctx, 'delete')),
          ]),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice.startsWith('react:')) {
      c.reactToMessage(widget.group, m.id, choice.substring(6));
    } else if (choice == 'reply') {
      setState(() {
        _replyTo = m;
        _editing = null;
      });
    } else if (choice == 'pin') {
      c.pinMessage(widget.group, m.id, !m.pinned);
    } else if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
    } else if (choice == 'edit') {
      setState(() {
        _editing = m;
        _replyTo = null;
        _input.text = m.text;
        _input.selection = TextSelection.collapsed(offset: m.text.length);
      });
    } else if (choice == 'delete') {
      c.deleteMessage(widget.group, m.id);
    }
  }

  /// Short one-line description of a message for quotes.
  String _preview(ChatMessage m, bool de) => m.deleted ? (trLang(de ? 'de' : 'en', 'collab_ui.messageDeleted')) : (m.bill != null ? (trLang(de ? 'de' : 'en', 'collab_ui.receipt', [m.text])) : m.text);

  /// Tag a bill in the chat: the bills of this group, or – writing to a friend – of the groups we share.
  Future<void> _attach() async {
    final c = CollabScope.read(context), store = StoreScope.read(context), de = S.of(context).de;
    final g = widget.group;
    final peer = g.secret.direct ? c.directPeer(g) : null;
    final groupsHere = g.secret.direct
        ? {for (final x in c.groups.values) if (!x.secret.direct && peer != null && x.session.memberKeys.contains(peer)) x.localName}
        : {g.localName};
    final bills = store.bills.where((b) => b.trashedAt == null && groupsHere.contains(b.group)).toList()..sort((a, b) => b.date.compareTo(a.date));
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: Text(trLang(de ? 'de' : 'en', 'collab_ui.whichReceipt'), style: Theme.of(ctx).textTheme.titleMedium)),
            if (bills.isEmpty) ListTile(title: Text(trLang(de ? 'de' : 'en', 'collab_ui.noSharedReceiptsYet'))),
            for (final b in bills)
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(b.purpose.isEmpty ? 'Bon' : b.purpose),
                subtitle: Text('${b.group ?? ''} · ${money(b.effectiveTotal, de: de)}'),
                onTap: () => Navigator.pop(ctx, b.id),
              ),
          ]),
        ),
      ),
    );
    if (id == null) return;
    final b = store.bills.firstWhere((x) => x.id == id);
    c.sendMessage(g, b.purpose.isEmpty ? 'Bon' : b.purpose, bill: id);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
          actions: [
            IconButton(
              tooltip: trLang(t.de ? 'de' : 'en', 'collab_ui.searchThisChat'),
              icon: Icon(_searching ? Icons.search_off_rounded : Icons.search_rounded),
              onPressed: () => setState(() {
                _searching = !_searching;
                _query.clear();
              }),
            ),
            IconButton(
              tooltip: CollabScope.of(context).isMuted(widget.group) ? (trLang(t.de ? 'de' : 'en', 'collab_ui.unmute')) : (trLang(t.de ? 'de' : 'en', 'collab_ui.mute')),
              icon: Icon(CollabScope.of(context).isMuted(widget.group) ? Icons.notifications_off_rounded : Icons.notifications_none_rounded),
              onPressed: () {
                final c = CollabScope.read(context), now = !c.isMuted(widget.group);
                c.setMuted(widget.group, now);
                showNote(context, now ? (trLang(t.de ? 'de' : 'en', 'collab_ui.mutedNoNotificationsFrom')) : (trLang(t.de ? 'de' : 'en', 'collab_ui.notificationsOnAgain')));
              },
            ),
          ],
          title: _searching
              ? TextField(controller: _query, autofocus: true, decoration: InputDecoration(hintText: trLang(t.de ? 'de' : 'en', 'collab_ui.search'), border: InputBorder.none), onChanged: (_) => setState(() {}))
              : GroupChangeBuilder(
              group: widget.group,
              docId: GroupSession.members,
              builder: (context) {
                final g = widget.group, c = CollabScope.of(context); // rebuilds with presence changes
                final n = g.secret.direct ? c.directName(g) : g.localName;
                final peer = g.secret.direct ? c.directPeer(g) : null;
                final seen = peer == null ? null : c.lastSeen(peer);
                // Nutzer 12.11.: the name in the chat header looks tappable, so it opens the person (direct chat) or the members (group chat).
                return InkWell(key: const ValueKey('chat-header'), onTap: () {
                  if (peer != null) {
                    openProfile(context, groupName: '', person: n, pub: peer);
                  } else if (!g.secret.direct) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MembersScreen(group: g)));
                  }
                }, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(n.isEmpty ? t.chatTitle : n),
                  if (peer != null && (c.isOnline(peer) || seen != null))
                    Text(
                      c.isOnline(peer) ? 'online' : trLang(t.de ? 'de' : 'en', 'collab_ui.lastSeen', [seen!.day, seen.month, seen.hour.toString().padLeft(2, '0'), seen.minute.toString().padLeft(2, '0')]),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ]));
              })),
      body: Column(children: [
        Expanded(
          child: GroupChangeBuilder(
            group: widget.group,
            docId: GroupSession.chat,
            builder: (context) {
              final s = CollabScope.of(context), me = s.identity?.pub; // read marks of others rebuild too
              final all = s.messages(widget.group);
              final q = _searching ? _query.text.trim().toLowerCase() : '';
              final msgs = q.isEmpty ? all : [for (final m in all) if (!m.deleted && m.text.toLowerCase().contains(q)) m];
              final pinned = all.where((m) => m.pinned && !m.deleted).lastOrNull;
              // open chat = read (after this frame: marking notifies)
              WidgetsBinding.instance.addPostFrameCallback((_) => s.markRead(widget.group));
              if (q.isNotEmpty && msgs.isEmpty) {
                return Center(child: Text(trLang(t.de ? 'de' : 'en', 'collab_ui.nothingFound'), style: tt.bodyMedium));
              }
              if (msgs.isEmpty) {
                return Center(child: Padding(padding: const EdgeInsets.all(FasanSpace.l), child: Text(t.chatEmpty, style: tt.bodyMedium, textAlign: TextAlign.center)));
              }
              return Column(children: [
                // the newest pinned message stays on top; the long-press menu unpins it
                if (pinned != null)
                  Material(
                    color: l.surfaceAlt,
                    child: InkWell(
                      onLongPress: () => _actions(pinned, pinned.from == me),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: l.minTap),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: FasanSpace.s),
                          child: Row(children: [
                            Icon(Icons.push_pin, size: 16, color: l.accent),
                            const SizedBox(width: FasanSpace.s),
                            Expanded(child: Text('${pinned.from == me ? t.you : widget.group.session.nameOf(pinned.from)}: ${_preview(pinned, t.de)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodySmall)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                    child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(FasanSpace.m),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m = msgs[i], mine = m.from == me;
                  // the list builds lazily: before the target exists, jump close to it once; PulseOnFocus then centres it and pulses
                  if (!_jumped && widget.focusMessage != null) {
                    _jumped = true;
                    final at = msgs.indexWhere((x) => x.id == widget.focusMessage);
                    if (at > 0) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scroll.hasClients) _scroll.jumpTo((at * 96.0).clamp(0.0, _scroll.position.maxScrollExtent));
                      });
                    }
                  }
                  return PulseOnFocus(
                    key: ValueKey('pulse-${m.id}'),
                    active: m.id == widget.focusMessage,
                    child: Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () => _actions(m, mine),
                      child: Container(
                      margin: const EdgeInsets.only(bottom: FasanSpace.s),
                      padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: FasanSpace.s),
                      decoration: BoxDecoration(color: mine ? l.accent.withValues(alpha: 0.18) : l.surfaceAlt, borderRadius: BorderRadius.circular(l.rInner), border: m.mentions.contains(me) ? Border.all(color: l.accent, width: 1.5) : null),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(mine ? t.you : widget.group.session.nameOf(m.from), style: tt.labelSmall),
                        // quote of the message this one answers
                        if (m.reply != null)
                          Builder(builder: (context) {
                            final q = msgs.where((x) => x.id == m.reply).firstOrNull;
                            return Container(
                              margin: const EdgeInsets.only(top: 2, bottom: 4),
                              padding: const EdgeInsets.only(left: FasanSpace.s),
                              decoration: BoxDecoration(border: Border(left: BorderSide(color: l.accent, width: 3))),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                if (q != null) Text(q.from == me ? t.you : widget.group.session.nameOf(q.from), style: tt.labelSmall),
                                Text(q == null ? (trLang(t.de ? 'de' : 'en', 'collab_ui.messageNoLongerAvailable')) : _preview(q, t.de), maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
                              ]),
                            );
                          }),
                        if (m.bill != null && !m.deleted)
                          // a tagged bill: the card opens it (Nutzer 04.11.)
                          switch (StoreScope.read(context).bills.where((b) => b.id == m.bill).firstOrNull) {
                            final b? when m.items.isNotEmpty => ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 320),
                                child: SentItems(bill: b, items: m.items),
                              ),
                            final b? => ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 300),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: BillTile(bill: b, queue: ScanQueue.current ?? ScanQueue(StoreScope.read(context)), selecting: false, selected: false, onToggle: () {}, onRetry: () {}),
                                ),
                              ),
                            _ => Text(trLang(t.de ? 'de' : 'en', 'collab_ui.receiptNotAvailable'), style: tt.bodySmall),
                          },
                        if (m.deleted)
                          Text(trLang(t.de ? 'de' : 'en', 'collab_ui.messageDeleted2'), style: tt.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: l.textMuted))
                        else if (m.text.isNotEmpty && m.bill == null)
                          Text.rich(_rich(m, tt.bodyMedium, l.accent)),
                        if (m.edited && !m.deleted) Text(trLang(t.de ? 'de' : 'en', 'collab_ui.edited'), style: tt.labelSmall),
                        // reactions: emoji with the number of people; changed through the long-press menu
                        if (m.reactions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(spacing: 6, children: [
                              for (final e in {...m.reactions.values})
                                Text('$e ${m.reactions.values.where((x) => x == e).length}', style: tt.labelMedium?.copyWith(fontWeight: m.reactions[me] == e ? FontWeight.w700 : null)),
                            ]),
                          ),
                        // ✓ sent, ✓✓ read (direct: the friend; group: how many have read it) – only with presence on
                        if (mine)
                          Builder(builder: (context) {
                            final readers = [
                              for (final k in widget.group.session.memberKeys)
                                if (k != me && (s.readUntil(widget.group, k)?.millisecondsSinceEpoch ?? 0) >= m.at.millisecondsSinceEpoch) k,
                            ];
                            final read = readers.isNotEmpty;
                            return Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(read ? Icons.done_all_rounded : Icons.done_rounded, size: 14, color: read ? l.accent : l.textMuted),
                              if (read && !widget.group.secret.direct) ...[const SizedBox(width: 3), Text(trLang(t.de ? 'de' : 'en', 'collab_ui.readBy', [readers.length]), style: tt.labelSmall)],
                            ]);
                          }),
                      ]),
                    ),
                    ),
                  ));
                },
              )),
              ]);
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(FasanSpace.m, 0, FasanSpace.m, FasanSpace.s),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_replyTo != null || _editing != null)
                Container(
                  margin: const EdgeInsets.only(bottom: FasanSpace.s),
                  padding: const EdgeInsets.only(left: FasanSpace.m),
                  decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.rInner)),
                  child: Row(children: [
                    Icon(_editing != null ? Icons.edit_outlined : Icons.reply_rounded, size: 18, color: l.accent),
                    const SizedBox(width: FasanSpace.s),
                    Expanded(
                      child: Text(
                        _editing != null ? (trLang(t.de ? 'de' : 'en', 'collab_ui.editMessage')) : '${trLang(t.de ? 'de' : 'en', 'collab_ui.replyTo')} ${_replyTo!.from == CollabScope.read(context).identity?.pub ? t.you : widget.group.session.nameOf(_replyTo!.from)}: ${_preview(_replyTo!, t.de)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: trLang(t.de ? 'de' : 'en', 'collab_ui.cancel'),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        if (_editing != null) _input.clear();
                        _replyTo = _editing = null;
                      }),
                    ),
                  ]),
                ),
              Row(children: [
              IconButton(tooltip: trLang(t.de ? 'de' : 'en', 'collab_ui.attachAReceipt'), icon: const Icon(Icons.attach_file_rounded), onPressed: _attach),
              if (!widget.group.secret.direct) IconButton(tooltip: trLang(t.de ? 'de' : 'en', 'collab_ui.mentionSomeone'), icon: const Icon(Icons.alternate_email_rounded), onPressed: _mention),
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
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Live part of one group: members, notes, chat, invitation (admin), leaving.
