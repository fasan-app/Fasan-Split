// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the group choice as a labelled switch with a sheet (Nutzer 09.11.: chips do not scale with many groups). The switch
// shows what is chosen („Alle Gruppen“, „Ohne Gruppe“, a name) and opens a list: Alle, Ohne Gruppe, the groups, a search field when
// there are many, and „Neue Gruppe“. Sources: Apple HIG „Pull-down buttons“ / „Sheets“ (a choice among many belongs in a list), see
// docs/KONZEPT-STARTBILDSCHIRM.md. MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../l10n/tr.dart' show trLang;
import 'group_picker.dart';
import 'shape_tokens.dart';

/// More groups than this get a search field.
const kScopeSearchFrom = 7;

/// Result of the sheet: a scope, or [kScopeNew] for „Neue Gruppe“.
const kScopeNew = '\u0001new';

String scopeLabel(BuildContext context, String scope) {
  final lang = S.of(context).de ? 'de' : 'en';
  if (scope == kScopeAll) return trLang(lang, 'scope.allGroups');
  if (scope == kScopeLoose) return trLang(lang, 'scope.none');
  return scope;
}

/// The labelled switch: tap opens the sheet.
class ScopeSwitch extends StatelessWidget {
  const ScopeSwitch({super.key, required this.groups, required this.selected, required this.onSelect, required this.onNew});

  final List<String> groups;
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final label = scopeLabel(context, selected);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('scope-switch'),
        borderRadius: BorderRadius.circular(l.rCard),
        onTap: () async {
          final v = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => _ScopeSheet(groups: groups, selected: selected),
          );
          if (v == null) return;
          v == kScopeNew ? onNew() : onSelect(v);
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: l.minTap),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: FasanSpace.s),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleMedium)),
            Icon(Icons.expand_more_rounded, color: l.textMuted),
            const SizedBox(width: FasanSpace.xs),
          ]),
        ),
      ),
    );
  }
}

class _ScopeSheet extends StatefulWidget {
  const _ScopeSheet({required this.groups, required this.selected});

  final List<String> groups;
  final String selected;

  @override
  State<_ScopeSheet> createState() => _ScopeSheetState();
}

class _ScopeSheetState extends State<_ScopeSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), lang = t.de ? 'de' : 'en';
    final q = _q.trim().toLowerCase();
    final shown = [for (final g in widget.groups) if (q.isEmpty || g.toLowerCase().contains(q)) g];
    Widget row(String scope, String label, IconData icon) => ListTile(
          leading: Icon(icon),
          title: Text(label),
          trailing: scope == widget.selected ? Icon(Icons.check_rounded, color: l.accent) : null,
          onTap: () => Navigator.pop(context, scope),
        );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: FasanSpace.l), children: [
          ListTile(title: Text(trLang(lang, 'scope.sheetTitle'), style: Theme.of(context).textTheme.titleMedium)),
          if (widget.groups.length > kScopeSearchFrom)
            Padding(
              padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.s),
              child: TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: trLang(lang, 'scope.search')),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          if (q.isEmpty) ...[
            row(kScopeAll, trLang(lang, 'scope.allGroups'), Icons.layers_outlined),
            row(kScopeLoose, trLang(lang, 'scope.none'), Icons.inbox_outlined),
          ],
          for (final g in shown) row(g, g, Icons.folder_outlined),
          if (q.isEmpty) ListTile(leading: const Icon(Icons.create_new_folder_outlined), title: Text(t.newGroup), onTap: () => Navigator.pop(context, kScopeNew)),
        ]),
      ),
    );
  }
}
