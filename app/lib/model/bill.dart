// Fasan Split – a bill: people, items, who shares what, who paid. MPL-2.0
//
// Money is integer cents. Shares are weights per person (1 = an equal part; pieces of "4 × Pastel de Nata" can be
// given as counts). Rounding: largest remainder, so the parts always add up to the item exactly (no lost cent).
import 'dart:convert';
import 'dart:typed_data';

import '../recognition/speisen.dart';

class Person {
  Person(this.name, this.color);

  String name;
  final int color; // index into FasanPeople colours

  Map<String, Object> toJson() => {'name': name, 'color': color};
  static Person fromJson(Map<String, dynamic> j) => Person(j['name'] as String, (j['color'] as num).toInt());
}

/// Normalised box (0–1) in the receipt image.
class NBox {
  const NBox(this.x0, this.y0, this.x1, this.y1);

  final double x0, y0, x1, y1;

  List<double> toJson() => [x0, y0, x1, y1];
  static NBox? fromJson(Object? j) => j is List && j.length == 4 ? NBox((j[0] as num).toDouble(), (j[1] as num).toDouble(), (j[2] as num).toDouble(), (j[3] as num).toDouble()) : null;
}

class BillItem {
  BillItem({
    required this.name,
    required this.amount,
    this.qty = 1,
    this.unit,
    this.sure = true,
    this.certainty,
    this.suggestions = const [],
    this.boxes = const [],
    this.snippet,
    this.note,
    Map<int, double>? shares,
  }) : shares = shares ?? {};

  String name;
  int amount; // cents, incl. Pfand/Rabatt/extras
  int qty;
  int? unit;
  bool sure;
  int? certainty;
  List<int> suggestions;

  /// All lines of the item in the receipt image (name, quantity, Pfand …) – drawn as one continuous shape.
  List<NBox> boxes;
  Uint8List? snippet;

  /// Short hint like "inkl. Pfand 0,25".
  String? note;

  /// person index → weight
  Map<int, double> shares;

  // Leading till words in front of the name ("2 Uni", "1 Unj", "Un."): OCR variants of „Unidade“ (PT tills).
  static final _tillPrefix = RegExp(r'^\s*(\d+([.,]00)?\s+)?(uni|unj|unl|un|und|unid|unidade)\.?\s+', caseSensitive: false);
  static final _cutTail = RegExp(r'\s+(c/?|[a-z])$', caseSensitive: false);

  /// Name as printed, without till prefixes and cut-off one-letter tails; ALL CAPS in title case.
  String get cleanName {
    var n = name.replaceFirst(_tillPrefix, '').replaceFirst(_cutTail, '').trim();
    if (n.isEmpty) return name.trim();
    if (n == n.toUpperCase() && n.contains(RegExp(r'[A-Z]{3}'))) {
      n = n.toLowerCase().split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
    }
    return n;
  }

  FoodMatch? _food;
  String? _foodFor;

  /// German plain name with symbol from the dictionary (Karte 3.8, speisen.js), or null.
  FoodMatch? get food {
    if (_foodFor != name) {
      _foodFor = name;
      _food = Speisen.recognise(name);
    }
    return _food;
  }

  /// Title shown in lists: plain name with symbol if known, else the cleaned receipt name; with quantity.
  String get title {
    final f = food;
    final base = f != null ? '${f.symbol} ${f.name}' : cleanName;
    return qty > 1 ? '$qty × $base' : base;
  }

  /// Receipt name shown small under the plain name (only when it differs).
  String? get subtitle => food != null ? cleanName : null;

  bool get assigned => shares.values.any((w) => w > 0);

  Map<String, Object?> toJson() => {
        'name': name,
        'amount': amount,
        'qty': qty,
        'unit': unit,
        'sure': sure,
        'certainty': certainty,
        'suggestions': suggestions,
        'boxes': boxes.map((b) => b.toJson()).toList(),
        'snippet': snippet == null ? null : base64Encode(snippet!),
        'note': note,
        'shares': {for (final e in shares.entries) '${e.key}': e.value},
      };

