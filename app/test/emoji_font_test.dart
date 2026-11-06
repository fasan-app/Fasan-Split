// The app's own emoji font (06.11.: symbols in front of item names were empty boxes in the browser). Every symbol used in lib/
// must be in assets/fonts/FasanEmoji.ttf (else: tool/make_emoji_font.sh), and the theme falls back to it. MPL-2.0
import 'dart:io';
import 'dart:typed_data';

import 'package:fasan_split/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Code points of a TrueType font from its cmap (formats 4 and 12).
Set<int> _cmap(Uint8List f) {
  final b = ByteData.sublistView(f);
  final n = b.getUint16(4);
  var cmap = -1;
  for (var i = 0; i < n; i++) {
    final r = 12 + 16 * i;
    if (String.fromCharCodes(f.sublist(r, r + 4)) == 'cmap') cmap = b.getUint32(r + 8);
  }
  final out = <int>{};
  for (var i = 0; i < b.getUint16(cmap + 2); i++) {
    final off = cmap + b.getUint32(cmap + 4 + 8 * i + 4);
    final format = b.getUint16(off);
    if (format == 12) {
      for (var g = 0; g < b.getUint32(off + 12); g++) {
        final s = b.getUint32(off + 16 + 12 * g), e = b.getUint32(off + 20 + 12 * g);
        for (var c = s; c <= e; c++) {
          out.add(c);
        }
      }
    } else if (format == 4) {
      final seg = b.getUint16(off + 6) ~/ 2;
      for (var k = 0; k < seg; k++) {
        final e = b.getUint16(off + 14 + 2 * k), s = b.getUint16(off + 16 + 2 * seg + 2 * k);
        for (var c = s; c <= e && c != 0xFFFF; c++) {
          out.add(c);
        }
      }
    }
  }
  return out;
}

void main() {
  test('Jedes Symbol aus lib/ steckt in FasanEmoji.ttf', () {
    final have = _cmap(File('assets/fonts/FasanEmoji.ttf').readAsBytesSync());
    final used = <int>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      used.addAll(f.readAsStringSync().runes.where((c) => c >= 0x1F000 || (c >= 0x2600 && c < 0x27C0 && c != 0x2713)));
    }
    final missing = used.difference(have)..remove(0xFE0F);
    expect(missing.map((c) => 'U+${c.toRadixString(16).toUpperCase()}'), isEmpty, reason: 'tool/make_emoji_font.sh neu ausführen');
  });

  test('Thema fällt auf FasanEmoji zurück', () {
    final t = withEmoji(ThemeData());
    expect(t.textTheme.bodyLarge!.fontFamilyFallback, contains('FasanEmoji'));
    expect(t.textTheme.titleMedium!.fontFamilyFallback, contains('FasanEmoji'));
  });
}
