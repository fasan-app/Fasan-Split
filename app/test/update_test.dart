// Fasan Split – change list for in-app updates (lib/update.dart). MPL-2.0
import 'package:fasan_split/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const body = 'Testversion aus abc1234.\n\n- abc1234 Glas bricht den Hintergrund\n- 9f8e7d6 Korn wie echter Film\n- 1234567 Alter Stand\n- 7654321 Noch älter\n';

  test('Nur Änderungen über dem eigenen Stand', () {
    expect(Updates.changesSince(body, '1234567'), ['Glas bricht den Hintergrund', 'Korn wie echter Film']);
  });

  test('Ohne bekannten eigenen Stand alle Zeilen', () {
    expect(Updates.changesSince(body, ''), hasLength(4));
  });
}
