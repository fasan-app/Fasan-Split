// SPDX-License-Identifier: MPL-2.0
// The licence page lists the bundled models, the emoji font (with the OFL text) and ONNX Runtime. MPL-2.0
import 'package:fasan_split/ui/bundled_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Lizenzseite: Modelle, Emoji-Schrift (mit OFL-Text) und ONNX Runtime sind eingetragen', () async {
    registerBundledLicenses();
    registerBundledLicenses(); // twice must not duplicate
    final all = <LicenseEntry>[];
    await for (final e in LicenseRegistry.licenses) {
      all.add(e);
    }
    String textOf(LicenseEntry e) => e.paragraphs.map((p) => p.text).join('\n');
    bool has(String pkg) => all.any((e) => e.packages.any((p) => p.contains(pkg)));
    expect(has('FasanEmoji'), isTrue);
    expect(has('PaddleOCR'), isTrue);
    expect(has('UVDoc'), isTrue);
    expect(has('ONNX Runtime'), isTrue);
    expect(has('noble/curves'), isTrue);
    expect(all.where((e) => e.packages.any((p) => p.contains('noble/curves'))).map(textOf).join(), contains('Paul Miller'));
    expect(all.where((e) => e.packages.any((p) => p.contains('FasanEmoji'))).map(textOf).join(), contains('SIL Open Font License'));
    expect(all.where((e) => e.packages.any((p) => p.contains('PaddleOCR'))).length, 1);
  });
}
