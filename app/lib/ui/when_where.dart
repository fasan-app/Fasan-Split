// Fasan Split – when and where: date and address printed on the receipt, editable; OpenStreetMap only on tap
// (Beschluss 02.11.: Ort aus dem Bon, GPS nur Hinweis; OSM-Abgleich nur auf Knopfdruck). The app itself makes no
// network request: the search opens in the browser. MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import 'package:fasan_core/bill.dart';
import 'common.dart';

class WhenWhere extends StatelessWidget {
  const WhenWhere({super.key, required this.bill, required this.onChanged, this.compact = false});

  final Bill bill;
  final VoidCallback onChanged;

  /// One row (date · place · OSM) above the items; the full card is for detail views.
  final bool compact;

  Future<void> _pickDate(BuildContext context) async {
    final d = await showDatePicker(context: context, initialDate: bill.date, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d != null) {
      bill.receiptDate = d;
      onChanged();
    }
  }

  Future<void> _editPlace(BuildContext context) async {
    final t = S.of(context);
    final c = TextEditingController(text: bill.placeAddress ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.place),
        content: TextField(controller: c, autofocus: true, maxLines: 2, decoration: InputDecoration(labelText: t.address)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, c.text), child: Text(t.saveClose)),
        ],
      ),
    );
    if (v != null) {
      bill.placeAddress = v.trim().isEmpty ? null : v.trim();
      onChanged();
    }
  }

  Future<void> _osm(BuildContext context) async {
    final t = S.of(context);
    final q = [bill.purpose, bill.placeAddress].whereType<String>().where((x) => x.trim().isNotEmpty).join(', ');
    final ok = await launchUrl(Uri.https('www.openstreetmap.org', '/search', {'query': q}), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showNote(context, t.noBrowser);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final l = FasanLook.of(context);
    final tt = Theme.of(context).textTheme;
    final d = bill.date;
    final date = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    Widget row(IconData icon, String label, String value, VoidCallback onTap, {Widget? trailing, bool muted = false}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(l.radius * 0.5),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: l.minTap),
            child: Row(children: [
              Icon(icon, size: 20, color: l.textMuted),
              const SizedBox(width: FasanSpace.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: tt.bodySmall!.copyWith(color: l.textMuted)),
                  Text(value, style: tt.bodyLarge!.copyWith(color: muted ? l.textMuted : null)),
                ]),
              ),
              ?trailing,
            ]),
          ),
        );
    if (compact) {
      final place = bill.placeAddress == null ? t.placeUnknownShort : bill.placeAddress!.split(', ').last;
      Widget chip(IconData icon, String text, VoidCallback onTap, {bool muted = false}) => InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: l.minTap),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 18, color: l.textMuted),
                const SizedBox(width: 6),
                Flexible(child: Text(text, style: tt.bodyMedium!.copyWith(color: muted ? l.textMuted : null), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          );
      return Row(children: [
        chip(Icons.event_outlined, date, () => _pickDate(context)),
        const SizedBox(width: FasanSpace.m),
        Expanded(child: chip(Icons.place_outlined, place, () => _editPlace(context), muted: bill.placeAddress == null)),
        IconButton(tooltip: t.osmSearch, icon: const Icon(Icons.map_outlined, size: 20), onPressed: () => _osm(context)),
      ]);
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: FasanSpace.xs),
        child: Column(children: [
          row(Icons.event_outlined, bill.receiptDate != null ? t.dateOnReceipt : t.dateCaptured, date, () => _pickDate(context)),
          Divider(height: 1, color: l.hairline),
          row(
            Icons.place_outlined,
            bill.taxId == null ? t.place : '${t.place} · ${t.taxIdLabel} ${bill.taxId}',
            bill.placeAddress ?? t.placeUnknown,
            () => _editPlace(context),
            muted: bill.placeAddress == null,
            trailing: TextButton.icon(onPressed: () => _osm(context), icon: const Icon(Icons.map_outlined, size: 18), label: const Text('OSM')),
          ),
        ]),
      ),
    );
  }
}
