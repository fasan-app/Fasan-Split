// SPDX-License-Identifier: MPL-2.0
// OCR cache for developer runs (06.11.): the reader is a pure function of what det/rec/UVDoc return, so the model calls are stored
// per receipt and replayed. A change in reader.dart then costs ~1 s per receipt instead of ~30 s. Only for tests – the app never
// uses it. Keyed by a hash of the image pixels plus the call arguments, so a changed image pipeline simply misses and recomputes.
// MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fasan_split/recognition/image.dart';
import 'package:fasan_reader/model.dart';
import 'package:fasan_split/recognition/onnx.dart';
import 'package:fasan_split/recognition/paddle.dart';

class CachingOcr extends PaddleOcr {
  CachingOcr(super.det, super.rec, super.dictText, {super.uvdoc});

  Map<String, Object?> _cache = {};
  String? _file;
  var hits = 0, misses = 0;

  /// Cache file for the next receipt (null = no cache).
  void use(String? file) {
    _file = file;
    _cache = file != null && File(file).existsSync() ? (jsonDecode(File(file).readAsStringSync()) as Map).cast<String, Object?>() : {};
  }

  void save() {
    if (_file != null && misses > 0) File(_file!).writeAsStringSync(jsonEncode(_cache));
  }

  static String _hash(Img c) {
    // FNV-1a over every 7th byte plus the size: fast and collision-free enough for a few hundred test images
    var h = 0xcbf29ce484222325;
    final p = c.rgba;
    for (var i = 0; i < p.length; i += 7) {
      h ^= p[i];
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return '${c.w}x${c.h}:${h.toRadixString(36)}';
  }

  static Map<String, Object?> _word(Word w) => {
        't': w.text,
        'c': w.conf,
        'b': w.box.toList(),
        if (w.tilt != null) 'n': w.tilt,
        if (w.glyphs != null) 'g': [for (final g in w.glyphs!) [g.ch, g.p, g.alt, g.p2]],
        if (w.fromColumn) 'f': true,
        if (w.alts != null) 'a': w.alts,
      };

  static Word _unword(Map m) {
    final b = (m['b'] as List).cast<num>();
    return Word(
      text: m['t'] as String,
      conf: (m['c'] as num).toDouble(),
      box: Box(b[0].toDouble(), b[1].toDouble(), b[2].toDouble(), b[3].toDouble()),
      tilt: (m['n'] as num?)?.toDouble(),
      glyphs: (m['g'] as List?)
          ?.map((g) => Glyph(g[0] as String, (g[1] as num).toDouble(), alt: g[2] as String?, p2: (g[3] as num).toDouble()))
          .toList(),
      fromColumn: m['f'] == true,
      alts: (m['a'] as List?)?.cast<String>(),
    );
  }

  @override
  Future<List<Word>> words(Img c, {double? stretch, void Function(double)? progress}) async {
    final k = 'w|${_hash(c)}|$stretch';
    final v = _cache[k];
    if (v != null) {
      hits++;
      progress?.call(1);
      return [for (final m in v as List) _unword(m as Map)];
    }
    misses++;
    final r = await super.words(c, stretch: stretch, progress: progress);
    _cache[k] = [for (final w in r) _word(w)];
    return r;
  }

  @override
  Future<bool> sideways(Img c) async {
    final k = 's|${_hash(c)}';
    final v = _cache[k];
    if (v != null) {
      hits++;
      return v as bool;
    }
    misses++;
    final r = await super.sideways(c);
    _cache[k] = r;
    return r;
  }

  @override
  Future<List<Reading>> multiRead(Img c, Box k, {List<(double, double, bool)> variants = PaddleOcr.defaultVariants}) async {
    final key = 'm|${_hash(c)}|${k.toList().map((x) => x.toStringAsFixed(1)).join(',')}|$variants';
    final v = _cache[key];
    if (v != null) {
      hits++;
      return [for (final m in v as List) Reading((m as List)[0] as String, (m[1] as num).toDouble())];
    }
    misses++;
    final r = await super.multiRead(c, k, variants: variants);
    _cache[key] = [for (final x in r) [x.text, x.conf]];
    return r;
  }

  @override
  Future<(Float32List, List<int>)?> uvGrid(Img c) async {
    final k = 'u|${_hash(c)}';
    final v = _cache[k];
    if (v != null) {
      hits++;
      if (v == false) return null;
      final m = v as Map;
      return (Float32List.view(base64Decode(m['g'] as String).buffer), (m['s'] as List).cast<int>());
    }
    misses++;
    final r = await super.uvGrid(c);
    _cache[k] = r == null ? false : {'g': base64Encode(r.$1.buffer.asUint8List(r.$1.offsetInBytes, r.$1.lengthInBytes)), 's': r.$2};
    return r;
  }
}

/// PaddleOcr for test runs: with FASAN_OCR_CACHE (a folder) a [CachingOcr], else the plain one.
PaddleOcr testOcr(String m, int threads) {
  final det = OnnxModel.fromBytes(File('$m/det.onnx').readAsBytesSync(), threads: threads);
  final rec = OnnxModel.fromBytes(File('$m/rec-latin.onnx').readAsBytesSync(), threads: threads);
  final dict = File('$m/dict-latin.txt').readAsStringSync();
  final uv = File('$m/uvdoc.onnx');
  final uvdoc = uv.existsSync() ? OnnxModel.fromBytes(uv.readAsBytesSync(), threads: threads) : null;
  return Platform.environment['FASAN_OCR_CACHE'] != null ? CachingOcr(det, rec, dict, uvdoc: uvdoc) : PaddleOcr(det, rec, dict, uvdoc: uvdoc);
}

/// Before a receipt: point the cache at its file (no-op without FASAN_OCR_CACHE).
void cacheFor(PaddleOcr ocr, String imagePath) {
  final dir = Platform.environment['FASAN_OCR_CACHE'];
  if (ocr is! CachingOcr || dir == null) return;
  Directory(dir).createSync(recursive: true);
  final name = imagePath.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  ocr.save();
  ocr.misses = 0;
  ocr.use('$dir/${name.length > 120 ? name.substring(name.length - 120) : name}.json');
}

void cacheDone(PaddleOcr ocr) {
  if (ocr is CachingOcr) ocr.save();
}
