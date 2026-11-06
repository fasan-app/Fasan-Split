// Fasan Split – categories of a bill: a fixed base list (research docs/recherche/2026-11-04-konkurrenz-bedienung-saldo.md
// §4: groceries, eating out, transport, accommodation, leisure, household … appear in all comparable apps), own ones
// added by the user (stored in the app settings), and a guess from the receipt (shop name, items, dishes found by
// speisen.dart). The guess is only a start: the user changes it with one tap. Ids are stable English words. MPL-2.0
import 'package:flutter/material.dart';


export 'package:fasan_core/category_guess.dart';

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

// The guess (shop name and items → id) is pure logic and lives in the core: packages/fasan_core/lib/category_guess.dart.
