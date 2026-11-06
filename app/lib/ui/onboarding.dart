// Fasan Split – introduction on first start and an example receipt to try (Beschluss 02.11.: beides überspringbar).
// Rules (REGELWERK §7, Karte 24.10.): few pages, „Weiter“ always visible, skip at any time, reachable again in settings.
// The example receipt is invented and drawn at run time (Regel: keine bekannten Test-Bons in der App). MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../l10n.dart';
import 'scope.dart';
import '../model/bill.dart';
import '../state/store.dart';
import 'assign.dart';
import 'collab_ui.dart' show AccountScreen;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int page = 0;

  void _done() {
    StoreScope.read(context).onboarded = true;
    Navigator.of(context).pop();
  }

  Future<void> _example() async {
    final store = StoreScope.read(context);
    store.onboarded = true;
    final nav = Navigator.of(context);
    final b = await exampleBill(S.of(context).de);
    nav.pushReplacement(MaterialPageRoute(builder: (_) => AssignScreen(bill: b, initialMode: AssignMode.receipt)));
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final l = FasanLook.of(context);
    final tt = Theme.of(context).textTheme;
    final pages = [
      (Icons.document_scanner_outlined, t.intro1Title, t.intro1Text),
      (Icons.group_add_outlined, t.intro2Title, t.intro2Text),
      (Icons.touch_app_outlined, t.intro3Title, t.intro3Text),
      (Icons.handshake_outlined, t.intro4Title, t.intro4Text),
    ];
    final last = page == pages.length - 1;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: FasanLabel('${page + 1} / ${pages.length}'),
        actions: [
          // first start on a new device (Nutzer 04.11.): sign in with the other device or the 12 words
          TextButton(
            onPressed: () {
              _done();
              navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const AccountScreen()));
            },
            child: Text(t.de ? 'Schon ein Konto?' : 'Have an account?'),
          ),
          TextButton(onPressed: _done, child: Text(t.skip)),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView(
              controller: _pc,
              onPageChanged: (p) => setState(() => page = p),
              children: [
                for (final (icon, title, text) in pages)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: FasanSpace.xxl),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(color: l.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(l.radius)),
                        child: Icon(icon, size: 56, color: l.accent),
                      ),
                      const SizedBox(height: FasanSpace.xl),
                      Text(title, style: tt.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: FasanSpace.m),
                      Text(text, style: tt.bodyLarge!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
                    ]),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(FasanSpace.l),
            child: Column(children: [
              if (last) ...[
                FasanButton(label: t.tryExample, icon: Icons.play_arrow_rounded, kind: FasanButtonKind.secondary, expand: true, onPressed: _example),
                const SizedBox(height: FasanSpace.s),
              ],
              FasanButton(
                label: last ? t.letsGo : t.next,
                expand: true,
                onPressed: last
                    ? _done
                    : () {
                        // with „Animationen entfernen“ the duration is zero: jump instead of animating
                        final d = FasanMotion.of(context).medium;
                        d == Duration.zero ? _pc.jumpToPage(page + 1) : _pc.nextPage(duration: d, curve: Curves.easeOutCubic);
                      },
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// An invented café receipt, drawn at run time, with three example people. Saved like any bill (then under
/// „Angefangen“), so the user can also delete it.
Future<Bill> exampleBill(bool de) async {
  const lines = [
    ('2 Cappuccino', 760),
    ('1 Apfelschorle 0,4', 420),
    ('1 Flammkuchen', 1250),
    ('1 Salat Bowl', 1190),
    ('2 Espresso', 560),
  ];
  const w = 600, top = 360, step = 64;
  final h = top + lines.length * step + 260;
  final im = img.Image(width: w, height: h)..clear(img.ColorRgb8(250, 248, 242));
  final ink = img.ColorRgb8(30, 30, 30);
  img.drawString(im, 'CAFE FASAN', font: img.arial24, x: 220, y: 120, color: ink);
  img.drawString(im, 'Beispielstrasse 1', font: img.arial24, x: 190, y: 170, color: ink);
  final items = <BillItem>[];
  for (var i = 0; i < lines.length; i++) {
    final y = top + i * step;
    final (name, cents) = lines[i];
    img.drawString(im, name, font: img.arial24, x: 40, y: y, color: ink);
    final euro = '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';
    img.drawString(im, euro, font: img.arial24, x: 470, y: y, color: ink);
    final qty = int.parse(name.split(' ').first);
    items.add(BillItem(
      name: name.substring(name.indexOf(' ') + 1),
      amount: cents,
      qty: qty,
      boxes: [NBox(30 / w, (y - 10) / h, 570 / w, (y + 34) / h)],
    ));
  }
  final ys = top + lines.length * step + 40;
  img.drawString(im, 'SUMME EUR 41,80', font: img.arial24, x: 300, y: ys, color: ink);
  final id = 'beispiel-${DateTime.now().millisecondsSinceEpoch}';
  final path = await BillStore.saveFile('$id.png', img.encodePng(im));
  return Bill(
    id: id,
    created: DateTime.now(),
    purpose: de ? 'Beispiel: Café Fasan' : 'Example: Café Fasan',
    total: 4180,
    checked: true,
    items: items,
    imagePath: path,
    originalPath: path,
    imageAspect: w / h,
    people: [Person('Anna', 0), Person('Ben', 1), Person('Cleo', 2)],
    step: 3,
  );
}
