// SPDX-License-Identifier: MPL-2.0
// Fasan Split – real fonts for widget tests that measure layout (the default test font is much wider/taller). MPL-2.0
import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';

Future<void> loadTestFonts() async {
  // Direkt aus den Dateien, damit kein Bundle-Fehler stumm bleibt. Ort des Pakets: FASAN_UI, sonst wo die Paketauflösung
  // fasan_ui findet (Pfad-Override lokal, Git-Cache in der CI – dort liegt es nicht neben diesem Repo; 07.11. rote Android-CI).
  final ui = Platform.environment['FASAN_UI'] ?? _packageRoot('fasan_ui') ?? '../../fasan_ui';
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

/// Root folder of [name] from .dart_tool/package_config.json (Isolate.resolvePackageUri is not supported in flutter test).
String? _packageRoot(String name) {
  final f = File('.dart_tool/package_config.json');
  if (!f.existsSync()) return null;
  final pkgs = (jsonDecode(f.readAsStringSync())['packages'] as List).cast<Map<String, dynamic>>();
  for (final p in pkgs) {
    if (p['name'] == name) return Directory.fromUri(f.absolute.uri.resolve(p['rootUri'] as String)).path;
  }
  return null;
}
