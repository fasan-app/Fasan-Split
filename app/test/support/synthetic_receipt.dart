// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the invented receipt of the screen tests and of the browser scan walk (no real or known receipts in the repo).
// `dart run test/support/synthetic_receipt.dart <dir>` writes bon.png and leer.png (blank) for tool/e2e/scan-walk.js. MPL-2.0
import 'dart:io';

import 'package:fasan_core/bill.dart';
import 'package:image/image.dart' as img;

const syntheticLines = [
  ('Flammkuchen', '12,50'),
  ('Apfelschorle 0,4', '4,20'),
  ('Weizen 0,5', '5,40'),
  ('Salat Bowl', '11,90'),
  ('2 x Espresso', '5,60'),
  ('  a 2,80', ''),
];

/// Draws a plain receipt (bitmap font, ASCII) and returns its path and the normalised box of every line.
(String, List<NBox>) syntheticReceipt(Directory dir) {
  const w = 600, h = 1500, top = 360, step = 64;
  final im = img.Image(width: w, height: h)..clear(img.ColorRgb8(250, 248, 242));
  final ink = img.ColorRgb8(30, 30, 30);
  img.drawString(im, 'GASTHAUS AM FLUSS', font: img.arial24, x: 170, y: 120, color: ink);
  img.drawString(im, 'Tisch 7', font: img.arial24, x: 250, y: 170, color: ink);
  final boxes = <NBox>[];
  for (var i = 0; i < syntheticLines.length; i++) {
    final y = top + i * step;
    img.drawString(im, syntheticLines[i].$1, font: img.arial24, x: 40, y: y, color: ink);
    if (syntheticLines[i].$2.isNotEmpty) img.drawString(im, syntheticLines[i].$2, font: img.arial24, x: 470, y: y, color: ink);
    boxes.add(NBox(30 / w, (y - 12) / h, 570 / w, (y + 36) / h));
  }
  final ys = top + syntheticLines.length * step + 40;
  img.drawString(im, 'SUMME EUR 39,60', font: img.arial24, x: 300, y: ys, color: ink);
  final f = File('${dir.path}/bon.png')..writeAsBytesSync(img.encodePng(im));
  return (f.path, boxes);
}


void main(List<String> args) {
  final dir = Directory(args.isEmpty ? '.' : args.first)..createSync(recursive: true);
  final (path, _) = syntheticReceipt(dir);
  stdout.writeln(path);
  final blank = img.Image(width: 600, height: 800)..clear(img.ColorRgb8(255, 255, 255));
  File('${dir.path}/leer.png').writeAsBytesSync(img.encodePng(blank));
}
