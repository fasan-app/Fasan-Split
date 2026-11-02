// Fasan Split – demo start for emulator screenshots (private CI in fasan-diagnose only). MPL-2.0
// Inactive unless built with --dart-define=FASAN_DEMO=… ; the receipt then comes from assets/demo/bon.jpg, which exists
// only in that private build (Regel: echte Bonfotos nie ins Repo und nie in den Code).
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../model/bill.dart';
import '../recognition_service.dart';
import '../state/store.dart';
import 'assign.dart';

/// gallery | receipt | home
const demoPage = String.fromEnvironment('FASAN_DEMO');

class DemoLauncher extends StatefulWidget {
  const DemoLauncher({super.key});

  @override
  State<DemoLauncher> createState() => _DemoLauncherState();
}

class _DemoLauncherState extends State<DemoLauncher> {
  String state = 'start';

  @override
  void initState() {
    super.initState();
    StoreScope.read(context).onboarded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  Future<void> _go() async {
    final nav = Navigator.of(context);
    if (demoPage == 'gallery') {
      nav.pushReplacement(MaterialPageRoute(builder: (_) => const FasanGalleryPage()));
      return;
    }
    final photo = (await rootBundle.load('assets/demo/bon.jpg')).buffer.asUint8List();
    setState(() => state = 'lesen');
    await for (final e in RecognitionService.instance.recognize(photo)) {
      if (e is ScanProgress && mounted) setState(() => state = '${e.stage} ${(e.progress * 100).round()} %');
      if (e is ScanError && mounted) setState(() => state = 'FEHLER ${e.message}');
      if (e is ScanDone) {
        final r = e.result;
        final id = 'demo';
        final scan = await BillStore.saveFile('$id.png', r.display);
        final orig = await BillStore.saveFile('$id.orig.jpg', photo);
        final b = Bill(
          id: id,
          created: DateTime.now(),
          purpose: r.shop,
          total: r.total,
          items: r.items,
          imagePath: scan,
          originalPath: orig,
          imageAspect: r.width / r.height,
          checked: r.checked && !r.contradiction,
          people: [for (final (i, n) in ['Angi', 'Alexis', 'Emmi', 'Bine', 'Achim', 'Chris'].indexed) Person(n, i)],
        );
        for (final (k, it) in b.its.indexed) {
          if (k.isEven) it.shares = {k % 6: 1, (k + 1) % 6: 1};
        }
        // marker for the CI script: recognition finished
        debugPrint('FASAN_DEMO_READY');
        nav.pushReplacement(MaterialPageRoute(builder: (_) => AssignScreen(bill: b, initialMode: AssignMode.receipt)));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text('Demo: $state')));
}
