// Fasan Split – data types of the receipt recognition. MPL-2.0
//
// Names follow the web reader (Fasan-Karte/site/bon.js 3.19); the JS field is given in brackets for later readers.
// Amounts are integer cents. Boxes are in pixels of the image that was read.

class Box {
  Box(this.x0, this.y0, this.x1, this.y1);

  double x0, y0, x1, y1;

  double get w => x1 - x0;
  double get h => y1 - y0;
  double get cx => (x0 + x1) / 2;
  double get cy => (y0 + y1) / 2;

  Box copy() => Box(x0, y0, x1, y1);

  Box union(Box o) => Box(x0 < o.x0 ? x0 : o.x0, y0 < o.y0 ? y0 : o.y0, x1 > o.x1 ? x1 : o.x1, y1 > o.y1 ? y1 : o.y1);

  List<double> toList() => [x0, y0, x1, y1];

  @override
  String toString() => 'Box(${x0.round()},${y0.round()},${x1.round()},${y1.round()})';
}

/// One character with its probability and the second-best reading [zeichen: {z, p, alt, p2}].
class Glyph {
  const Glyph(this.ch, this.p, {this.alt, this.p2 = 0});

  final String ch;
  final double p;
  final String? alt;
  final double p2;
}

/// A short text reading with confidence 0–100 [mehr: {t, c}].
class Reading {
  const Reading(this.text, this.conf);

  final String text;
  final double conf;
}

/// A recognised word/text box [woerter: {t, c, b, neig, zeichen}].
class Word {
  Word({required this.text, required this.conf, required this.box, this.tilt, this.glyphs, this.fromColumn = false, this.alts});

  String text;
  double conf;
  Box box;

  /// Slope dy/dx of the text box (PaddleOCR) [neig].
  double? tilt;
  List<Glyph>? glyphs;

  /// Created by the column re-read [spalte].
  bool fromColumn;
  List<String>? alts;

  // working fields of zeilenAus
  double cy = 0, hh = 0;
}

/// A text line built from words [zeilen].
class Line {
  Line(this.words);

  List<Word> words;
  Box box = Box(0, 0, 0, 0);
  double conf = 0;
  List<Glyph> glyphs = const [];
  String text = '';

  /// Re-readings of the amount of this line [mehr].
  List<Reading>? readings;
  bool taken = false; // [genommen]
}

/// Lines plus the column-matching info [Array.spalten in zeilenSpalten].
class Lines {
  Lines(this.lines, [this.columns]);

  final List<Line> lines;
  final ColumnInfo? columns;
}

class ColumnInfo {
  const ColumnInfo(this.offset, this.pairs, this.pitch);

  /// Offset of the amount column in lines [versatz].
  final double offset;
  final int pairs;
  final double pitch;
}

/// An amount in a line with its position in the text [betraege].
class Amount {
  Amount(this.v, this.start, this.end, this.neg, {this.late = false});

  int v;
  final int start, end;
  final bool neg;

  /// Found only when re-reading [nach].
  final bool late;
}

/// A candidate value for an item with a cost [kand: {v, k, warum}].
class Cand {
  Cand(this.v, this.k, [this.why]);

  final int v;
  double k;
  final String? why;
}

class Vote {
  const Vote(this.v, this.k, this.share, [this.why]);

  final int v;
  final double k;
  final double share; // [anteil]
  final String? why;
}

/// Pfand, Rabatt or extra attached to an item [zusaetze].
class Extra {
  Extra({required this.kind, required this.amount, required this.line, required this.name, required this.alt, required this.score, required this.sure, this.frame});

  final String kind; // pfand | rabatt | extra
  final int amount;
  final int line;
  final String name;
  final List<(int, double)> alt;
  final double score;
  final bool sure;
  Box? frame;
}

/// One item of the receipt [posten].
class Item {
  Item({required this.name, required this.amount, this.qty = 1, this.line = -1, this.conf = 100, this.frame, this.cands = const []});

  String name; // [t]
  int amount; // [b]
  num qty; // [menge]
  num qtyRead = 0; // [mengeGelesen]
  num? unit; // [einzel] cents per piece (1,799 €/l → 179.9)
  int? rate; // [satz] VAT %
  String? taxCode; // [stb] A/B/…
  int line; // [zeile]
  double conf; // [c]
  Box? frame; // [rahmen]
  int nameLine = -1; // [nameZeile]
  bool nameUncertain = false; // [nameUnsicher]
  List<Cand> cands; // [kand]
  String? kind2; // [art2] rabatt | leergut | storno | kaution
  bool deposit = false; // [kaution]
  List<(int, double)> votes = const []; // [lesungen] (value, share)
  int readCount = 1; // [lesbarAmount]
  bool sure = false; // [sicher]
  String? repair; // [rep]
  bool dropped = false; // [weg]
  String? surcharge; // [zuschlag] steuer | service | rundung | trinkgeld
  int? certainty; // [sicherheit] 0–100
  List<int> suggestions = const []; // [vorschlag]
  List<Extra> extras = []; // [zusaetze]
  List<(int, double)>? extraCands; // [zuKand]
  String? extraKind; // [zusArt]
  bool merged = false; // [weg2]
  bool cancelled = false; // [storniert]
  bool qtySure = false; // [mengeSicher]
  bool missing = false; // [fehlt]
  int? vat; // [mwst] (PT reader)

  /// JPEG of the line in the shown image [schnipsel]; filled by the pipeline.
  List<int>? snippet;
}

/// A line of the result with its type [zeilen: {text, b, c, typ, zu, block}].
class LineOut {
  LineOut({required this.text, required this.box, required this.conf, required this.type, this.item, this.block = false});

  final String text;
  Box box;
  final double conf;
  String type;
  int? item;
  bool block;
}

class TaxClass {
  TaxClass({required this.rate, required this.gross, this.base, this.vat});

  final int rate;
  final int gross;
  final int? base, vat;
  int actual = 0; // [ist]
  bool ok = false;
}

class Check {
  Check({required this.ok, this.source, this.corrected = 0, this.targets = 0, this.contradiction = false, this.classes, this.unreadable = 0, this.repaired = 0});

  bool ok; // [gesamtOk]
  final String? source;
  final int corrected, targets;
  bool contradiction; // [widerspruch]
  final List<TaxClass>? classes;
  final int unreadable, repaired;
}

class ReceiptKind {
  const ReceiptKind(this.id, this.name, this.sure, this.shop);

  final String id; // restaurant | cafe | bar | supermarkt | tanken | apotheke | fahrt | unterkunft | eintritt | unbekannt
  final String name;
  final bool sure;
  final String shop; // [geschaeft]
}

/// Parsed invoice QR code (Portugal, AT specification) [qrLesen].
class QrInfo {
  const QrInfo({required this.total, this.nif, this.date, this.doc, this.tax, this.classes = const []});

  final int total;
  final String? nif, date, doc;
  final int? tax;
  final List<TaxClass> classes;
}

/// Result of reading the lines [liesAllgemein / liesPT].
class ReadResult {
  ReadResult({
    required this.lines,
    required this.items,
    required this.total,
    required this.totalLine,
    required this.sum,
    required this.dec,
    required this.advance,
    required this.check,
    this.kind,
  });

  List<LineOut> lines;
  List<Item> items;
  int? total;
  final int totalLine;
  final int sum;
  final String dec;
  final int advance; // [anzahlung]
  Check check;
  ReceiptKind? kind;
}
