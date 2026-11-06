// Fasan Split – what every screen reaches from the app: the store, the collaboration and a few app-wide handles. Lives in ui/ so
// screens never import main.dart (docs/ARCHITEKTUR.md, step 3b; before: 22 of 32 screens imported the entry point). MPL-2.0
import 'package:flutter/widgets.dart';

import '../collab/notify.dart';
import '../collab/service.dart';
import '../perf/perf_governor.dart';
import '../state/store.dart';

/// Measures the first frames and reduces effects on slow devices (set in main.dart, null in tests).
PerfGovernor? perfGovernor;

final navigatorKey = GlobalKey<NavigatorState>();

/// Device notifications (null in tests).
DeviceNotifier? deviceNotifier;

/// True when this start came from an invitation link (browser: handed over by join/index.html).
bool startedWithInvite = false;

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
