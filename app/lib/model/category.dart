// Fasan Split – categories of a bill: a fixed base list (research docs/recherche/2026-11-04-konkurrenz-bedienung-saldo.md
// §4: groceries, eating out, transport, accommodation, leisure, household … appear in all comparable apps), own ones
// added by the user (stored in the app settings), and a guess from the receipt (shop name, items, dishes found by
// speisen.dart). The guess is only a start: the user changes it with one tap. Ids are stable English words. MPL-2.0
import 'package:flutter/material.dart';

import 'bill.dart';

class Category {
  const Category(this.id, this.de, this.en, this.icon, this.color);

  final String id, de, en;
  final IconData icon;
  final Color color;

  String label(bool german) => german ? de : en;
}

/// Base list, in the order shown in the picker.
const baseCategories = [
  Category('groceries', 'Lebensmittel', 'Groceries', Icons.shopping_basket_outlined, Color(0xFF26745C)),
  Category('restaurant', 'Restaurant & Café', 'Restaurant & café', Icons.restaurant_outlined, Color(0xFFC2410C)),
  Category('bar', 'Bar & Ausgehen', 'Bar & nightlife', Icons.local_bar_outlined, Color(0xFF8B3FB8)),
  Category('transport', 'Transport', 'Transport', Icons.directions_transit_outlined, Color(0xFF2B54D6)),
  Category('fuel', 'Tanken', 'Fuel', Icons.local_gas_station_outlined, Color(0xFF5B6B12)),
  Category('stay', 'Unterkunft', 'Accommodation', Icons.hotel_outlined, Color(0xFF00708A)),
  Category('trip', 'Reise & Ausflug', 'Trips & tours', Icons.luggage_outlined, Color(0xFF0E7490)),
  Category('leisure', 'Freizeit & Kultur', 'Leisure & culture', Icons.theater_comedy_outlined, Color(0xFFB4235A)),
  Category('shopping', 'Einkauf', 'Shopping', Icons.shopping_bag_outlined, Color(0xFF7A5512)),
  Category('home', 'Haushalt & Wohnen', 'Home & utilities', Icons.home_outlined, Color(0xFF64748B)),
  Category('health', 'Gesundheit', 'Health', Icons.medical_services_outlined, Color(0xFFDC2626)),
  Category('other', 'Sonstiges', 'Other', Icons.category_outlined, Color(0xFF6B7280)),
];

/// An own category (name only; icon and colour fixed).
Category customCategory(String name) => Category('c:$name', name, name, Icons.label_outline_rounded, const Color(0xFF475569));

Category? categoryById(String? id) {
  if (id == null || id.isEmpty) return null;
  if (id.startsWith('c:')) return customCategory(id.substring(2));
  for (final c in baseCategories) {
    if (c.id == id) return c;
  }
  return null;
}

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
