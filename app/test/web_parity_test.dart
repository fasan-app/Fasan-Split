// Browser = APK 1:1 (Nutzer 06.11., Prüfliste): `kIsWeb` may only appear where the platform really differs. New places must be
// added here on purpose and listed in docs/WEB-GRENZEN.md. MPL-2.0
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kIsWeb nur an den bekannten Stellen (Plattform-Adapter und die Hinweise in docs/WEB-GRENZEN.md)', () {
    const allowed = {
      'lib/main.dart', // join code from the address, deep links (APK only)
      'lib/recognition/service.dart', // recognition in the web worker
      'lib/collab/notify.dart', // notification permission API differs
      'lib/ui/diagnose.dart', // device block of the protocol (no dart:io on the web)
      'lib/ui/home.dart', // update check (APK update vs „load again“), „Zum Home-Bildschirm“ hint
      'lib/ui/join_screen.dart', // „open the web app“ / home-screen hints
    };
    final found = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final name = f.path;
      if (name.endsWith('_web.dart') || name.endsWith('_io.dart') || name.endsWith('_stub.dart')) continue;
      if (RegExp(r'\bkIsWeb\b').hasMatch(f.readAsStringSync().replaceAll(RegExp(r'^import .*$', multiLine: true), ''))) found.add(name);
    }
    expect(found.difference(allowed), isEmpty, reason: 'neue kIsWeb-Stelle: in allowed und docs/WEB-GRENZEN.md eintragen, oder in einen Adapter');
  });
}
