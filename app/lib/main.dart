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
import 'collab/nostr.dart' show relayProxy;
import 'collab/pairing.dart';
import 'ui/pairing_ui.dart';
import 'web_platform.dart';
import 'collab/service.dart';
import 'state/notify.dart';
import 'state/store.dart';
import 'ui/collab_ui.dart';
import 'ui/demo.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prepareWebStart();
  if (!browserStorageWorks) {
    // Browser refuses storage: keep everything in memory so the app still starts (an invitation still works); the
    // home screen says that nothing stays. The in-memory store is meant for tests, here it is the honest fallback.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  }
  final store = await BillStore.load();
  var look = FasanSettings.decode(store.settingsJson);
  // Nutzer 04.11.: the standard look of Fasan Split is glass without grain. Applied once to existing installs too; any
  // later choice in Erscheinungsbild stays.
  if (!store.hintDone('look-glass-v1')) {
    look = look.copyWith(style: FasanStyle.fullGlass, effects: look.effects.copyWith(grain: 0));
    store.saveSettings(look.encode());
    store.hintDismiss('look-glass-v1');
  }
  final ui = FasanController(settings: look, onChanged: (s) => store.saveSettings(s.encode()));
  ui.start();
  // Collaboration: keys in the Android Keystore; the service only connects to relays if there is a group (Beschluss 03.11.).
  final collab = CollabService(store: store, vault: browserStorageWorks ? const SecureVault() : MemoryVault(), prefs: await SharedPreferences.getInstance());
  // Tor via Orbot (Einstellungen → Datenschutz): every relay connection through Orbot's local tunnel
  if ((await SharedPreferences.getInstance()).getBool('net.tor') == true) relayProxy = '127.0.0.1:8118';
  // news as device notifications while the app is in the background (state/notify.dart)
  deviceNotifier = DeviceNotifier(await SharedPreferences.getInstance());
  collab.onActivity = (a) => deviceNotifier?.show(a);
  unawaited(deviceNotifier!.init());
  WidgetsBinding.instance.addObserver(_Foreground(collab));
  runApp(SplitApp(store: store, ui: ui, collab: collab, deepLinks: true));
  unawaited(collab.init());
}

final navigatorKey = GlobalKey<NavigatorState>();

/// Device notifications (null in tests).
DeviceNotifier? deviceNotifier;

/// Tells the collaboration when the app is in front (online status, CollabService.setForeground).
class _Foreground with WidgetsBindingObserver {
  _Foreground(this.c) {
    c.setForeground(true);
  }
  final CollabService c;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => c.setForeground(state == AppLifecycleState.resumed);
}

/// True when this start came from an invitation link (browser: handed over by join/index.html).
bool startedWithInvite = false;

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
    // Web: join/index.html handed the invitation over (web_platform_web.dart).
    final code = kIsWeb ? takeJoinCode() : null;
    if (code != null) {
      startedWithInvite = true;
      _open(Uri.parse('${Invite.inviteBase}#$code'));
    }
    if (widget.deepLinks && !kIsWeb) {
      final al = AppLinks();
      // link that started the app, then links while it runs
      al.getInitialLink().then((u) => _open(u), onError: (_) {});
      _links = al.uriLinkStream.listen(_open, onError: (_) {});
    }
  }

  void _open(Uri? u) {
    if (u == null || !isInviteLink(u)) return;
    final pair = PairOffer.parse(u.fragment);
    if (pair != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => PairSendScreen(initial: pair))));
      return;
    }
    startedWithInvite = true; // the introduction must not cover the join screen (also on Android)
    pendingInviteLink = u.toString(); // the start page shows it as a card until the request is sent
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
              // wide screens (laptop browser, tablet across, Nutzer 04.11.: „auf dem Desktop eine Katastrophe“): the app keeps
              // a phone-like column in the middle on the shared background, like messengers in the browser; the system
              // insets stay correct because MediaQuery is narrowed with the column.
              builder: (context, child) => FasanBackdrop(
                child: FasanFilm(
                  child: LayoutBuilder(builder: (context, c) {
                    const maxW = 600.0;
                    final inner = child ?? const SizedBox();
                    if (c.maxWidth <= maxW + 48) return inner;
                    final mq = MediaQuery.of(context);
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: SizedBox(
                            width: maxW,
                            child: MediaQuery(data: mq.copyWith(size: Size(maxW, mq.size.height - 32)), child: inner),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
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
