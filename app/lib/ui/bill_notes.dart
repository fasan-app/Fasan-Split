// Fasan Split – notes on a bill (Nutzer 04.11.): anyone in the group writes a note, can pin it as a hint on top of the
// bill, and can mention people with @ – they find it in their „Neuigkeiten“. Shared with the bill (BillSync `n/`). MPL-2.0
import '../l10n/tr.dart' show trLang;
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import 'scope.dart';
import '../model/bill.dart';

/// Pinned notes as a hint on top of the bill (result and flow steps).
class PinnedNotes extends StatelessWidget {
  const PinnedNotes({super.key, required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    StoreScope.of(context);
    final pinned = bill.notes.where((n) => n.pinned).toList();
    if (pinned.isEmpty) return const SizedBox.shrink();
    final l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    return Column(children: [
      for (final n in pinned)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: FasanSpace.s),
          padding: const EdgeInsets.all(FasanSpace.m),
          decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(l.radius * 0.6), border: Border.all(color: Colors.amber.withValues(alpha: 0.5))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.push_pin_rounded, size: 18, color: Colors.amber),
            const SizedBox(width: FasanSpace.s),
            Expanded(child: Text('${n.text}  — ${n.from}', style: tt.bodyMedium)),
          ]),
        ),
    ]);
  }
}

/// All notes of a bill with a field to write one.
class BillNotes extends StatefulWidget {
  const BillNotes({super.key, required this.bill});

  final Bill bill;

  @override
  State<BillNotes> createState() => _BillNotesState();
}

class _BillNotesState extends State<BillNotes> {
  final TextEditingController _c = TextEditingController();
  final Set<String> _mentions = {};
  bool _pin = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Who can be mentioned: the people of the bill and everyone of its group.
  List<String> _people() {
    final b = widget.bill, collab = CollabScope.read(context);
    final names = {for (final p in b.ps) p.name, if (b.group != null) ...collab.peopleOf(b.group!)};
    final me = (collab.identity?.name ?? StoreScope.read(context).me).trim().toLowerCase();
    return names.where((n) => n.trim().isNotEmpty && n.trim().toLowerCase() != me).toList()..sort();
  }

  Future<void> _mention() async {
    final de = S.of(context).de;
    final people = _people();
    final who = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(trLang(de ? 'de' : 'en', 'bill_notes.mentionWhom'), style: Theme.of(ctx).textTheme.titleMedium)),
          if (people.isEmpty) ListTile(title: Text(trLang(de ? 'de' : 'en', 'bill_notes.nobodyElseOnThis'))),
          for (final p in people) ListTile(leading: FasanAvatar(name: p, index: 0, size: 32), title: Text(p), onTap: () => Navigator.pop(ctx, p)),
        ]),
      ),
    );
    if (who == null) return;
    _mentions.add(who);
    final t = _c.text;
    _c.text = '${t.isEmpty || t.endsWith(' ') ? t : '$t '}@$who ';
    _c.selection = TextSelection.collapsed(offset: _c.text.length);
  }

  void _add() {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    final store = StoreScope.read(context), collab = CollabScope.read(context);
    final me = (collab.identity?.name ?? '').trim().isNotEmpty ? collab.identity!.name.trim() : store.me;
    final b = widget.bill;
    // a mention counts while its @name is still in the text
    final ms = [for (final m in _mentions) if (text.contains('@$m')) m];
    b.notes.add(BillNote(from: me.isEmpty ? '—' : me, text: text, pinned: _pin, mentions: ms));
    store.upsert(b);
    _c.clear();
    _mentions.clear();
    setState(() => _pin = false);
  }

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de, l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final store = StoreScope.of(context), b = widget.bill;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FasanLabel(trLang(de ? 'de' : 'en', 'bill_notes.notes')),
      const SizedBox(height: FasanSpace.s),
      for (final n in b.notes)
        Padding(
          padding: const EdgeInsets.only(bottom: FasanSpace.s),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FasanAvatar(name: n.from, index: 0, size: 28),
            const SizedBox(width: FasanSpace.s),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${n.from} · ${n.at.day}.${n.at.month}. ${n.at.hour.toString().padLeft(2, '0')}:${n.at.minute.toString().padLeft(2, '0')}', style: tt.labelSmall!.copyWith(color: l.textMuted)),
                Text(n.text, style: tt.bodyMedium),
              ]),
            ),
            IconButton(
              tooltip: n.pinned ? (trLang(de ? 'de' : 'en', 'bill_notes.unpin')) : (trLang(de ? 'de' : 'en', 'bill_notes.pinOnTop')),
              icon: Icon(n.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, size: 20, color: n.pinned ? Colors.amber : l.textMuted),
              onPressed: () {
                n.pinned = !n.pinned;
                store.upsert(b);
              },
            ),
            IconButton(
              tooltip: trLang(de ? 'de' : 'en', 'bill_notes.delete'),
              icon: Icon(Icons.delete_outline_rounded, size: 20, color: l.textMuted),
              onPressed: () {
                b.notes.remove(n);
                store.upsert(b);
              },
            ),
          ]),
        ),
      Row(children: [
        IconButton(tooltip: trLang(de ? 'de' : 'en', 'bill_notes.mentionSomeone'), icon: const Icon(Icons.alternate_email_rounded), onPressed: _mention),
        Expanded(
          child: TextField(
            controller: _c,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: trLang(de ? 'de' : 'en', 'bill_notes.writeANoteMentions')),
            onSubmitted: (_) => _add(),
          ),
        ),
        IconButton(
          tooltip: trLang(de ? 'de' : 'en', 'bill_notes.pinOnTop2'),
          icon: Icon(_pin ? Icons.push_pin_rounded : Icons.push_pin_outlined, color: _pin ? Colors.amber : l.textMuted),
          onPressed: () => setState(() => _pin = !_pin),
        ),
        IconButton.filled(tooltip: trLang(de ? 'de' : 'en', 'bill_notes.saveNote'), icon: const Icon(Icons.send_rounded), onPressed: _add),
      ]),
    ]);
  }
}
