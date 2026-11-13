// SPDX-License-Identifier: MPL-2.0
// Fasan Split – Account screen: name, key, recovery words, relays. Split out of collab_ui.dart (13.11., Umbau, behaviour unchanged). MPL-2.0
import '../l10n/tr.dart';
import 'dart:async';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../collab/service.dart';
import '../l10n.dart';
import '../l10n_collab.dart';
import 'scope.dart';
import 'pairing_ui.dart';
import 'collab_dialogs.dart';
// The screen an invitation link opens lives in join_screen.dart (exported here for the old imports).

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final TextEditingController _name = TextEditingController(), _words = TextEditingController();
  bool _showWords = false;

  Timer? _nameTimer;
  late final CollabService _svc = CollabScope.read(context); // dispose() must not look up the tree

  @override
  void initState() {
    super.initState();
    final n = _svc.identity?.name ?? '';
    _name.text = n.isNotEmpty ? n : StoreScope.read(context).me;
  }

  @override
  void dispose() {
    _nameTimer?.cancel();
    if (_name.text.trim().isNotEmpty) _svc.setName(_name.text);
    _name.dispose();
    _words.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final t = S.of(context), s = CollabScope.read(context), messenger = ScaffoldMessenger.of(context);
    final text = _words.text.trim();
    if (text.isEmpty) return;
    if (!await confirmDialog(context, t.accountRestore, t.accountRestoreText, t.accountRestore)) return;
    try {
      if (!mounted || !await ensureConsent(context, s)) return; // the group list comes from the relays
      final n = await s.restoreIdentity(text, name: _name.text.trim());
      _words.clear();
      messenger.showSnackBar(SnackBar(content: Text('${t.accountRestoreOk} ${t.de ? (n == 0 ? 'Keine Gruppen gefunden.' : '$n Gruppen sind zurück.') : (n == 0 ? 'No groups found.' : '$n groups are back.')}')));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.accountRestoreBad)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), s = CollabScope.read(context), tt = Theme.of(context).textTheme;
    final id = s.identity;
    return Scaffold(
      appBar: AppBar(title: Text(t.collabTitle)),
      body: ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: t.accountName, helperText: trLang(t.de ? 'de' : 'en', 'collab_ui.usedEverywhereReceiptsGroups')),
          // saved while typing (04.11.: only Enter saved, leaving the field lost the name)
          onChanged: (v) {
            _nameTimer?.cancel();
            _nameTimer = Timer(const Duration(milliseconds: 600), () => s.setName(v));
          },
          onSubmitted: (v) => s.setName(v),
        ),
        const SizedBox(height: FasanSpace.l),
        if (id == null) Text(t.accountMissing, style: tt.bodyMedium),
        if (id != null) ...[
          Text(t.accountKey, style: tt.titleSmall),
          SelectableText(id.pub, style: tt.bodySmall),
          const SizedBox(height: FasanSpace.l),
          if (id.mnemonic != null) ...[
            Text(t.accountWords, style: tt.titleSmall),
            const SizedBox(height: FasanSpace.s),
            Text(t.accountWordsText, style: tt.bodySmall),
            TextButton(onPressed: () => setState(() => _showWords = !_showWords), child: Text(_showWords ? t.accountHide : t.accountShow)),
            if (_showWords) ...[
              Wrap(spacing: FasanSpace.s, runSpacing: FasanSpace.s, children: [
                for (final (i, w) in id.mnemonic!.split(' ').indexed) Chip(label: Text('${i + 1}. $w')),
              ]),
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: Text(trLang(t.de ? 'de' : 'en', 'collab_ui.copyWords')),
                onPressed: () async {
                  final m = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: id.mnemonic!));
                  m.showSnackBar(SnackBar(content: Text(trLang(t.de ? 'de' : 'en', 'collab_ui.wordsCopied'))));
                },
              ),
            ],
          ],
        ],
        const Divider(height: FasanSpace.xl),
        // several devices, one account (Nutzer 04.11.): no typing of the 12 words
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.qr_code_2_rounded),
          title: Text(trLang(t.de ? 'de' : 'en', 'collab_ui.signInWithAnother')),
          subtitle: Text(trLang(t.de ? 'de' : 'en', 'collab_ui.thisDeviceShowsA')),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairNewScreen())),
        ),
        if (id != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add_to_home_screen_rounded),
            title: Text(trLang(t.de ? 'de' : 'en', 'collab_ui.addDevice')),
            subtitle: Text(trLang(t.de ? 'de' : 'en', 'collab_ui.scanTheCodeOf')),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairSendScreen())),
          ),
        const Divider(height: FasanSpace.xl),
        Text(t.accountRestore, style: tt.titleSmall),
        const SizedBox(height: FasanSpace.s),
        Text(t.accountRestoreText, style: tt.bodySmall),
        const SizedBox(height: FasanSpace.s),
        TextField(controller: _words, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: t.accountWords)),
        const SizedBox(height: FasanSpace.s),
        OutlinedButton(onPressed: _restore, child: Text(t.accountRestore)),
        const Divider(height: FasanSpace.xl),
        Text(t.relaysTitle, style: tt.titleSmall),
        const SizedBox(height: FasanSpace.s),
        Text(t.relaysText, style: tt.bodySmall),
        for (final r in defaultRelays) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(r)),
      ]),
    );
  }
}

/// The bell on the main pages (Nutzer 04.11.: notifications about joins, messages, new and changed bills).
