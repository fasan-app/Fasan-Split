// Fasan Split – one bill as a card on the overview. MPL-2.0

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../l10n_bill.dart';
import '../model/bill.dart';
import '../state/scan_queue.dart';
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
        ? Image(image: ResizeImage(imageProvider(orig!), width: 160), fit: BoxFit.cover)
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
      sub = bill.done ? '${bill.refund ? '${t.refundBadge} · ' : ''}$date · ${bill.ps.length} ${t.de ? 'Personen' : 'people'}' : '$date · ${t.stepOf(bill.step)}';
    }
    if (subtitle != null) sub = subtitle!;
    // reading: date as soon as the first pass knows it, then the state
    if (bill.read == BillRead.reading && bill.receiptDate != null) sub = '$date · $sub';
    Widget body(VoidCallback? open) => FasanDepth(
        radius: r,
        level: selected ? 1 : 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(r),
          onTap: selecting ? onToggle : open,
          onLongPress: selecting ? null : onLongPress,
          child: Container(
            constraints: BoxConstraints(minHeight: l.minTap + 16),
            padding: const EdgeInsets.all(FasanSpace.m),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              border: Border.all(color: selected ? l.accent : l.hairline, width: selected ? 2 : 1),
              color: selected ? Color.alphaBlend(l.accent.withValues(alpha: 0.08), l.surface) : l.surface,
            ),
            child: Row(children: [
              if (selecting) ...[
                Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? l.accent : l.textMuted),
                const SizedBox(width: FasanSpace.m),
              ],
              if (waiting || failed)
                _thumb(context)
              else if (imageExists(bill.imagePath))
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image(image: ResizeImage(imageProvider(bill.imagePath!), width: 120), width: 40, height: 52, fit: BoxFit.cover),
                )
              else
                SizedBox(width: 40, height: 52, child: Icon(failed ? Icons.error_outline_rounded : Icons.receipt_outlined, color: l.textMuted)),
              const SizedBox(width: FasanSpace.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bill.purpose.isEmpty ? (waiting || failed ? t.photoBill : t.appName) : bill.purpose, style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(sub, style: tt.bodySmall),
                ]),
              ),
              if (failed && !selecting)
                TextButton(onPressed: onRetry, child: Text(t.readAgain))
              else if (!waiting && !failed || bill.total != null && !failed) ...[
                FasanAvatarStack(people: [for (final p in bill.ps) (p.name, p.color)], size: 24, max: 3),
                const SizedBox(width: FasanSpace.s),
                Money(bill.effectiveTotal),
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

