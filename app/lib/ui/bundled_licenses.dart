// SPDX-License-Identifier: MPL-2.0
// Licence entries for the parts that are bundled in the app but are not Dart packages (models, emoji font, ONNX Runtime), so the
// system licence page (showLicensePage) lists them next to the pub packages. Sources and open points: docs/recht/LIZENZEN.md.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

bool _registered = false;

/// Adds the bundled non-package parts to [LicenseRegistry]. Safe to call more than once.
void registerBundledLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(_entries);
}

Stream<LicenseEntry> _entries() async* {
  // The font licence text is shipped as an asset (OFL 1.1 asks for the text on redistribution).
  try {
    yield LicenseEntryWithLineBreaks(['FasanEmoji (Noto Color Emoji, Google)'], await rootBundle.loadString('assets/fonts/FasanEmoji-OFL.txt'));
  } catch (_) {
    yield const LicenseEntryWithLineBreaks(['FasanEmoji (Noto Color Emoji, Google)'], 'SIL Open Font License 1.1 – https://openfontlicense.org');
  }
  // Notices with the licence name, author and the place of the full text; the full texts are not bundled yet (open point in docs/recht).
  yield const LicenseEntryWithLineBreaks(
    ['PaddleOCR PP-OCRv5 (det, rec-latin, dict-latin)'],
    'Text recognition models of PaddleOCR (PaddlePaddle authors), converted to ONNX in the project ppu-paddle-ocr-models.\n'
    'Licence: Apache License 2.0 – full text: https://www.apache.org/licenses/LICENSE-2.0\n'
    'Source and checksums: assets/models/DATEIEN.txt.',
  );
  yield const LicenseEntryWithLineBreaks(
    ['UVDoc (document unwarping)'],
    'Verhoeven, Magne, Sorkine-Hornung: UVDoc, SIGGRAPH Asia 2023 – https://github.com/tanguymagne/UVDoc (commit 4c9b82b), converted to ONNX.\n'
    'Licence: MIT (as stated in the entry; the upstream licence file was not re-checked – see docs/recht/LIZENZEN.md).',
  );
  yield const LicenseEntryWithLineBreaks(
    ['ONNX Runtime'],
    'ONNX Runtime (Microsoft) runs the models on the device.\n'
    'Licence: MIT – https://github.com/microsoft/onnxruntime/blob/main/LICENSE (not re-checked, see docs/recht/LIZENZEN.md).',
  );
  // Browser build only (web_extra/fasan-curve.js, built by tool/curve/build.sh); the licence text is the one in the package (verified 08.11.).
  yield const LicenseEntryWithLineBreaks(
    ['@noble/curves and @noble/hashes (browser build)'],
    'Fast secp256k1 for the browser app: @noble/curves 2.4.0 (and @noble/hashes), Paul Miller – https://github.com/paulmillr/noble-curves\n\n'
    'The MIT License (MIT)\n'
    '\n'
    'Copyright (c) 2022 Paul Miller (https://paulmillr.com)\n'
    '\n'
    'Permission is hereby granted, free of charge, to any person obtaining a copy\n'
    'of this software and associated documentation files (the “Software”), to deal\n'
    'in the Software without restriction, including without limitation the rights\n'
    'to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n'
    'copies of the Software, and to permit persons to whom the Software is\n'
    'furnished to do so, subject to the following conditions:\n'
    '\n'
    'The above copyright notice and this permission notice shall be included in\n'
    'all copies or substantial portions of the Software.\n'
    '\n'
    'THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n'
    'IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n'
    'FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\n'
    'AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n'
    'LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n'
    'OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN\n'
    'THE SOFTWARE.',
  );
}
