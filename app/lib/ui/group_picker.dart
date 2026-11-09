// SPDX-License-Identifier: MPL-2.0
// Fasan Split – group picker above the Gruppe and Abrechnung tab (Option A, Nutzer 08.11. 21:06): „Alle“, „Ohne Gruppe“, then every
// group, then „+“. One row that scrolls sideways; every chip is a drop target for lifted bills (they move into that group).
// Sources: Apple HIG „Tab bars“ (tabs are for places, choices inside a place belong in the content), Material 3 FilterChip/ChoiceChip
// semantics (selected state is read out). MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n/tr.dart' show trLang;
import '../l10n.dart';

/// All bills of all groups and the loose ones.
const kScopeAll = '\u0001all';

/// Only bills without a group („Ohne Gruppe“ is a group of its own).
const kScopeLoose = '\u0001none';

/// True when [scope] names a real group.
bool scopeIsGroup(String scope) => scope != kScopeAll && scope != kScopeLoose;

/// The group name to give a new bill started in [scope]; null = no group.
String? scopeGroup(String scope) => scopeIsGroup(scope) ? scope : null;

class GroupPicker extends StatelessWidget {
  const GroupPicker({super.key, required this.groups, required this.selected, required this.onSelect, required this.onNew, this.onDrop});

  final List<String> groups;
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;

  /// Bills dropped on a chip: the group name, or null for „Ohne Gruppe“. Null callback = chips take no bills.
  final void Function(List<Bill> bills, String? group)? onDrop;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context), t = S.of(context);
    final lang = t.de ? 'de' : 'en';
    Widget chip(String scope, String label, {IconData? icon, String? dropTo, bool canDrop = true}) {
      final on = scope == selected;
      return DragTarget<List<Bill>>(
        onWillAcceptWithDetails: (_) => onDrop != null && canDrop,
        onAcceptWithDetails: (d) => onDrop?.call(d.data, dropTo),
        builder: (context, cand, _) => Padding(
          padding: const EdgeInsets.only(right: FasanSpace.s),
          child: Semantics(
            button: true,
            selected: on,
            label: label,
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: l.minTap),
              child: ChoiceChip(
                avatar: icon == null ? null : Icon(icon, size: 18),
                label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: on || cand.isNotEmpty,
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => onSelect(scope),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: l.minTap + 4,
      child: ListView(
        key: const ValueKey('group-picker'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
        children: [
          chip(kScopeAll, trLang(lang, 'scope.all'), icon: Icons.layers_outlined, canDrop: false),
          chip(kScopeLoose, trLang(lang, 'scope.none'), icon: Icons.inbox_outlined, dropTo: null),
          for (final g in groups) chip(g, g, icon: Icons.folder_outlined, dropTo: g),
          Semantics(
            button: true,
            label: t.newGroup,
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: l.minTap, minHeight: l.minTap),
              child: IconButton(tooltip: t.newGroup, icon: const Icon(Icons.create_new_folder_outlined), onPressed: onNew),
            ),
          ),
        ],
      ),
    );
  }
}
