// Fasan Split – a bill: people, items, who shares what, who paid. MPL-2.0
//
// Money is integer cents. Shares are weights per person (1 = an equal part; pieces of "4 × Pastel de Nata" can be
// given as counts). Rounding: largest remainder, so the parts always add up to the item exactly (no lost cent).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'settle.dart';
import 'split_math.dart';

import 'speisen.dart';

final math.Random _uidRng = math.Random.secure();

/// 80-bit random id (hex). Stable names for people and items, so shared bills can merge by id, not by list position.
String newUid() => List.generate(10, (_) => _uidRng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// A note on a bill (Nutzer 04.11.): written by someone, optionally pinned as a hint on top of the bill, and may mention
/// members (they are told in their „Neuigkeiten“). [from] is the author's name; [mentions] are member keys or names.
class BillNote {
  BillNote({String? id, required this.from, required this.text, DateTime? at, this.pinned = false, this.mentions = const []})
      : id = id ?? newUid(),
        at = at ?? DateTime.now();
  final String id, from;
  String text;
  final DateTime at;
  bool pinned;
  List<String> mentions;

  Map<String, Object?> toJson() => {'id': id, 'f': from, 'x': text, 't': at.millisecondsSinceEpoch, if (pinned) 'pin': true, if (mentions.isNotEmpty) 'm': mentions};
  static BillNote fromJson(Map<String, Object?> j) => BillNote(
        id: j['id'] as String?,
        from: j['f'] as String? ?? '',
        text: j['x'] as String? ?? '',
        at: DateTime.fromMillisecondsSinceEpoch((j['t'] as num?)?.toInt() ?? 0),
        pinned: j['pin'] == true,
        mentions: [for (final m in (j['m'] as List?) ?? const []) '$m'],
      );
}

class Person {
  Person(this.name, this.color, {String? uid}) : uid = uid ?? newUid();

  String name;
  final int color; // index into FasanPeople colours
  final String uid;

  Map<String, Object> toJson() => {'name': name, 'color': color, 'uid': uid};
  static Person fromJson(Map<String, dynamic> j) => Person(j['name'] as String, (j['color'] as num).toInt(), uid: j['uid'] as String?);
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
    Map<int, int>? fixed,
    String? uid,
    this.proportional = false,
  })  : shares = shares ?? {},
        fixed = fixed ?? {},
        uid = uid ?? newUid();

  /// Stable id for merging shared bills.
  final String uid;

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

  /// Fixed cents per person index (Aufteilen „fest“, Nutzer 06.11.): these people pay exactly this, the rest follows [shares].
  Map<int, int> fixed;

  /// Shared like the other items, not by own weights: whoever had more pays more of it (VAT/service without an item
  /// line, Nutzer 04.11.: „jemand der weniger hatte muss auch weniger Steuern zahlen“). [shares] is ignored then.
  bool proportional;

  // Leading till words in front of the name ("2 Uni", "1 Unj", "Un."): OCR variants of „Unidade“ (PT tills).
  static final _tillPrefix = RegExp(r'^\s*(\d+([.,]00)?\s+)?(u[nm][il1tfjíìĩ|!]?|und|unid|unidade)(?![A-Za-zÀ-ÿ])\.?\s+', caseSensitive: false);
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

  /// Setting „Klarnamen“ (on by default); set by the store.
  static bool plainNames = true;

  /// German plain name with symbol from the dictionary (Karte 3.8, speisen.js), or null.
  FoodMatch? get food {
    if (!plainNames) return null;
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
    // quantity always shown, also 1 (Nutzer 02.11.: „1“ vom Bon fehlte)
    return '$qty × $base';
  }

  /// Receipt name shown small under the plain name (only when it differs).
  String? get subtitle => food != null ? cleanName : null;

  bool get assigned => proportional || shares.values.any((w) => w > 0);

  Map<String, Object?> toJson() => {
        'uid': uid,
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
        if (fixed.isNotEmpty) 'fixed': {for (final e in fixed.entries) '${e.key}': e.value},
        if (proportional) 'prop': true,
      };

  static BillItem fromJson(Map<String, dynamic> j) => BillItem(
        uid: j['uid'] as String?,
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
        fixed: {for (final e in ((j['fixed'] as Map?) ?? const {}).entries) int.parse(e.key as String): (e.value as num).toInt()},
        proportional: j['prop'] == true,
      );
}

