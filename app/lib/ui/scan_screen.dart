// SPDX-License-Identifier: MPL-2.0
// Fasan Split – reading the receipt: the straightened receipt appears, lines light up as they are read. MPL-2.0
import 'dart:async';
import 'dart:typed_data';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import 'package:fasan_core/bill.dart';
import '../flows/scan_bill.dart';
import '../recognition/service.dart';
import '../state/scan_live.dart';
import 'scan_stage.dart';
import 'flow.dart';
import 'scope.dart' show StoreScope;

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.photo, this.events, this.group});

  final Uint8List photo;

  /// The group the bill goes into (started with the plus inside a group); null = none.
  final String? group;

  /// For tests: a prepared event stream instead of the real recognition.
  final Stream<ScanEvent>? events;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  StreamSubscription<ScanEvent>? _sub;
  final _live = ScanLive();
  String _stage = '';
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = (widget.events ?? RecognitionService.instance.recognize(widget.photo)).listen(_on);
  }

  void _on(ScanEvent e) {
    if (!mounted) return;
    _live.onEvent(e); // preview with boxes and the straightening: ScanStage plays them
    switch (e) {
      case ScanProgress():
        setState(() {
          _stage = e.stage;
          _progress = e.progress;
        });
      case ScanDone():
        _finish(e.result);
      case ScanError():
        setState(() => _error = e.message);
      default:
        break;
    }
  }

  Future<void> _finish(ScanResultData r) async {
    final playing = _live.playing;
    if (playing != null) await playing.timeout(const Duration(seconds: 5), onTimeout: () {});
    if (!mounted) return;
    final bill = await billFromScan(r, widget.photo, group: widget.group, homeCurrency: StoreScope.read(context).homeCurrency);
    if (!mounted) return;
    FasanHaptics.of(context).confirm();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ReviewScreen(bill: bill, scan: r)));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _live.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final l = FasanLook.of(context);
    final tt = Theme.of(context).textTheme;
    final cine = l.style.cinematic;
    return Scaffold(
      appBar: AppBar(title: Text(t.reading)),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(FasanSpace.l),
              child: Center(
                child: _error != null
                    ? _Failed(group: widget.group, message: _error!)
                    : ScanStage(
                        live: _live,
                        brackets: true,
                        placeholder: Image.memory(widget.photo, fit: BoxFit.contain, cacheWidth: 900, opacity: const AlwaysStoppedAnimation(0.5)),
                      ),
              ),
            ),
          ),
          if (_error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_stage, style: cine ? l.mono(12, color: l.text) : tt.bodyMedium),
                const SizedBox(height: FasanSpace.s),
                FasanProgress(value: _progress <= 0 ? null : _progress),
                const SizedBox(height: FasanSpace.s),
                Text(t.photoStays, style: tt.bodySmall),
                const SizedBox(height: FasanSpace.s),
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(t.cancel))),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, this.group});

  final String message;
  final String? group;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.error_outline, size: 40, color: FasanLook.of(context).textMuted),
      const SizedBox(height: FasanSpace.m),
      Text(t.readFailed, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
      const SizedBox(height: FasanSpace.s),
      Text(message.split('\n').first, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      const SizedBox(height: FasanSpace.l),
      FasanButton(
        label: t.enterByHand,
        onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ReviewScreen(bill: Bill(id: DateTime.now().microsecondsSinceEpoch.toString(), created: DateTime.now(), items: [], group: group)),
        )),
      ),
    ]);
  }
}
