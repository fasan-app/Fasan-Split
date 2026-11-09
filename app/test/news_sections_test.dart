// SPDX-License-Identifier: MPL-2.0
// Fasan Split – news file parsing for „Was ist neu“ in the browser settings. MPL-2.0
import 'package:fasan_split/flows/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Abschnitte und Punkte, neueste zuerst, begrenzt', () {
    const text = '## 0.1.84\n- Eins\n- Zwei\n## 0.1.83\n- Drei\n\nText ohne Punkt\n## 0.1.82\n- Vier\n';
    final all = Updates.newsSections(text);
    expect(all.map((e) => e.$1), ['0.1.84', '0.1.83', '0.1.82']);
    expect(all.first.$2, ['Eins', 'Zwei']);
    expect(all[1].$2, ['Drei']);
    expect(Updates.newsSections(text, maxSections: 2).length, 2);
    expect(Updates.newsSections('Kein Abschnitt\n- lose').length, 0);
  });
}