/// Reading state of a bill that comes from a photo in the queue (several photos at once).
abstract final class BillRead {
  static const ok = 'ok';
  static const queued = 'queued';
  static const reading = 'reading';
  static const failed = 'failed';
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
    this.refund = false,
    this.imagePath,
    this.thumb,
    List<BillNote>? notes,
    this.imageAspect,
    this.checked = false,
    this.advance = 0,
    this.logPath,
    this.step = 1,
    this.done = false,
    this.settled = false,
    this.originalPath,
    this.receiptDate,
    this.placeAddress,
    this.taxId,
    this.group,
    this.read = BillRead.ok,
    this.originalQuad,
    this.originalAspect,
    this.trashedAt,
    this.order,
    this.category,
    this.currency,
    this.rate,
    this.rateDate,
    DateTime? updated,
  })  : updated = updated ?? created,
        notes = notes ?? [];

  final String id;
  final DateTime created;
  String purpose;

  /// Total printed on the receipt (or entered); null = sum of items.
  int? total;
  List<BillItem>? items;
  List<Person>? people;
  int? payer;

  /// Several payers (Nutzer 04.11.): person index → cents each one paid. Empty = [payer] paid everything. When set,
  /// [payer] is the one who paid most (balances and lists that show one name use it).
  Map<int, int> paid = {};

  /// True when more than one person paid.
  bool get multiPay => paid.values.where((v) => v > 0).length > 1;

  /// Cents still missing (+) or too much (−) between the amounts of several payers and the receipt.
  int get paidGap => multiPay ? effectiveTotal - paid.values.fold<int>(0, (a, v) => a + v) : 0;

  /// False: [payer] paid and the others owe them. True: [payer] got money back (refund) and holds the others' share.
  /// Amounts are always positive; the direction is only this flag (Nutzer 03.11.: Schulden immer positiv).
  bool refund;
  String? imagePath;

  /// Small preview of the scan (base64 JPEG, about 120 px wide), shared with the group: the others have no photo
  /// (Nutzer 04.11.: no thumbnails in the browser). Made by CollabService once per bill.
  String? thumb;

  /// Notes on this bill, oldest first; a pinned one shows as a hint on top (Nutzer 04.11.).
  List<BillNote> notes;
  double? imageAspect; // width / height of the receipt image
  bool checked;
  int advance;
  String? logPath;

  /// Last flow step the user was on (1 total, 2 people, 3 assign, 4 paid); resumes there.
  int step;

  /// Finished with „Fertig“. Unfinished bills are listed under „Angefangen“ and never discarded on close.
  bool done;

  /// Paid back and balanced (Nutzer 04.11.: only then a bill goes to the archive). [done] alone means „eingetragen“:
  /// it stays under Offen and counts in the balances; a settled bill no longer counts (its debts are paid).
  bool settled;

  /// The photo exactly as taken, untouched (Beschluss 02.11.: Original immer sichtbar). imagePath is the cleaned scan.
  String? originalPath;

  /// Shared photos (Beschluss 06.11.): reference to the downscaled scan / original on the relays ({h, n, s}, see
  /// collab/photo_sync.dart). Set by the phone that has the photo; the others fetch it and fill imagePath/originalPath.
  Map<String, Object?>? photoRef, origRef;

  /// The user removed the photos on this device („Bonfotos löschen“): never fetch them again from the group.
  bool photosRemoved = false;
  DateTime updated;

  /// Date printed on the receipt (Beschluss 02.11.: aus dem Bon, nicht aus dem Erfassungszeitpunkt).
  DateTime? receiptDate;

  /// Address printed on the receipt (street, postcode city) and the shop's tax number (NIF / USt-ID).
  String? placeAddress;
  String? taxId;

  /// Name of the group the bill was put into on the overview (null = none). Nutzer 02.11.: gruppieren.
  String? group;

  /// Reading state of a photo that was added with others: see [BillRead]. Bills made by hand or read in one go are `ok`.
  String read;

  /// Receipt corners in the original photo (8 numbers: top left, top right, bottom right, bottom left, x y in 0–1) and the
  /// photo's width / height. They place the item rows in the „Original“ view; null for older bills.
  List<double>? originalQuad;
  double? originalAspect;

  /// When the bill was moved to the trash (Papierkorb); null = not in the trash.
  DateTime? trashedAt;

  /// Place in the list after the user moved it by hand (smaller = higher); null = by last change. Only on this phone,
  /// not shared with the group (everyone sorts their own list).
  double? order;

  /// Category id (model/category.dart): a base id like „restaurant“ or `c:<name>` for an own one; null = none yet.
  String? category;

  /// Currency of the receipt (ISO code); null = the home currency (Einstellungen, default EUR). Amounts of the bill stay in
  /// this currency; [rate] (home units per 1 unit of it) turns them into the home currency for balances across bills.
  String? currency;
  double? rate;
  DateTime? rateDate;

  /// Cents of this bill in the home currency.
  int toHome(int cents) => currency == null || rate == null ? cents : (cents * rate!).round();

  /// Sort key of the bill lists: hand-made place, else newest change first.
  double get sortKey => order ?? -updated.millisecondsSinceEpoch.toDouble();

  /// The date that matters for the user: printed date, else when it was captured.
  DateTime get date => receiptDate ?? created;

  List<BillItem> get its => items ??= [];
  List<Person> get ps => people ??= [];

  int get itemSum => its.fold(0, (a, p) => a + p.amount);
  int get effectiveTotal => total ?? itemSum;

  /// A negative total (or, without a total, a negative item sum) cannot be a debt: the app asks whether it was paid or came
  /// back. Single negative lines (discount, deposit) in a positive bill are no reason to ask.
  bool get needsSignQuestion => effectiveTotal < 0;

  /// Answers the question: turns every amount positive and sets the direction.
  void resolveSign({required bool refund}) {
    if (!needsSignQuestion) return;
    for (final it in its) {
      it.amount = -it.amount;
    }
    if (total != null) total = -total!;
    this.refund = refund;
    checked = false;
  }

  /// Institutions often print an amount with a minus („-198,00 EUR“: money that left the account). When the total is positive
  /// (read, or corrected by the user) and every item is negative, and the items turned around add up to exactly the total,
  /// the signs of the items were just the wrong way round: turn them. Returns true when something changed (Nutzer 05.11.:
  /// „ich musste im einzigen Posten sagen, das ist kein −198 €“; the app showed a difference of 396 €). The mirror case – a
  /// negative total, positive items adding up to it – turns the total.
  bool alignSigns() {
    final t = total;
    if (t == null || t == 0 || its.isEmpty) return false;
    final sum = itemSum;
    if (t > 0 && sum == -t && its.every((p) => p.amount <= 0)) {
      for (final p in its) {
        p.amount = -p.amount;
      }
      return true;
    }
    if (t < 0 && sum == -t && its.every((p) => p.amount >= 0)) {
      total = -t;
      return true;
    }
    return false;
  }

  /// Difference between total and items (positive: items missing).
  int get difference => effectiveTotal - itemSum;

  int get unassigned => its.where((p) => !p.assigned).length;

  /// Cents per person for one item. Exact integer arithmetic, leftover cents rotate with [rotate] (the item index).
  static Map<int, int> split(int amount, Map<int, double> shares, {int rotate = 0, Map<int, int> fixed = const {}}) => SplitMath.splitFixed(amount, shares, fixed, rotate: rotate);

  /// What each person consumed (cents). Unassigned items are not counted (shown separately).
  /// What each person pays of item [n]. Proportional items follow the other items (largest remainders, exact cents).
  Map<int, int> partsOf(int n) {
    final it = its[n];
    if (!it.proportional) return split(it.amount, it.shares, rotate: n, fixed: it.fixed);
    final base = _baseSums();
    if (!base.values.any((v) => v > 0)) return const {};
    return SplitMath.spread(it.amount, base, rotate: n);
  }

  Map<int, int> _baseSums() {
    final out = {for (var i = 0; i < ps.length; i++) i: 0};
    for (var n = 0; n < its.length; n++) {
      final it = its[n];
      if (it.proportional) continue;
      for (final e in split(it.amount, it.shares, rotate: n, fixed: it.fixed).entries) {
        if (e.key < ps.length) out[e.key] = out[e.key]! + e.value;
      }
    }
    return out;
  }

  Map<int, int> perPerson() {
    final out = _baseSums();
    for (var n = 0; n < its.length; n++) {
      if (!its[n].proportional) continue;
      for (final e in partsOf(n).entries) {
        if (e.key < ps.length) out[e.key] = out[e.key]! + e.value;
      }
    }
    // difference between receipt total and items (tip, unread line) is spread like the items
    final diff = difference;
    if (diff != 0 && out.values.any((v) => v > 0)) {
      for (final e in SplitMath.spread(diff, out, rotate: its.length).entries) {
        out[e.key] = out[e.key]! + e.value;
      }
    }
    return out;
  }

  /// Removes a person and moves every higher index down by one (shares, payer). Items that only they had become open.
  void removePerson(int idx) {
    if (idx < 0 || idx >= ps.length) return;
    ps.removeAt(idx);
    for (final it in its) {
      it.shares = {
        for (final e in it.shares.entries)
          if (e.key != idx) (e.key > idx ? e.key - 1 : e.key): e.value
      };
      it.fixed = {
        for (final e in it.fixed.entries)
          if (e.key != idx) (e.key > idx ? e.key - 1 : e.key): e.value
      };
    }
    if (payer == idx) {
      payer = null;
    } else if (payer != null && payer! > idx) {
      payer = payer! - 1;
    }
    paid = {for (final e in paid.entries) if (e.key != idx) (e.key > idx ? e.key - 1 : e.key): e.value};
  }

  /// Sum of the cents that are assigned to someone (plus the spread difference when anything is assigned).
  int get expectedShared {
    final shared = its.where((p) => !p.proportional && p.assigned && p.shares.keys.any((k) => k < ps.length && (p.shares[k] ?? 0) > 0));
    // proportional items count once anyone has a share of the others (partsOf)
    final assigned = shared.fold<int>(0, (a, p) => a + p.amount) + (shared.isEmpty ? 0 : its.where((p) => p.proportional).fold<int>(0, (a, p) => a + p.amount));
    return assigned + (assigned != 0 || its.any((p) => p.assigned) ? difference : 0);
  }

  /// Second, independent check of every number. Empty list = all consistent. Never throws.
  List<AuditIssue> audit() {
    final issues = <AuditIssue>[];
    for (var n = 0; n < its.length; n++) {
      final it = its[n];
      final a = SplitMath.splitFixed(it.amount, it.shares, it.fixed, rotate: n);
      final b = it.fixed.isEmpty ? SplitMath.splitCumulative(it.amount, it.shares) : a; // fixed amounts have no second method: the sum check below covers them
      final sa = a.values.fold<int>(0, (x, y) => x + y);
      if (a.isNotEmpty && sa != it.amount) issues.add(AuditIssue('sum', '${it.name}: $sa ≠ ${it.amount}'));
      if (a.isNotEmpty && !SplitMath.agree(a, b)) issues.add(AuditIssue('method', '${it.name}: $a ≠ $b'));
    }
    final pp = perPerson();
    final total = pp.values.fold<int>(0, (x, y) => x + y);
    if (pp.values.any((v) => v > 0) && total != expectedShared) issues.add(AuditIssue('sum', 'Σ Personen $total ≠ $expectedShared'));
    // transfers must net to zero around the payer (several payers: they must have paid exactly the receipt)
    final p = payer;
    if (multiPay) {
      if (paidGap != 0) issues.add(AuditIssue('sum', 'Zahler ${effectiveTotal - paidGap} ≠ $effectiveTotal'));
    } else if (p != null && p < ps.length) {
      final t = transfers().fold<int>(0, (x, e) => x + e.$3);
      if (t != total - (pp[p] ?? 0)) issues.add(AuditIssue('sum', 'Überweisungen $t ≠ ${total - (pp[p] ?? 0)}'));
    }
    return issues;
  }

  /// Transfers to the payer (to the others for a refund): (from, to, cents). Several payers: each person's balance is
  /// what they paid minus what they had; settled with the fewest transfers (settle.dart, exact cents, at most
  /// n−1 transfers, same on every phone).
  List<(int, int, int)> transfers() {
    if (multiPay) {
      final pp = perPerson();
      final net = <int, int>{
        for (var i = 0; i < ps.length; i++) i: (paid[i] ?? 0) - (pp[i] ?? 0),
      };
      if (refund) net.updateAll((_, v) => -v);
      // fewest transfers, exactly (settle.dart); people as zero-padded indices so the order is the same on every phone
      String k(int i) => i.toString().padLeft(4, '0');
      return [for (final (f, t, c) in settle({for (final e in net.entries) k(e.key): e.value})) (int.parse(f), int.parse(t), c)];
    }
    final p = payer;
    if (p == null) return const [];
    final pp = perPerson();
    return [
      for (final e in pp.entries)
        if (e.key != p && e.value != 0) refund ? (p, e.key, e.value) : (e.key, p, e.value)
    ];
  }

  /// Takes over everything the user can edit from [o] (undo/redo); photos, paths and sync references stay as they are.
  void restoreEdits(Bill o) {
    purpose = o.purpose;
    total = o.total;
    items = o.its;
    people = o.ps;
    payer = o.payer;
    paid = o.paid;
    refund = o.refund;
    notes = o.notes;
    checked = o.checked;
    advance = o.advance;
    settled = o.settled;
    receiptDate = o.receiptDate;
    placeAddress = o.placeAddress;
    taxId = o.taxId;
    category = o.category;
    currency = o.currency;
    rate = o.rate;
    rateDate = o.rateDate;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'created': created.toIso8601String(),
        'purpose': purpose,
        'total': total,
        'items': its.map((p) => p.toJson()).toList(),
        'people': ps.map((p) => p.toJson()).toList(),
        'payer': payer,
        if (paid.isNotEmpty) 'paid': {for (final e in paid.entries) '${e.key}': e.value},
        'refund': refund,
        'imagePath': imagePath,
        if (thumb != null) 'thumb': thumb,
        if (notes.isNotEmpty) 'notes': [for (final n in notes) n.toJson()],
        'imageAspect': imageAspect,
        'checked': checked,
        'advance': advance,
        'logPath': logPath,
        'step': step,
        'done': done,
        if (settled) 'settled': true,
        'originalPath': originalPath,
        if (photoRef != null) 'photoRef': photoRef,
        if (origRef != null) 'origRef': origRef,
        if (photosRemoved) 'photosRemoved': true,
        'receiptDate': receiptDate?.toIso8601String(),
        'placeAddress': placeAddress,
        'taxId': taxId,
        'group': group,
        'read': read,
        'originalQuad': originalQuad,
        'originalAspect': originalAspect,
        'trashedAt': trashedAt?.toIso8601String(),
        if (order != null) 'order': order,
        if (category != null) 'category': category,
        if (currency != null) 'currency': currency,
        if (rate != null) 'rate': rate,
        if (rateDate != null) 'rateDate': rateDate!.toIso8601String(),
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
        refund: j['refund'] as bool? ?? false,
        imagePath: j['imagePath'] as String?,
        thumb: j['thumb'] as String?,
        notes: [for (final n in (j['notes'] as List?) ?? const []) BillNote.fromJson((n as Map).cast<String, Object?>())],
        imageAspect: (j['imageAspect'] as num?)?.toDouble(),
        checked: j['checked'] as bool? ?? false,
        advance: (j['advance'] as num?)?.toInt() ?? 0,
        logPath: j['logPath'] as String?,
        step: (j['step'] as num?)?.toInt() ?? 4,
        // bills saved before 0.2 were only stored on „Fertig“
        done: j['done'] as bool? ?? true,
        settled: j['settled'] as bool? ?? false,
        originalPath: j['originalPath'] as String?,
        receiptDate: DateTime.tryParse(j['receiptDate'] as String? ?? ''),
        placeAddress: j['placeAddress'] as String?,
        taxId: j['taxId'] as String?,
        group: j['group'] as String?,
        read: j['read'] as String? ?? BillRead.ok,
        originalQuad: (j['originalQuad'] as List?)?.map((x) => (x as num).toDouble()).toList(),
        originalAspect: (j['originalAspect'] as num?)?.toDouble(),
        trashedAt: DateTime.tryParse(j['trashedAt'] as String? ?? ''),
        order: (j['order'] as num?)?.toDouble(),
        category: j['category'] as String?,
        currency: j['currency'] as String?,
        rate: (j['rate'] as num?)?.toDouble(),
        rateDate: DateTime.tryParse(j['rateDate'] as String? ?? ''),
        updated: DateTime.tryParse(j['updated'] as String? ?? ''),
      )
        ..paid = {for (final e in ((j['paid'] as Map?) ?? const {}).entries) int.parse('${e.key}'): (e.value as num).toInt()}
        ..photoRef = (j['photoRef'] as Map?)?.cast<String, Object?>()
        ..origRef = (j['origRef'] as Map?)?.cast<String, Object?>()
        ..photosRemoved = j['photosRemoved'] == true;
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
    final parts = b.partsOf(b.its.indexOf(it));
    rows.add([q(it.subtitle == null ? it.cleanName : '${it.food!.name} (${it.cleanName})'), '${it.qty}', money(it.amount, de: de), for (var i = 0; i < people.length; i++) money(parts[i] ?? 0, de: de)].join(';'));
  }
  final pp = b.perPerson();
  if (b.difference != 0) rows.add([q(de ? 'Differenz zum Bon' : 'Difference to receipt'), '', money(b.difference, de: de), for (var i = 0; i < people.length; i++) ''].join(';'));
  rows.add([q(de ? 'Summe' : 'Total'), '', money(b.effectiveTotal, de: de), for (var i = 0; i < people.length; i++) money(pp[i] ?? 0, de: de)].join(';'));
  if (b.payer != null && b.payer! < people.length) {
    rows.add([q(b.refund ? (de ? 'Erstattung erhalten von' : 'Refund received by') : (de ? 'Bezahlt von' : 'Paid by')), '', q(people[b.payer!].name), for (var i = 0; i < people.length; i++) ''].join(';'));
  }
  return '﻿${rows.join('\r\n')}\r\n';
}
