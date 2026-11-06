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
}
