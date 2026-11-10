// SPDX-License-Identifier: MPL-2.0
// Fasan Split – notifications on the device (Nutzer 04.11.: told when invitations were accepted, new bills, messages).
// flutter_local_notifications 22.3.3 (BSD-3, pub.dev). No Google push (FOSS, Grundsätze): a notification appears while
// the app runs or sits in the background; a fully closed app shows the news in the bell on the next start.
// Android 13+ needs POST_NOTIFICATIONS, asked only when the user switches this on (developer.android.com/develop/ui/
// views/notifications/notification-permission: „request the permission in context“). Browsers: permission only after
// a tap (pub.dev README, web). MPL-2.0
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity.dart';

class DeviceNotifier with WidgetsBindingObserver {
  DeviceNotifier(this.prefs);

  final SharedPreferences? prefs;
  static const _kOn = 'notify.device';
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  AppLifecycleState _state = AppLifecycleState.resumed;
  int _id = 0;

  /// Switched on by the user (Einstellungen → Benachrichtigungen).
  bool get enabled => prefs?.getBool(_kOn) ?? false;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    if (!enabled) return;
    await _init();
  }

  Future<void> _init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      _ready = true;
    } catch (e) {
      debugPrint('notifications unavailable: $e');
    }
  }

  /// Turns device notifications on or off; on asks for the permission. Returns whether they are on now.
  Future<bool> setEnabled(bool on) async {
    if (!on) {
      await prefs?.setBool(_kOn, false);
      return false;
    }
    await _init();
    bool? granted;
    try {
      if (kIsWeb) {
        granted = await _plugin.resolvePlatformSpecificImplementation<WebFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      } else {
        granted = await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      }
    } catch (_) {
      granted = false;
    }
    final ok = _ready && granted != false;
    await prefs?.setBool(_kOn, ok);
    return ok;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _state = state;

  /// Shows [a] when the app is not in front (in front the bell and the badges already tell).
  Future<void> show(Activity a) async {
    if (!enabled || !_ready || _state == AppLifecycleState.resumed) return;
    final title = switch (a.kind) {
      ActivityKind.message => 'Neue Nachricht',
      ActivityKind.mention => 'Du wurdest erwähnt',
      ActivityKind.joined => 'Neu in der Gruppe',
      ActivityKind.billNew => 'Neuer Bon',
      ActivityKind.billChanged => 'Bon geändert',
      ActivityKind.proposal => 'Vorschlag für dich',
    };
    try {
      await _plugin.show(
        id: _id++ % 1000,
        title: title,
        body: a.shown,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('fasan-news', 'Neuigkeiten', channelDescription: 'Nachrichten, Beitritte, neue und geänderte Bons', importance: Importance.defaultImportance),
        ),
      );
    } catch (_) {}
  }
}
