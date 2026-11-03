// Fasan Split – texts for group members and balances. German and English, Du-Form, short sentences. MPL-2.0
import 'l10n.dart';

extension GroupTexts on S {
  String get groupPeople => de ? 'Personen' : 'People';
  String get groupAddPerson => de ? 'Person hinzufügen' : 'Add person';
  String get groupNoPeople => de ? 'Noch niemand in der Gruppe. Füg Personen hinzu, dann teilst du Bons schneller auf.' : 'Nobody in this group yet. Add people to split receipts faster.';
  String get groupFromBills => de ? 'Aus Bons, bleibt in der Gruppe' : 'From receipts, stays in the group';
  String get groupSettle => de ? 'So gleicht ihr aus' : 'How to settle up';
  String get groupSettled => de ? 'Alles ausgeglichen.' : 'All settled.';
  String get groupBalanceHint => de ? 'Zählt nur fertige Bons.' : 'Counts finished receipts only.';
  String allFromGroup(String g) => de ? 'Alle aus „$g“' : 'Everyone from “$g”';
}
