// Fasan Split – Rechnungen in der Gruppe teilen. Freie App der Fasan-Familie (MPL-2.0), offline, ohne Konto.
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collab/group.dart';
import 'collab/keys.dart';
import 'web_link.dart';
import 'collab/service.dart';
import 'state/store.dart';
import 'ui/collab_ui.dart';
import 'ui/demo.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await BillStore.load();
  final ui = FasanController(settings: FasanSettings.decode(store.settingsJson), onChanged: (s) => store.saveSettings(s.encode()));
  ui.start();
  // Collaboration: keys in the Android Keystore; the service only connects to relays if there is a group (Beschluss 03.11.).
  final collab = CollabService(store: store, vault: const SecureVault(), prefs: await SharedPreferences.getInstance());
  runApp(SplitApp(store: store, ui: ui, collab: collab, deepLinks: true));
  unawaited(collab.init());
}

final navigatorKey = GlobalKey<NavigatorState>();

/// Invitation links: the old scheme fasansplit://join and the https address of the web app (App Link).
bool isInviteLink(Uri u) =>
    u.scheme == 'fasansplit' || u.scheme == 'https' && u.host == 'fasan-app.github.io' && u.path.startsWith('/Fasan-Split/join');

class SplitApp extends StatefulWidget {
  const SplitApp({super.key, required this.store, required this.ui, this.home, this.collab, this.deepLinks = false});

  final BillStore store;
  final FasanController ui;

  /// Start screen override (tests, screenshots).
  final Widget? home;

  /// Without one (tests) a service with an in-memory vault is made; it connects to nothing without a group.
  final CollabService? collab;

  /// Open invitation links (fasansplit://join#…). Off in tests: no platform plugin there.
  final bool deepLinks;

  @override
  State<SplitApp> createState() => _SplitAppState();
}

class _SplitAppState extends State<SplitApp> {
  late final CollabService collab = widget.collab ?? CollabService(store: widget.store, vault: MemoryVault());
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    // Web: join/index.html handed the invitation over (web_link_web.dart).
    final code = kIsWeb ? takeJoinCode() : null;
    if (code != null) _open(Uri.parse('${Invite.inviteBase}#$code'));
    if (widget.deepLinks && !kIsWeb) {
      final al = AppLinks();
      // link that started the app, then links while it runs
      al.getInitialLink().then((u) => _open(u), onError: (_) {});
      _links = al.uriLinkStream.listen(_open, onError: (_) {});
    }
  }

  void _open(Uri? u) {
    if (u == null || !isInviteLink(u)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav != null) nav.push(MaterialPageRoute(builder: (_) => JoinScreen(prefill: u.toString())));
    });
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = widget.ui;
    return FasanScope(
      controller: ui,
      child: StoreScope(
        store: widget.store,
        child: CollabScope(
          service: collab,
          child: ListenableBuilder(
            listenable: ui,
            builder: (context, _) => MaterialApp(
              navigatorKey: navigatorKey,
              title: 'Fasan Split',
              debugShowCheckedModeBanner: false,
              theme: ui.theme(Brightness.light),
              darkTheme: ui.theme(Brightness.dark),
              themeMode: ui.themeMode,
              // style changes morph instead of jumping (fasan_ui Norm): colours, radii and glow are interpolated
              themeAnimationDuration: const Duration(milliseconds: 380),
              themeAnimationCurve: Curves.easeInOutCubic,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('de'), Locale('en')],
              // Layer 0 (ground with gradient, grain, weave, light) behind all pages; FasanFilm adds grain over the whole
              // picture only if the user chooses „ganzes Bild“ (fasan_ui docs/GESTALTUNG.md §2). Both pause when saving.
              builder: (context, child) => FasanBackdrop(child: FasanFilm(child: child ?? const SizedBox())),
              home: widget.home ?? (demoPage.isEmpty ? const HomeScreen() : const DemoLauncher()),
            ),
          ),
        ),
      ),
    );
  }
}

/// The collaboration service for all screens.
class CollabScope extends InheritedNotifier<CollabService> {
  const CollabScope({super.key, required CollabService service, required super.child}) : super(notifier: service);

  static CollabService of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CollabScope>()!.notifier!;
  static CollabService read(BuildContext context) => context.getInheritedWidgetOfExactType<CollabScope>()!.notifier!;
}

class StoreScope extends InheritedNotifier<BillStore> {
  const StoreScope({super.key, required BillStore store, required super.child}) : super(notifier: store);

  static BillStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  /// Without registering a dependency: for saving from build-triggered callbacks (otherwise save → notify → rebuild →
  /// save loops forever).
  static BillStore read(BuildContext context) => context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
