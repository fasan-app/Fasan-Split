// Digits that reading put into words („G1n“ for „Gin“) – and names with real digits that must stay. MPL-2.0
import 'package:fasan_split/recognition/name_repair.dart';
import 'package:fasan_split/recognition/reader.dart' show withoutCrumbs;
import 'package:fasan_split/recognition/model.dart';
import 'package:fasan_split/recognition/speisen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ziffern in Wörtern werden Buchstaben', () {
    expect(fixDigitsInWord('G1n Tonico Mart1'), 'Gin Tonico Marti');
    expect(fixDigitsInWord('Capital Soc1al'), 'Capital Social');
    expect(fixDigitsInWord('Fatura 51mplif1cada'), 'Fatura 51mplif1cada', reason: 'two digits in a word: not touched');
    expect(fixDigitsInWord('Abatanadu Dascaf'), 'Abatanadu Dascaf');
    expect(fixDigitsInWord('Pe0ra'), 'Peora');
  });

  test('echte Ziffern bleiben', () {
    for (final n in ['7UP', 'H2O', 'B12', 'Coca-Cola 33 cl', 'Menu 1', 'Pizza 4 Formaggi', 'Cola 0,33', 'A1', 'Sprite 1,5 L', '1.00 Cafe', 'Gr 500 g', 'Mate 5']) {
      expect(fixDigitsInWord(n), n, reason: n);
    }
  });

  test('Gin Tonico ist ein Cocktail, keine Limonade; Tonic Water bleibt Limonade', () {
    expect(Speisen.recognise('Gin Tonico Marti')?.name, 'Cocktail');
    expect(Speisen.recognise('GIN TONIC')?.name, 'Cocktail');
    expect(Speisen.recognise('Tonic Water')?.name, 'Limonade oder Schorle');
  });

  test('Haarlinien-Boxen (8 px hoch neben 55 px) sind kein Text', () {
    Word w(String t, double y0, double y1, {double conf = 90}) => Word(text: t, conf: conf, box: Box(100, y0, 500, y1));
    final words = [for (var i = 0; i < 8; i++) w('Zeile $i', i * 60.0, i * 60.0 + 55), w('easo', 480, 488, conf: 82), w('roozao', 500, 508, conf: 63)];
    final kept = withoutCrumbs(words).map((x) => x.text).toList();
    expect(kept.contains('easo'), isFalse);
    expect(kept.contains('roozao'), isFalse);
    expect(kept.length, 8);
  });
}
