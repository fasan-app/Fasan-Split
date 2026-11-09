// SPDX-License-Identifier: MPL-2.0
// Fasan Split – „Meintest du …?“ (ui/search_suggest.dart). Invented words only. MPL-2.0
import 'package:fasan_split/ui/search_suggest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vocab = ['Cola Zero', 'Pizza Margherita', 'Salat', 'Anna', 'Cappuccino', 'Straßenbahn'];

  test('Abstand: Tausch zweier Nachbarn und ein falscher Buchstabe zählen je 1', () {
    expect(editDistance('pizaz', 'pizza'), 1);
    expect(editDistance('coka', 'cola'), 1);
    expect(editDistance('abc', 'abc'), 0);
    expect(editDistance('', 'abc'), 3);
  });

  test('Tippfehler wird korrigiert, jedes Wort einzeln', () {
    expect(didYouMean('coka', vocab), 'cola');
    expect(didYouMean('pizaz', vocab), 'pizza');
    expect(didYouMean('capuccino', vocab), 'cappuccino');
    expect(didYouMean('pizaz margerita', vocab), 'pizza margherita');
    expect(didYouMean('strassenbahn', vocab), 'straßenbahn', reason: 'ss for ß is two edits: within reach for a long word');
  });

  test('Bekanntes und Angefangenes ist kein Tippfehler; Unbekanntes ohne Nachbarn bleibt ohne Vorschlag', () {
    expect(didYouMean('cola', vocab), isNull);
    expect(didYouMean('cap', vocab), isNull, reason: 'still typing');
    expect(didYouMean('xylophon', vocab), isNull);
    expect(didYouMean('', vocab), isNull);
    expect(didYouMean('coka', const []), isNull);
  });
}
