// SPDX-License-Identifier: MPL-2.0
// Fasan Split – category chip on a bill and the picker (base list, own categories, „Eigene Kategorie…“), and the
// sort/filter sheet of the bill lists (Nutzer 04.11.: sort by status, date, place, amount, category). MPL-2.0
import '../l10n/tr.dart' show trLang;
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import 'scope.dart';
import 'package:fasan_core/bill.dart';
import 'category.dart';
import '../state/store.dart';
import 'collab_ui.dart' show askText;

/// Shows the bill's category (or „Kategorie wählen“); tap opens the picker.
class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    StoreScope.of(context); // rebuild right after choosing (04.11.: showed the old one until leaving the bill)
    final c = categoryById(bill.category);
    return ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(c?.icon ?? Icons.category_outlined, size: 18, color: c?.color),
      label: Text(c?.label(t.de) ?? (trLang(t.de ? 'de' : 'en', 'category_ui.chooseCategory'))),
      onPressed: () async {
        final id = await pickCategory(context, bill.category);
        if (id == null || !context.mounted) return;
        bill.category = id.isEmpty ? null : id;
        StoreScope.read(context).upsert(bill);
      },
    );
  }
}

/// Returns the chosen id, '' for „none“, null when closed.
Future<String?> pickCategory(BuildContext context, String? current) async {
  final t = S.of(context), store = StoreScope.read(context);
  final all = [...baseCategories, for (final n in store.customCategories) customCategory(n)];
  final r = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(trLang(t.de ? 'de' : 'en', 'category_ui.category'), style: Theme.of(ctx).textTheme.titleMedium)),
          for (final c in all)
            ListTile(
              leading: Icon(c.icon, color: c.color),
              title: Text(c.label(t.de)),
              trailing: c.id == current ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(ctx, c.id),
            ),
          ListTile(leading: const Icon(Icons.add_rounded), title: Text(trLang(t.de ? 'de' : 'en', 'category_ui.ownCategory')), onTap: () => Navigator.pop(ctx, '+')),
          if (current != null) ListTile(leading: const Icon(Icons.close_rounded), title: Text(trLang(t.de ? 'de' : 'en', 'category_ui.noCategory')), onTap: () => Navigator.pop(ctx, '')),
        ]),
      ),
    ),
  );
  if (r != '+' || !context.mounted) return r;
  final name = await askText(context, trLang(t.de ? 'de' : 'en', 'category_ui.ownCategory2'), trLang(t.de ? 'de' : 'en', 'category_ui.name'));
  if (name == null || name.trim().isEmpty) return null;
  store.addCategory(name.trim());
  return 'c:${name.trim()}';
}

/// How the bill lists are ordered (BillStore.sortMode).
enum BillSort { own, date, amount, shop, category, status }

String sortLabel(BillSort s, bool de) => switch (s) {
      BillSort.own => trLang(de ? 'de' : 'en', 'category_ui.ownOrder'),
      BillSort.date => trLang(de ? 'de' : 'en', 'category_ui.dateNewestFirst'),
      BillSort.amount => trLang(de ? 'de' : 'en', 'category_ui.amountHighestFirst'),
      BillSort.shop => trLang(de ? 'de' : 'en', 'category_ui.placeShopAZ'),
      BillSort.category => trLang(de ? 'de' : 'en', 'category_ui.category2'),
      BillSort.status => trLang(de ? 'de' : 'en', 'category_ui.statusUnfinishedFirst'),
    };