  static BillItem fromJson(Map<String, dynamic> j) => BillItem(
        name: j['name'] as String,
        amount: (j['amount'] as num).toInt(),
        qty: (j['qty'] as num?)?.toInt() ?? 1,
        unit: (j['unit'] as num?)?.toInt(),
        sure: j['sure'] as bool? ?? true,
        certainty: (j['certainty'] as num?)?.toInt(),
        suggestions: ((j['suggestions'] as List?) ?? const []).map((x) => (x as num).toInt()).toList(),
        boxes: ((j['boxes'] as List?) ?? const []).map(NBox.fromJson).whereType<NBox>().toList(),
        snippet: j['snippet'] == null ? null : base64Decode(j['snippet'] as String),
        note: j['note'] as String?,
        shares: {for (final e in ((j['shares'] as Map?) ?? const {}).entries) int.parse(e.key as String): (e.value as num).toDouble()},
      );
}

class Bill {
  Bill({
    required this.id,
    required this.created,
    this.purpose = '',
    this.total,
    this.items,
    this.people,
    this.payer,
    this.imagePath,
    this.imageAspect,
    this.checked = false,
    this.advance = 0,
    this.logPath,
    this.step = 1,
    this.done = false,
    this.originalPath,
    DateTime? updated,
  }) : updated = updated ?? created;

  final String id;
  final DateTime created;
  String purpose;

  /// Total printed on the receipt (or entered); null = sum of items.
  int? total;
  List<BillItem>? items;
  List<Person>? people;
  int? payer;
  String? imagePath;
  double? imageAspect; // width / height of the receipt image
  bool checked;
  int advance;
  String? logPath;

  /// Last flow step the user was on (1 total, 2 people, 3 assign, 4 paid); resumes there.
  int step;

  /// Finished with „Fertig“. Unfinished bills are listed under „Angefangen“ and never discarded on close.
  bool done;

  /// The photo exactly as taken, untouched (Beschluss 02.11.: Original immer sichtbar). imagePath is the cleaned scan.
  String? originalPath;
  DateTime updated;

  List<BillItem> get its => items ??= [];
  List<Person> get ps => people ??= [];

  int get itemSum => its.fold(0, (a, p) => a + p.amount);
  int get effectiveTotal => total ?? itemSum;

  /// Difference between total and items (positive: items missing).
  int get difference => effectiveTotal - itemSum;

  int get unassigned => its.where((p) => !p.assigned).length;

  /// Cents per person for one item (largest remainder: parts always add up exactly).
  static Map<int, int> split(int amount, Map<int, double> shares) {
    final w = {for (final e in shares.entries) if (e.value > 0) e.key: e.value};
    if (w.isEmpty) return {};
    final sum = w.values.fold<double>(0, (a, x) => a + x);
    final raw = {for (final e in w.entries) e.key: amount * e.value / sum};
    final out = {for (final e in raw.entries) e.key: e.value.floor()};
    var rest = amount - out.values.fold<int>(0, (a, x) => a + x); // ≥ 0 because of floor()
    double frac(int k) => raw[k]! - raw[k]!.floor();
    final order = raw.keys.toList()..sort((a, b) => frac(b) != frac(a) ? frac(b).compareTo(frac(a)) : a.compareTo(b));
    for (var i = 0; rest > 0; i = (i + 1) % order.length) {
      out[order[i]] = out[order[i]]! + 1;
      rest--;
    }
    return out;
  }

  /// What each person consumed (cents). Unassigned items are not counted (shown separately).
  Map<int, int> perPerson() {
    final out = {for (var i = 0; i < ps.length; i++) i: 0};
    for (final it in its) {
      for (final e in split(it.amount, it.shares).entries) {
        if (e.key < ps.length) out[e.key] = out[e.key]! + e.value;
      }
    }
    // difference between receipt total and items (tip, unread line) is spread like the items
    final diff = difference;
    if (diff != 0 && out.values.any((v) => v > 0)) {
      final weights = {for (final e in out.entries) if (e.value > 0) e.key: e.value.toDouble()};
      for (final e in split(diff, weights).entries) {
        out[e.key] = out[e.key]! + e.value;
      }
    }
    return out;
  }

