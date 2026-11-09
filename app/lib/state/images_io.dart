// SPDX-License-Identifier: MPL-2.0
// Fasan Split – receipt photos as files in the app documents (path_provider). MPL-2.0
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

Future<void> initImages() async {}

Future<String?> saveImage(String name, Uint8List bytes) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  } catch (_) {
    return null;
  }
}

bool imageExists(String? path) => path != null && File(path).existsSync();

Future<Uint8List?> readImage(String path) async => imageExists(path) ? File(path).readAsBytes() : null;

void deleteImage(String path) {
  try {
    File(path).deleteSync();
  } catch (_) {}
}

ImageProvider imageProvider(String path) => FileImage(File(path));
