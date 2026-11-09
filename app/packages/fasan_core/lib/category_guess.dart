// Fasan Split – first guess of a bill's category from the shop name and the items (ids of ui/category.dart). Pure logic, no
// framework (docs/ARCHITEKTUR.md). MPL-2.0
import 'bill.dart';

// Words in the shop name or the items, several languages (DE, PT, EN, ES, FR, IT). Checked in this order: the first
// rule that matches wins (a hotel bar is accommodation, a supermarket café still a supermarket).
final _rules = <(String, RegExp)>[
  ('fuel', RegExp(r'\b(tankstelle|aral|shell|esso|total ?energies|jet|galp|repsol|bp|avia|diesel|benzin|gasolina|gas[oó]leo|super ?95|e10)\b', caseSensitive: false)),
  ('groceries', RegExp(r'\b(rewe|edeka|aldi|lidl|netto|penny|kaufland|real|tegut|globus|norma|continente|pingo doce|minipre[cç]o|intermarch[eé]|mercadona|carrefour|auchan|spar|billa|hofer|coop|migros|supermerca\w*|supermarkt|mercearia|bio ?company|alnatura|denns)\b', caseSensitive: false)),
  ('stay', RegExp(r'\b(hotel|hostel|airbnb|booking\.com|pens[aã]o|pension|guesthouse|apartamentos?|alojamento|ferienwohnung|übernachtung|city ?tax|kurtaxe)\b', caseSensitive: false)),
  ('transport', RegExp(r'\b(uber|bolt|free ?now|taxi|t[aá]xi|db|deutsche bahn|flixbus|bvg|mvv|hvv|cp|comboios|metro|carris|ryanair|easyjet|lufthansa|tap|ticket|fahrkarte|bilhete|parking|parken|estacionamento|maut|portagem|via ?verde)\b', caseSensitive: false)),
  ('trip', RegExp(r'\b(sightseeing|tour|excurs[aã]o|ausflug|bootstour|boat|hop.?on)\b', caseSensitive: false)),
  ('leisure', RegExp(r'\b(museu[m]?|kino|cinema|theater|teatro|konzert|concert|zoo|aquarium|eintritt|entrada|bilheteira|schwimmbad|piscina)\b', caseSensitive: false)),
  ('bar', RegExp(r'\b(bar|pub|kneipe|club|cocktail|cervejaria|taberna)\b', caseSensitive: false)),
  ('restaurant', RegExp(r'\b(restaurante?|ristorante|trattoria|pizzeria|tasca|tasquinha|marisqueira|churrasqueira|caf[eé]|confeitaria|pastelaria|padaria|b[äa]ckerei|bistro|imbiss|döner|burger|mcdonald\S*|kfc|sushi|gasthaus|gasthof|wirtshaus|steakhouse|snack|cantina|mensa)\b', caseSensitive: false)),
  ('health', RegExp(r'\b(apotheke|farm[aá]cia|pharmacy|arzt|cl[ií]nica|hospital|optiker)\b', caseSensitive: false)),
  ('home', RegExp(r'\b(ikea|bauhaus|obi|hornbach|leroy merlin|dm|rossmann|m[üu]ller|drogerie|strom|internet|miete|rent)\b', caseSensitive: false)),
  ('shopping', RegExp(r'\b(zara|h&m|primark|decathlon|fnac|media ?markt|saturn|worten|amazon)\b', caseSensitive: false)),
];

/// A first guess for [b]; null when nothing fits (the user picks).
String? guessCategory(Bill b) {
  final shop = b.purpose;
  for (final (id, re) in _rules) {
    if (re.hasMatch(shop)) return id;
  }
  // dishes on the receipt (speisen.dart): eating out
  if (b.its.where((i) => i.food != null).length >= 2) return 'restaurant';
  final items = b.its.map((i) => i.name).join(' ');
  for (final (id, re) in _rules) {
    if (re.hasMatch(items)) return id;
  }
  return null;
}
