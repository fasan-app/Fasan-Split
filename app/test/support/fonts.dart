// Fasan Split – real fonts for widget tests that measure layout (the default test font is much wider/taller). MPL-2.0
import 'dart:io';

import 'package:flutter/services.dart';

Future<void> loadTestFonts() async {
  // Direkt aus den Dateien (fasan_ui neben diesem Repo, FASAN_UI überschreibt), damit kein Bundle-Fehler stumm bleibt.
  final ui = Platform.environment['FASAN_UI'] ?? '../../fasan_ui';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  await load('packages/fasan_ui/FasanInter', [for (final w in [400, 500, 600, 700]) '$ui/fonts/Inter-$w.ttf']);
  await load('packages/fasan_ui/FasanGeistMono', ['$ui/fonts/GeistMono-Regular.ttf']);
  await load('FasanEmoji', ['assets/fonts/FasanEmoji.ttf']);
  await load('MaterialIcons', ['${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}
