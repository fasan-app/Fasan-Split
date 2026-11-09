// SPDX-License-Identifier: MPL-2.0
// Fasan Split – one bill as a card on the overview. MPL-2.0

import '../l10n/tr.dart' show trLang;
import 'dart:convert';
import 'dart:typed_data' show Uint8List;
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import 'scope.dart';
import '../l10n_bill.dart';
import 'package:fasan_core/bill.dart';
import '../flows/scan_queue.dart';
import 'category.dart';
import 'package:fasan_core/settle.dart';
import 'my_balance.dart';
import 'scan_stage.dart';
import 'flow.dart';
import 'change_badge.dart';
import 'common.dart';
import 'resume.dart';
import '../state/images.dart';
import 'marquee_text.dart';
import 'shape_tokens.dart';

/// Decoded group preview per bill. `Image.memory(base64Decode(...))` made a NEW byte list at every build, and the image cache
/// compares byte lists by identity: each build of a tile (every one that scrolls into view, every list rebuild) decoded the
/// base64 text and the JPEG again – Firefox/Safari scrolled the list at ~150 ms per frame (Code-Befund 08.11.).
final Map<String, ({String src, Uint8List bytes})> _thumbCache = {};
Uint8List _thumbBytes(Bill b) {
  final hit = _thumbCache[b.id];
  if (hit != null && (identical(hit.src, b.thumb) || hit.src == b.thumb)) return hit.bytes;
  final bytes = base64Decode(b.thumb!);
  _thumbCache[b.id] = (src: b.thumb!, bytes: bytes);
  return bytes;
}

/// One bill on the overview: thumbnail, name, state (waiting / reading / failed / date and step) and sum.
class BillTile extends StatelessWidget {
  const BillTile({super.key, required this.bill, required this.queue, required this.selecting, required this.selected, required this.onToggle, required this.onRetry, this.subtitle, this.openable = true, this.onLongPress, this.focusItem, this.trailing});

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

  /// Menu button at the right end of the row (the ⋮ that replaced the swipes, Nutzer 09.11.).
  final Widget? trailing;

  /// Search hit inside the bill: open it on that item (middle of the screen, one pulse).
  final int? focusItem;

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
    final r = l.rCard;
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
      // second line: only what a glance needs (Nutzer 08.11.: Symbol, Datum, Personen; Schritt, Zahler, Ort und Anzahl raus,
      // sie standen lang und wurden abgeschnitten). The state word only where it is a real state.
      sub = [
        if (bill.refund) t.refundBadge,
        date,
        if (bill.settled) trLang(t.de ? 'de' : 'en', 'bill_tile.settled'),
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
                ? ClipRRect(borderRadius: BorderRadius.circular(6), clipBehavior: Clip.hardEdge, child: Image.memory(_thumbBytes(bill), width: 34, height: 44, fit: BoxFit.cover, gaplessPlayback: true))
                : SizedBox(width: 34, height: 44, child: Icon(failed ? Icons.error_outline_rounded : Icons.receipt_outlined, color: l.textMuted));
    final fill = bill.fill;
    final framed = !waiting && !failed && !bill.settled && bill.its.isNotEmpty;
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
              // frame like the items (Nutzer 07.11.): red open, amber partial, green complete; plain for waiting, failed and settled bills
              border: selected || !framed
                  ? Border.all(color: selected ? l.accent : l.hairline, width: 1.5)
                  : Border.fromBorderSide(fillSide(context, fill)),
              color: selected ? Color.alphaBlend(l.accent.withValues(alpha: 0.10), l.surface) : l.surface,
            ),
            child: Row(children: [
              Stack(clipBehavior: Clip.none, children: [
                AnimatedOpacity(duration: motion.short, opacity: selected ? 0.55 : 1, child: thumb),
                // changed by someone else since I last opened it (Nutzer 04.11.: bills must be marked): counter at the upper right
                // corner of the thumbnail instead of a dot beside the name (Nutzer 08.11.: the name needs the room)
                if (CollabScope.of(context).changedBills.contains(bill.id) && !selecting)
                  Positioned(right: -7, top: -7, child: ChangeBadge(id: bill.id, count: CollabScope.of(context).unseenCount(bill.id))),
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
                    Expanded(child: MarqueeText(bill.purpose.isEmpty ? (waiting || failed ? t.photoBill : t.appName) : bill.purpose, style: tt.titleMedium)),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    // category at a glance (category.dart)
                    if (categoryById(bill.category) case final c?) ...[Icon(c.icon, size: 14, color: c.color), const SizedBox(width: 4)],
                    Flexible(child: MarqueeText(sub, style: tt.bodySmall)),
                    // people moved here from the right side: the title gets the width (Nutzer 08.11.)
                    if (!waiting && !failed && bill.ps.isNotEmpty) ...[const SizedBox(width: FasanSpace.s), FasanAvatarStack(people: [for (final p in bill.ps) (p.name, p.color)], size: 18, max: 4)],
                  ]),
                ]),
              ),
              if (failed && !selecting)
                TextButton(onPressed: onRetry, child: Text(t.readAgain))
              else if (!waiting && !failed || bill.total != null && !failed) ...[
                Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  CurrencyScope(code: bill.currency ?? StoreScope.read(context).homeCurrency, child: Money(bill.effectiveTotal)),
                  // my balance from this bill: green = I get, red = I owe (Nutzer 04.11.: indicators at a glance)
                  if (bill.done && !bill.settled && bill.payer != null)
                    if (myDebts([bill], myNames(context)).values.fold(0, (a, x) => a + x) case final v when v != 0)
                      Text('${money(v, de: t.de, sign: true)} ${signOf(context)}', style: tt.labelMedium!.copyWith(color: v > 0 ? Colors.green.shade600 : Colors.red.shade600, fontWeight: FontWeight.w700)),
                  // not finished yet: what is assigned so far, paler (Nutzer 07.11.)
                  if (!bill.done && !bill.settled)
                    if (myProvisional([bill], myNames(context)).values.fold(0, (a, x) => a + x) case final v when v != 0)
                      Text(trLang(t.de ? 'de' : 'en', 'my_balance.provisionalShort', [money(v, de: t.de, sign: true)]), style: tt.labelMedium!.copyWith(color: (v > 0 ? Colors.green.shade600 : Colors.red.shade600).withValues(alpha: 0.65))),
                ]),
              ],
              ?trailing,
            ]),
          ),
        ));
    // Waiting, reading and failed photos have nothing to open yet.
    if (waiting || failed || selecting || !openable) return body(null);
    // Container transform: the card grows into the bill (fasan_ui GESTALTUNG.md §7). Unfinished bills continue where
    // the user left (Karte 3.9: Schließen verwirft nie).
    return FasanOpenContainer(
      radius: r,
      openBuilder: (_) => focusItem != null
          ? (bill.done ? ReviewScreen(bill: bill, focusItem: focusItem) : ResumeFlow(bill: bill, focusItem: focusItem))
          : (bill.done ? ResultScreen(bill: bill) : ResumeFlow(bill: bill)),
      closedBuilder: (context, open) => body(open),
    );
  }
}

