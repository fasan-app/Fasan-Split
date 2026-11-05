// Digits that reading put into words („G1n“ for „Gin“) – and names with real digits that must stay. MPL-2.0
import 'package:fasan_split/recognition/name_repair.dart';
import 'package:fasan_split/recognition/reader.dart' show isHairline;
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

  test('Haarlinien-Boxen (8 px hoch neben 55 px) werden erkannt, kleine echte Zeilen nicht', () {
    expect(isHairline(Word(text: 'easo', conf: 82, box: Box(680, 1469, 858, 1477)), 55), isTrue);
    expect(isHairline(Word(text: 'roozao', conf: 63, box: Box(641, 1652, 1116, 1660)), 55), isTrue);
    expect(isHairline(Word(text: '• 3oocooo', conf: 75, box: Box(0, 0, 324, 16)), 56), isFalse, reason: 'SROIE 016: garbled but real');
    expect(isHairline(Word(text: 'Zeile', conf: 90, box: Box(0, 0, 400, 55)), 55), isFalse);
  });
}
