// Fasan Split – Rechnungen in der Gruppe teilen. Freie App der Fasan-Familie (MPL-2.0), offline, ohne Konto.
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'state/store.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await BillStore.load();
  final ui = FasanController(settings: FasanSettings.decode(store.settingsJson), onChanged: (s) => store.saveSettings(s.encode()));
  ui.start();
  runApp(SplitApp(store: store, ui: ui));
}

class SplitApp extends StatelessWidget {
  const SplitApp({super.key, required this.store, required this.ui, this.home});

  final BillStore store;
  final FasanController ui;

  /// Start screen override (tests, screenshots).
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return FasanScope(
      controller: ui,
      child: StoreScope(
        store: store,
        child: ListenableBuilder(
          listenable: ui,
          builder: (context, _) => MaterialApp(
            title: 'Fasan Split',
            debugShowCheckedModeBanner: false,
            theme: ui.theme(Brightness.light),
            darkTheme: ui.theme(Brightness.dark),
            themeMode: ui.themeMode,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('de'), Locale('en')],
            // film effects over every screen; they pause by themselves when saving battery
            builder: (context, child) => FasanFilm(child: child ?? const SizedBox()),
            home: home ?? const HomeScreen(),
          ),
        ),
      ),
    );
  }
}

class StoreScope extends InheritedNotifier<BillStore> {
  const StoreScope({super.key, required BillStore store, required super.child}) : super(notifier: store);

  static BillStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  /// Without registering a dependency: for saving from build-triggered callbacks (otherwise save → notify → rebuild →
  /// save loops forever).
  static BillStore read(BuildContext context) => context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
