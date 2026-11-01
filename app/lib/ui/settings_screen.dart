// Fasan Split – settings: appearance (fasan_ui), style gallery, about and licences. MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.settings)),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(t.appearance),
          subtitle: Text(t.de ? 'Stil, Akzent, Schrift, Filmeffekte, Akku' : 'Style, accent, font, film effects, battery'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FasanAppearancePage())),
        ),
        ListTile(
          leading: const Icon(Icons.grid_view_outlined),
          title: Text(t.de ? 'Alle Stile vergleichen' : 'Compare all styles'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FasanGalleryPage())),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(t.about),
          subtitle: Text(t.de
              ? 'Frei (MPL-2.0), offline, ohne Konto. Texterkennung: PaddleOCR (Apache-2.0), UVDoc (MIT), ONNX Runtime (MIT).'
              : 'Free (MPL-2.0), offline, no account. Text recognition: PaddleOCR (Apache-2.0), UVDoc (MIT), ONNX Runtime (MIT).'),
          onTap: () => showLicensePage(context: context, applicationName: 'Fasan Split', applicationLegalese: 'MPL-2.0 · fasan-app'),
        ),
      ]),
    );
  }
}
