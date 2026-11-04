// Fasan Split – what happened in my groups while I looked elsewhere (Nutzer 04.11.: „keinerlei Benachrichtigungen über
// Einladungen in Gruppen, Nachrichten oder andere Geschehnisse“). A short list on this phone only, newest first; the
// app shows it behind the bell and counts what is new. MPL-2.0
import 'dart:convert';

enum ActivityKind { joined, billNew, billChanged, message, mention }

class Activity {
  Activity(this.kind, this.at, this.group, this.text, {this.ref});

  final ActivityKind kind;
  final DateTime at;
  final String group; // group tag
  final String text;
  final String? ref; // bill id or message id

  Map<String, Object?> toJson() => {'k': kind.name, 't': at.millisecondsSinceEpoch, 'g': group, 'x': text, if (ref != null) 'r': ref};
  static Activity? fromJson(Map<String, Object?> j) {
    try {
      return Activity(ActivityKind.values.byName(j['k'] as String), DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()), j['g'] as String, j['x'] as String, ref: j['r'] as String?);
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