  /// Transfers to the payer: (from, to, cents).
  List<(int, int, int)> transfers() {
    final p = payer;
    if (p == null) return const [];
    final pp = perPerson();
    return [
      for (final e in pp.entries)
        if (e.key != p && e.value != 0) (e.key, p, e.value)
    ];
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'created': created.toIso8601String(),
        'purpose': purpose,
        'total': total,
        'items': its.map((p) => p.toJson()).toList(),
        'people': ps.map((p) => p.toJson()).toList(),
        'payer': payer,
        'imagePath': imagePath,
        'imageAspect': imageAspect,
        'checked': checked,
        'advance': advance,
        'logPath': logPath,
        'step': step,
        'done': done,
        'originalPath': originalPath,
        'updated': updated.toIso8601String(),
      };

  static Bill fromJson(Map<String, dynamic> j) => Bill(
        id: j['id'] as String,
        created: DateTime.parse(j['created'] as String),
        purpose: j['purpose'] as String? ?? '',
        total: (j['total'] as num?)?.toInt(),
        items: ((j['items'] as List?) ?? const []).map((x) => BillItem.fromJson((x as Map).cast<String, dynamic>())).toList(),
        people: ((j['people'] as List?) ?? const []).map((x) => Person.fromJson((x as Map).cast<String, dynamic>())).toList(),
        payer: (j['payer'] as num?)?.toInt(),
        imagePath: j['imagePath'] as String?,
        imageAspect: (j['imageAspect'] as num?)?.toDouble(),
        checked: j['checked'] as bool? ?? false,
        advance: (j['advance'] as num?)?.toInt() ?? 0,
        logPath: j['logPath'] as String?,
        step: (j['step'] as num?)?.toInt() ?? 4,
        // bills saved before 0.2 were only stored on „Fertig“
        done: j['done'] as bool? ?? true,
        originalPath: j['originalPath'] as String?,
        updated: DateTime.tryParse(j['updated'] as String? ?? ''),
      );
}

/// "12,50" (German) or "12.50".
String money(int cents, {bool de = true, bool sign = false}) {
  final neg = cents < 0, a = cents.abs();
  final s = '${a ~/ 100}${de ? ',' : '.'}${(a % 100).toString().padLeft(2, '0')}';
  return neg ? '−$s' : (sign && cents > 0 ? '+$s' : s);
}

/// Parses "12,5", "12.50", "-3,2" to cents; null if not a number.
int? parseMoney(String s) {
  final t = s.trim().replaceAll(' ', '').replaceAll('€', '').replaceAll('−', '-');
  final m = RegExp(r'^(-?)(\d+)(?:[.,](\d{0,2}))?$').firstMatch(t);
  if (m == null) return null;
  final cents = int.parse(m[2]!) * 100 + int.parse((m[3] ?? '').padRight(2, '0'));
  return m[1] == '-' ? -cents : cents;
}

/// CSV for spreadsheets: semicolon, decimal comma, UTF-8 with BOM (Excel/LibreOffice in German settings).
String billCsv(Bill b, {bool de = true}) {
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  final people = b.ps;
  final rows = <String>[];
  rows.add([q(de ? 'Posten' : 'Item'), q(de ? 'Menge' : 'Qty'), q(de ? 'Betrag' : 'Amount'), for (final p in people) q(p.name)].join(';'));
  for (final it in b.its) {
    final parts = Bill.split(it.amount, it.shares);
    rows.add([q(it.subtitle == null ? it.cleanName : '${it.food!.name} (${it.cleanName})'), '${it.qty}', money(it.amount, de: de), for (var i = 0; i < people.length; i++) money(parts[i] ?? 0, de: de)].join(';'));
  }
  final pp = b.perPerson();
  if (b.difference != 0) rows.add([q(de ? 'Differenz zum Bon' : 'Difference to receipt'), '', money(b.difference, de: de), for (var i = 0; i < people.length; i++) ''].join(';'));
  rows.add([q(de ? 'Summe' : 'Total'), '', money(b.effectiveTotal, de: de), for (var i = 0; i < people.length; i++) money(pp[i] ?? 0, de: de)].join(';'));
  if (b.payer != null && b.payer! < people.length) {
    rows.add([q(de ? 'Bezahlt von' : 'Paid by'), '', q(people[b.payer!].name), for (var i = 0; i < people.length; i++) ''].join(';'));
  }
  return '﻿${rows.join('\r\n')}\r\n';
}
