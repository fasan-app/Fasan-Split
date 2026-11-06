// Guards of the module structure (docs/ARCHITEKTUR.md). They fail when a change breaks a rule, so the structure does not wear away
// change by change. MPL-2.0
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<(String, String)> _imports(String dir) sync* {
  for (final f in Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    for (final m in RegExp(r'''^(?:import|export|part)\s+'([^']+)';''', multiLine: true).allMatches(f.readAsStringSync())) {
      yield (f.path, m.group(1)!);
    }
  }
}

void main() {
  test('fasan_core kennt nur sich selbst und dart: (kein Flutter, keine App, keine Pakete)', () {
    final bad = [
      for (final (file, imp) in _imports('packages/fasan_core/lib'))
        if (!imp.startsWith('dart:') && imp.contains(':') && !imp.startsWith('package:fasan_core/')) '$file → $imp',
      for (final (file, imp) in _imports('packages/fasan_core/lib'))
        if (!imp.contains(':') && imp.contains('..')) '$file → $imp (zeigt aus dem Paket heraus)',
    ];
    expect(bad, isEmpty);
  });

  test('Übergangsdateien in lib/ leiten nur weiter (kein Code, der neben dem Kern wächst)', () {
    for (final f in ['model/bill.dart', 'model/split_math.dart', 'model/settle.dart', 'model/pay.dart', 'recognition/speisen.dart', 'recognition/text_util.dart']) {
      final code = File('lib/$f').readAsLinesSync().where((l) => l.trim().isNotEmpty && !l.trim().startsWith('//'));
      expect(code.every((l) => l.startsWith('export ')), isTrue, reason: f);
    }
  });

  // layers of the app (docs/ARCHITEKTUR.md): a folder may only use the folders below it
  const allowed = {
    'model': <String>{},
    'recognition': {'model'},
    'state': {'model', 'recognition'},
    'collab': {'model', 'state'},
    'perf': <String>{},
    // flows: what a screen starts (scan queue, scan → bill, backup); below ui, above store and sync
    'flows': {'model', 'recognition', 'state', 'collab'},
    'ui': {'model', 'recognition', 'state', 'collab', 'perf', 'l10n', 'flows'},
  };
  for (final e in allowed.entries) {
    test('lib/${e.key} nutzt nur ${e.value.isEmpty ? 'fasan_core' : e.value.join(', ')}', () {
      final bad = <String>[];
      for (final (file, imp) in _imports('lib/${e.key}')) {
        String? target;
        if (imp.startsWith('package:fasan_split/')) {
          target = imp.substring('package:fasan_split/'.length);
        } else if (!imp.contains(':')) {
          final rel = File(file).parent.uri.resolve(imp).toFilePath();
          final i = rel.indexOf('lib/');
          target = i < 0 ? null : rel.substring(i + 4);
        }
        if (target == null || !target.contains('/')) continue; // files at the top of lib/ (texts, adapters): checked when they move
        final folder = target.split('/').first;
        if (folder != e.key && !e.value.contains(folder)) bad.add('$file → $imp');
      }
      expect(bad, isEmpty);
    });
  }

  test('Kein Bildschirm und kein Ablauf importiert main.dart (Einstieg kennt alles, nichts kennt ihn)', () {
    final bad = [
      for (final d in ['lib/ui', 'lib/flows', 'lib/state', 'lib/collab', 'lib/recognition', 'lib/model'])
        for (final (file, imp) in _imports(d))
          if (imp.endsWith('main.dart')) '$file → $imp',
    ];
    expect(bad, isEmpty);
  });
}
