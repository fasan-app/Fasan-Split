// Fasan Split – what a running recognition shows: the latest preview with its boxes and the straightening mesh. MPL-2.0
//
// One [ScanLive] feeds a [ScanStage] widget: the big one on the scan page and the small one in a list tile (Nutzer 02.11.:
// bei mehreren Bons soll jede Miniatur dieselbe Scan-Animation zeigen wie bei einem einzelnen).
import 'package:flutter/foundation.dart';

import '../recognition_service.dart';

class ScanLive extends ChangeNotifier {
  Uint8List? preview;
  List<List<double>> boxes = const [];
  bool straight = false;
  int previewSerial = 0;

  ScanWarp? warp;
  int warpSerial = 0;

  /// Set by the stage while the straightening plays; await it before leaving the page.
  Future<void>? playing;

  void onEvent(ScanEvent e) {
    switch (e) {
      case ScanPreview():
        preview = e.jpeg;
        boxes = e.boxes;
        straight = e.straight;
        previewSerial++;
        notifyListeners();
      case ScanWarp():
        warp = e;
        warpSerial++;
        notifyListeners();
      default:
        break;
    }
  }
}
