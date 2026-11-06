// Fasan Split – link a second device to the same account (collab/pairing.dart). New device: QR code + check code,
// waits. Old device: reads the code (system camera opens the link, photo of the QR, or pasted link), compares the
// check code, sends. MPL-2.0
import '../l10n/tr.dart' show trLang;
import 'dart:typed_data';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as im;
import 'package:image_picker/image_picker.dart';
import 'package:zxing2/qrcode.dart';

import '../collab/pairing.dart';
import '../l10n.dart';
import 'scope.dart';
import 'collab_ui.dart' show ensureConsent, QrView;
import 'common.dart';
import '../platform/web_platform.dart';

class _T {
  const _T(this.de);
  final bool de;
  String get newTitle => trLang(de ? 'de' : 'en', 'pairing_ui.signInWithAnother');
  String get newText => trLang(de ? 'de' : 'en', 'pairing_ui.newText');
  String get check => trLang(de ? 'de' : 'en', 'pairing_ui.checkCode');
  String get waiting => trLang(de ? 'de' : 'en', 'pairing_ui.waitingForYourOther');
  String done(int n) => n == 0 ? trLang(de ? 'de' : 'en', 'pairing_ui.doneNone') : trLang(de ? 'de' : 'en', 'pairing_ui.doneSome', [n]);
  String get failed => trLang(de ? 'de' : 'en', 'pairing_ui.noAnswerTryAgain');
  String get addTitle => trLang(de ? 'de' : 'en', 'pairing_ui.addDevice');
  String get addText => trLang(de ? 'de' : 'en', 'pairing_ui.scanTheCodeYour');
  String get photo => trLang(de ? 'de' : 'en', 'pairing_ui.photographTheCode');
  String get paste => trLang(de ? 'de' : 'en', 'pairing_ui.pasteLink');
  String get noCode => trLang(de ? 'de' : 'en', 'pairing_ui.noPairingCodeFound');
  String get compare => trLang(de ? 'de' : 'en', 'pairing_ui.doesYourNewDevice');
  String get send => trLang(de ? 'de' : 'en', 'pairing_ui.yesTransferAccount');
  String get sent => trLang(de ? 'de' : 'en', 'pairing_ui.accountTransferredTheNew');
  String get noWords => trLang(de ? 'de' : 'en', 'pairing_ui.thisAccountHasNo');
}

/// New device.
class PairNewScreen extends StatefulWidget {
  const PairNewScreen({super.key});

  @override
  State<PairNewScreen> createState() => _PairNewScreenState();
}

class _PairNewScreenState extends State<PairNewScreen> {
  PairOffer? _offer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = CollabScope.read(context);
      if (!await ensureConsent(context, s) || !mounted) {
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      final (offer, done) = s.startPairing();
      setState(() => _offer = offer);
      final t = _T(S.of(context).de);
      try {
        final n = await done;
        if (!mounted) return;
        showNote(context, t.done(n));
        Navigator.of(context).maybePop();
      } catch (_) {
        if (mounted) showNote(context, t.failed);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _T(S.of(context).de), tt = Theme.of(context).textTheme, o = _offer;
    return Scaffold(
      appBar: AppBar(title: Text(t.newTitle)),
      body: ListView(padding: const EdgeInsets.all(FasanSpace.l), children: [
        Text(t.newText, style: tt.bodyMedium),
        const SizedBox(height: FasanSpace.l),
        if (o == null) const Center(child: CircularProgressIndicator()) else ...[
          Center(child: QrView(o.link)),
          const SizedBox(height: FasanSpace.l),
          Center(child: Text(t.check, style: tt.labelLarge)),
          Center(child: Text(o.check, style: tt.displaySmall!.copyWith(letterSpacing: 6, fontFeatures: const [FontFeature.tabularFigures()]))),
          const SizedBox(height: FasanSpace.l),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: FasanSpace.s),
            Text(t.waiting, style: tt.bodySmall),
          ]),
        ],
      ]),
    );
  }
}

/// Reads a QR code from a photo (zxing2, BSD-3; same decoder as the receipt QR).
String? qrFromPhoto(Uint8List bytes) {
  final img = im.decodeImage(bytes);
  if (img == null) return null;
  final small = img.width > 1600 ? im.copyResize(img, width: 1600) : img;
  final px = Int32List(small.width * small.height);
  var i = 0;
  for (final p in small) {
    px[i++] = (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
  }
  try {
    return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(RGBLuminanceSource(small.width, small.height, px))), hints: DecodeHints()..put(DecodeHintType.tryHarder)).text;
  } catch (_) {
    return null;
  }
}

/// Old device: scan or paste, then compare and send. [initial] when the app was opened by the link itself.
class PairSendScreen extends StatefulWidget {
  const PairSendScreen({super.key, this.initial});

  final PairOffer? initial;

  @override
  State<PairSendScreen> createState() => _PairSendScreenState();
}

class _PairSendScreenState extends State<PairSendScreen> {
  late PairOffer? _offer = widget.initial;
  bool _busy = false;

  Future<void> _photo() async {
    final t = _T(S.of(context).de);
    final f = await ImagePicker().pickImage(source: ImageSource.camera);
    if (f == null || !mounted) return;
    final text = qrFromPhoto(await f.readAsBytes());
    final o = text == null ? null : PairOffer.parse(text);
    if (!mounted) return;
    o == null ? showNote(context, t.noCode) : setState(() => _offer = o);
  }

  Future<void> _paste() async {
    final t = _T(S.of(context).de);
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final o = d?.text == null ? null : PairOffer.parse(d!.text!);
    if (!mounted) return;
    o == null ? showNote(context, t.noCode) : setState(() => _offer = o);
  }

  Future<void> _send() async {
    final t = _T(S.of(context).de), s = CollabScope.read(context), o = _offer!;
    if (!await ensureConsent(context, s) || !mounted) return;
    setState(() => _busy = true);
    final ok = await s.sendPairing(o);
    if (!mounted) return;
    setState(() => _busy = false);
    showNote(context, ok ? t.sent : t.noWords);
    if (ok) {
      clearJoinCode(); // the link came through the web page: done with it
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _T(S.of(context).de), tt = Theme.of(context).textTheme, o = _offer;
    return Scaffold(
      appBar: AppBar(title: Text(t.addTitle)),
      body: ListView(padding: const EdgeInsets.all(FasanSpace.l), children: [
        if (o == null) ...[
          Text(t.addText, style: tt.bodyMedium),
          const SizedBox(height: FasanSpace.l),
          FasanButton(label: t.photo, icon: Icons.qr_code_scanner_rounded, expand: true, onPressed: _photo),
          const SizedBox(height: FasanSpace.s),
          FasanButton(label: t.paste, icon: Icons.content_paste_rounded, kind: FasanButtonKind.secondary, expand: true, onPressed: _paste),
        ] else ...[
          Text(t.compare, style: tt.bodyMedium),
          const SizedBox(height: FasanSpace.m),
          Center(child: Text(o.check, style: tt.displaySmall!.copyWith(letterSpacing: 6, fontFeatures: const [FontFeature.tabularFigures()]))),
          const SizedBox(height: FasanSpace.l),
          FasanButton(label: t.send, icon: Icons.send_to_mobile_rounded, expand: true, onPressed: _busy ? null : _send),
        ],
      ]),
    );
  }
}
