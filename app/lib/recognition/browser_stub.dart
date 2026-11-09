// SPDX-License-Identifier: MPL-2.0
// Fasan Split – phone and tests: the background isolate reads receipts (recognition_service.dart). MPL-2.0
import 'dart:typed_data';

import 'scan_events.dart';

Stream<ScanEvent> recognizeInBrowser(Uint8List photo) => throw UnsupportedError('Only in the browser.');
