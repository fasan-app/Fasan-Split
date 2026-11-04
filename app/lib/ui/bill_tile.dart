// Fasan Split – one bill as a card on the overview. MPL-2.0

import 'dart:convert';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../l10n_bill.dart';
import '../model/bill.dart';
import '../state/scan_queue.dart';
import '../model/category.dart';
import '../model/settle.dart';
import 'my_balance.dart';
import 'scan_stage.dart';
import 'flow.dart';
import 'common.dart';
import 'resume.dart';
import '../state/images.dart';

/// One bill on the overview: thumbnail, name, state (waiting / reading / failed / date and step) and sum.
class BillTile extends StatelessWidget {
  const BillTile({super.key, required this.bill, required this.queue, required this.selecting, required this.selected, required this.onToggle, required this.onRetry, this.subtitle, this.openable = true, this.onLongPress});

  final Bill bill;
  final ScanQueue queue;
  final bool selecting, selected;
  final VoidCallback onToggle, onRetry;

  /// Long press outside the selection: starts selecting with this bill (home.dart).
  final VoidCallback? onLongPress;

  /// Replaces the second line (trash: „gelöscht am …“).
  final String? subtitle;

  /// False: tapping does nothing (bills in the trash).
  final bool openable;

  /// Thumbnail of the photo as taken, at once when it is added. While the bill is read, it plays the scan animation in small
  /// (Nutzer 02.11.): boxes light up, the kinked receipt straightens.
  Widget _thumb(BuildContext context) {
    final l = FasanLook.of(context);
    final orig = bill.originalPath;
    final photo = imageExists(orig)
        ? Image(image: ResizeImage(imageProvider(orig!), width: 160), fit: BoxFit.cover, gaplessPlayback: true)
        : ColoredBox(color: l.surfaceAlt, child: Icon(bill.read == BillRead.failed ? Icons.error_outline_rounded : Icons.receipt_outlined, color: l.textMuted));
    final live = bill.read == BillRead.reading ? queue.liveFor(bill.id) : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 48,
        height: 62,
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(color: l.surfaceAlt, child: live != null ? ScanStage(live: live, placeholder: photo) : photo),
          if (bill.read == BillRead.queued) Center(child: Icon(Icons.schedule_rounded, size: 20, color: l.text.withValues(alpha: 0.7))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    final date = '${bill.date.day}.${bill.date.month}.${bill.date.year}';
    final r = l.radius * 0.7;
    final waiting = bill.read == BillRead.queued || bill.read == BillRead.reading;
    final failed = bill.read == BillRead.failed;
    String sub;
    if (bill.read == BillRead.queued) {
      sub = t.waiting;
    } else if (bill.read == BillRead.reading) {
      sub = queue.currentId == bill.id && queue.progress > 0 ? '${t.readingNow} · ${(queue.progress * 100).round()} %' : t.readingNow;
    } else if (failed) {
      sub = t.readFailedShort;
    } else {
      // dense line (Nutzer 04.11.: more at one glance): date, step or people, who paid, place
      final payer = bill.payer != null && bill.payer! < bill.ps.length ? bill.ps[bill.payer!].name : null;
      final city = bill.placeAddress?.split(RegExp(r'[,\n]')).map((x) => x.trim()).where((x) => x.isNotEmpty).lastOrNull;
      sub = [
        if (bill.refund) t.refundBadge,
        date,
        bill.settled ? (t.de ? 'ausgeglichen' : 'settled') : bill.done ? (t.de ? 'eingetragen' : 'entered') : t.stepOf(bill.step),
        if (bill.done) '${bill.ps.length} ${t.de ? 'Pers.' : 'ppl'}',
        if (payer != null) t.de ? '$payer zahlte' : '$payer paid',
        ?city,
      ].join(' · ');
    }
    if (subtitle != null) sub = subtitle!;
    // reading: date as soon as the first pass knows it, then the state
    if (bill.read == BillRead.reading && bill.receiptDate != null) sub = '$date · $sub';
    final motion = FasanMotion.of(context);
    // Selecting changes nothing in the layout (Nutzer 04.11.: the tile grew and all text jumped right for a check box):
    // a check mark fades and scales in on the thumbnail, border and fill only change colour.
    final Widget thumb = waiting || failed
        ? _thumb(context)
        : imageExists(bill.imagePath)
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image(image: ResizeImage(imageProvider(bill.imagePath!), width: 120), width: 34, height: 44, fit: BoxFit.cover, gaplessPlayback: true),
              )
            : bill.thumb != null
                // the preview shared by the group (the photo is on the phone of whoever scanned it)
                ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(base64Decode(bill.thumb!), width: 34, height: 44, fit: BoxFit.cover, gaplessPlayback: true))
                : SizedBox(width: 34, height: 44, child: Icon(failed ? Icons.error_outline_rounded : Icons.receipt_outlined, color: l.textMuted));
    Widget body(VoidCallback? open) => FasanDepth(
        radius: r,
        level: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(r),
          onTap: selecting
              ? onToggle
              : open == null
                  ? null
                  : () {
                      CollabScope.read(context).billSeen(bill.id); // opened: no longer „changed“
                      markBillOrigin(context); // closing the bill comes back here (group, chat, overview)
                      open();
                    },
          onLongPress: selecting ? null : onLongPress,
          child: AnimatedContainer(
            duration: motion.short,
            curve: FasanCurves.short,
            constraints: BoxConstraints(minHeight: l.minTap + 8),
            padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: FasanSpace.s),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              border: Border.all(color: selected ? l.accent : l.hairline, width: 1.5),
              color: selected ? Color.alphaBlend(l.accent.withValues(alpha: 0.10), l.surface) : l.surface,
            ),
            child: Row(children: [
              Stack(clipBehavior: Clip.none, children: [
                AnimatedOpacity(duration: motion.short, opacity: selected ? 0.55 : 1, child: thumb),
                // check mark at the lower right corner of the thumbnail, like photo pickers
                Positioned(
                  right: -6,
                  bottom: -4,
                  child: AnimatedScale(
                    duration: motion.short,
                    curve: Curves.easeOutBack,
                    scale: selecting ? 1 : 0,
                    child: AnimatedContainer(
                      duration: motion.short,
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? l.accent : l.surface,
                        border: Border.all(color: selected ? l.accent : l.textMuted, width: 1.5),
                      ),
                      child: selected ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                    ),
                  ),
                ),
              ]),
              const SizedBox(width: FasanSpace.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    // changed by someone else since I last opened it (Nutzer 04.11.: bills must be marked)
                    if (CollabScope.of(context).changedBills.contains(bill.id)) ...[
                      Container(width: 9, height: 9, decoration: BoxDecoration(color: l.accent, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                    ],
                    Expanded(child: Text(bill.purpose.isEmpty ? (waiting || failed ? t.photoBill : t.appName) : bill.purpose, style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    // category at a glance (category.dart)
                    if (categoryById(bill.category) case final c?) ...[Icon(c.icon, size: 14, color: c.color), const SizedBox(width: 4)],
                    Expanded(child: Text(sub, style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ]),
              ),
              if (failed && !selecting)
                TextButton(onPressed: onRetry, child: Text(t.readAgain))
              else if (!waiting && !failed || bill.total != null && !failed) ...[
                FasanAvatarStack(people: [for (final p in bill.ps) (p.name, p.color)], size: 20, max: 3),
                const SizedBox(width: FasanSpace.s),
                Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  CurrencyScope(code: bill.currency ?? StoreScope.read(context).homeCurrency, child: Money(bill.effectiveTotal)),
                  // my balance from this bill: green = I get, red = I owe (Nutzer 04.11.: indicators at a glance)
                  if (bill.done && !bill.settled && bill.payer != null)
                    if (myDebts([bill], myNames(context)).values.fold(0, (a, x) => a + x) case final v when v != 0)
                      Text('${money(v, de: t.de, sign: true)} ${signOf(context)}', style: tt.labelMedium!.copyWith(color: v > 0 ? Colors.green.shade600 : Colors.red.shade600, fontWeight: FontWeight.w700)),
                ]),
              ],
            ]),
          ),
        ));
    // Waiting, reading and failed photos have nothing to open yet.
    if (waiting || failed || selecting || !openable) return body(null);
    // Container transform: the card grows into the bill (fasan_ui GESTALTUNG.md §7). Unfinished bills continue where
    // the user left (Karte 3.9: Schließen verwirft nie).
    return FasanOpenContainer(
      radius: r,
      openBuilder: (_) => bill.done ? ResultScreen(bill: bill) : ResumeFlow(bill: bill),
      closedBuilder: (context, open) => body(open),
    );
  }
}