/// Sorts and filters one list of bills for display.
List<Bill> arrange(List<Bill> l, BillSort s, String? category, {bool onlyOpen = false}) {
  final out = [for (final b in l) if ((category == null || b.category == category) && (!onlyOpen || b.fill != ItemFill.complete)) b];
  int byDate(Bill a, Bill b) => b.date.compareTo(a.date);
  switch (s) {
    case BillSort.own:
      break; // store order (sortKey)
    case BillSort.date:
      out.sort(byDate);
    case BillSort.amount:
      out.sort((a, b) => b.effectiveTotal != a.effectiveTotal ? b.effectiveTotal.compareTo(a.effectiveTotal) : byDate(a, b));
    case BillSort.shop:
      out.sort((a, b) => a.purpose.toLowerCase() != b.purpose.toLowerCase() ? a.purpose.toLowerCase().compareTo(b.purpose.toLowerCase()) : byDate(a, b));
    case BillSort.category:
      int ix(Bill b) => b.category == null ? 999 : baseCategories.indexWhere((c) => c.id == b.category).let((i) => i < 0 ? 500 : i);
      out.sort((a, b) => ix(a) != ix(b) ? ix(a).compareTo(ix(b)) : byDate(a, b));
    case BillSort.status:
      // open first, then partial, then complete; inside a state the newest first (Nutzer 07.11.)
      out.sort((a, b) => a.fill != b.fill ? a.fill.index.compareTo(b.fill.index) : byDate(a, b));
  }
  return out;
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Sort order and category filter for the lists. Returns the chosen filter ('' = all) or null when closed.
Future<void> sortSheet(BuildContext context, {required String? filter, required ValueChanged<String?> onFilter, bool? itemsView, ValueChanged<bool>? onItemsView}) async {
  final t = S.of(context), store = StoreScope.read(context), l = FasanLook.of(context);
  var iv = itemsView ?? false;
  final used = <String>{for (final b in store.bills) if (b.category != null && b.trashedAt == null) b.category!};
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: FasanSpace.l), children: [
          // one window for everything that changes the list (Nutzer 09.11.): what is shown, only open, sort order, category
          ListTile(title: Text(trLang(t.de ? 'de' : 'en', 'filter.title'), style: Theme.of(ctx).textTheme.titleMedium)),
          if (itemsView != null && onItemsView != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.s),
              child: FasanSegmented<int>(
                values: const [0, 1],
                selected: iv ? 1 : 0,
                label: (i) => trLang(t.de ? 'de' : 'en', i == 0 ? 'grp.bills' : 'grp.items'),
                onChanged: (v) => set(() {
                  iv = v == 1;
                  onItemsView(iv);
                }),
              ),
            ),
          SwitchListTile(
            title: Text(trLang(t.de ? 'de' : 'en', 'filter.onlyOpen')),
            value: store.onlyOpen,
            onChanged: (v) => set(() => store.onlyOpen = v),
          ),
          ListTile(title: Text(trLang(t.de ? 'de' : 'en', 'filter.sortBy'), style: Theme.of(ctx).textTheme.titleSmall)),
          RadioGroup<BillSort>(
            groupValue: store.sortMode,
            onChanged: (v) => set(() => store.sortMode = v ?? BillSort.status),
            child: Column(children: [for (final s in BillSort.values) RadioListTile<BillSort>(value: s, title: Text(sortLabel(s, t.de)))]),
          ),
          if (used.isNotEmpty) ...[
            ListTile(title: Text(trLang(t.de ? 'de' : 'en', 'category_ui.onlyCategory'), style: Theme.of(ctx).textTheme.titleSmall)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
              child: Wrap(spacing: FasanSpace.s, runSpacing: FasanSpace.s, children: [
                ChoiceChip(label: Text(trLang(t.de ? 'de' : 'en', 'category_ui.all')), selected: filter == null, onSelected: (_) => set(() => onFilter(filter = null))),
                for (final id in used)
                  if (categoryById(id) case final c?)
                    ChoiceChip(
                      avatar: Icon(c.icon, size: 16, color: c.color),
                      label: Text(c.label(t.de)),
                      selected: filter == id,
                      selectedColor: l.accent.withValues(alpha: 0.18),
                      onSelected: (_) => set(() => onFilter(filter = id)),
                    ),
              ]),
            ),
          ],
        ]),
      ),
    ),
  );
}

/// Store side: kept in the app settings.
extension BillStoreSort on BillStore {
  BillSort get sortMode => BillSort.values.firstWhere((s) => s.name == appSettings['sort'], orElse: () => BillSort.status);
  set sortMode(BillSort s) => appSettings = {...appSettings, 'sort': s.name};

  /// Show only bills with open items (Nutzer 07.11.), on the lists and in groups.
  bool get onlyOpen => appSettings['onlyOpen'] == true;
  set onlyOpen(bool v) => appSettings = {...appSettings, 'onlyOpen': v};
}
