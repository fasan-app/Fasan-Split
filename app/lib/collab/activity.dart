// SPDX-License-Identifier: MPL-2.0
// Fasan Split – what happened in my groups while I looked elsewhere (Nutzer 04.11.: „keinerlei Benachrichtigungen über
// Einladungen in Gruppen, Nachrichten oder andere Geschehnisse“). A short list on this phone only, newest first; the
// app shows it behind the bell and counts what is new. MPL-2.0
import 'dart:convert';

enum ActivityKind { joined, billNew, billChanged, message, mention }

/// Language of the app right now (set by the app from the language setting): the list and the device notifications show the
/// matching text of an entry. Entries keep both, so a language switch changes the old ones too.
bool activityGerman = true;

class Activity {
  Activity(this.kind, this.at, this.group, this.text, {this.ref, this.en});

  final ActivityKind kind;
  final DateTime at;
  final String group; // group tag
  final String text; // German
  final String? en; // English; null = same text (e.g. only a name and a message)
  final String? ref; // bill id or message id

  /// The text in the language of the app.
  String get shown => activityGerman || en == null ? text : en!;

  Map<String, Object?> toJson() => {'k': kind.name, 't': at.millisecondsSinceEpoch, 'g': group, 'x': text, if (en != null) 'y': en, if (ref != null) 'r': ref};
  static Activity? fromJson(Map<String, Object?> j) {
    try {
      return Activity(ActivityKind.values.byName(j['k'] as String), DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()), j['g'] as String, j['x'] as String, ref: j['r'] as String?, en: j['y'] as String?);
    } catch (_) {
      return null;
    }
  }

  static String encode(List<Activity> l) => jsonEncode([for (final a in l) a.toJson()]);
  static List<Activity> decode(String? s) {
    try {
      return [for (final j in jsonDecode(s ?? '[]') as List) ?Activity.fromJson((j as Map).cast<String, Object?>())];
    } catch (_) {
      return [];
    }
  }
}
