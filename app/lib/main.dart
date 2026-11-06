// Fasan Split – Rechnungen in der Gruppe teilen. Freie App der Fasan-Familie (MPL-2.0), offline, ohne Konto.
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'perf/perf_governor.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collab/group.dart';
import 'collab/keys.dart';
import 'collab/nostr.dart' show relayProxy;
import 'collab/pairing.dart';
import 'ui/pairing_ui.dart';
import 'platform/web_platform.dart';
import 'collab/activity.dart' show activityGerman;
import 'collab/service.dart';
import 'collab/notify.dart';
import 'state/store.dart';
import 'ui/collab_ui.dart';
import 'ui/demo.dart';
import 'ui/home.dart';
import 'ui/scope.dart';

export 'ui/scope.dart';

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
  final ui = SplitController(settings: look, onChanged: (s) => store.saveSettings(s.encode()));
  ui.start();
  // measures the first frames and reduces effects on slow devices (browser, old phones); perf/perf_governor.dart
  perfGovernor = PerfGovernor(ui, await SharedPreferences.getInstance())..start();
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

/// Tells the collaboration when the app is in front (online status, CollabService.setForeground).
class _Foreground with WidgetsBindingObserver {
  _Foreground(this.c) {
    c.setForeground(true);
  }
  final CollabService c;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => c.setForeground(state == AppLifecycleState.resumed);
}

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

  /// News and device notifications follow the language setting (system = the phone's language; anything but English is German,
  /// like S.of).
  void _syncLanguage() => activityGerman = switch (widget.store.language) {
        'de' => true,
        'en' => false,
        _ => WidgetsBinding.instance.platformDispatcher.locale.languageCode != 'en',
      };

  @override
  void initState() {
    super.initState();
    _syncLanguage();
    widget.store.addListener(_syncLanguage);
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
    widget.store.removeListener(_syncLanguage);
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
            listenable: Listenable.merge([ui, widget.store]),
            builder: (context, _) => MaterialApp(
              navigatorKey: navigatorKey,
              title: 'Fasan Split',
              // Settings → Language: German, English, or the phone's language (null)
              locale: switch (widget.store.language) { 'de' => const Locale('de'), 'en' => const Locale('en'), _ => null },
              debugShowCheckedModeBanner: false,
              theme: withEmoji(ui.theme(Brightness.light)),
              darkTheme: withEmoji(ui.theme(Brightness.dark)),
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

/// Every text falls back to the app's own emoji font (assets/fonts/FasanEmoji.ttf) before the system's: the symbols look the
/// same on the phone and in the browser, and the browser asks no font server (06.11.).
ThemeData withEmoji(ThemeData t) => t.copyWith(
      textTheme: t.textTheme.apply(fontFamilyFallback: const ['FasanEmoji']),
      primaryTextTheme: t.primaryTextTheme.apply(fontFamilyFallback: const ['FasanEmoji']),
    );
