// Fasan Split – texts in German and English (Du-Form, short sentences). MPL-2.0
import 'package:flutter/widgets.dart';

class S {
  const S._(this.de);

  final bool de;

  static S of(BuildContext context) => S._(Localizations.maybeLocaleOf(context)?.languageCode != 'en');

  String get appName => 'Fasan Split';
  String get bills => de ? 'Rechnungen' : 'Bills';
  String get emptyTitle => de ? 'Noch keine Rechnung' : 'No bill yet';
  String get emptyText => de ? 'Fotografiere einen Bon. Fasan Split liest die Posten, du teilst sie auf.' : 'Take a photo of a receipt. Fasan Split reads the items, you share them.';
  String get scan => de ? 'Bon scannen' : 'Scan receipt';
  String get camera => de ? 'Kamera' : 'Camera';
  String get gallery => de ? 'Foto wählen' : 'Choose photo';
  String get manual => de ? 'Ohne Bon' : 'Without receipt';
  String get settings => de ? 'Einstellungen' : 'Settings';
  String get appearance => de ? 'Aussehen' : 'Appearance';
  String get about => de ? 'Über Fasan Split' : 'About Fasan Split';
  String get reading => de ? 'Bon wird gelesen' : 'Reading receipt';
  String get cancel => de ? 'Abbrechen' : 'Cancel';
  String get readFailed => de ? 'Der Bon ließ sich nicht lesen.' : 'The receipt could not be read.';
  String get tryAgain => de ? 'Nochmal versuchen' : 'Try again';
  String get enterByHand => de ? 'Von Hand eingeben' : 'Enter by hand';
  String get photoStays => de ? 'Das Foto bleibt auf deinem Handy.' : 'The photo stays on your phone.';
  // review
  String get totalAndPurpose => de ? 'Summe und Zweck' : 'Total and purpose';
  String get purpose => de ? 'Wofür?' : 'What for?';
  String get purposeHint => de ? 'z. B. Abendessen Alfama' : 'e.g. dinner in Alfama';
  String get total => de ? 'Summe' : 'Total';
  String get checked => de ? 'Geprüft: Posten ergeben die Summe' : 'Checked: items add up to the total';
  String diff(String d) => de ? 'Posten und Summe weichen um $d ab. Prüfe die markierten Posten.' : 'Items and total differ by $d. Check the marked items.';
  String get contradiction => de ? 'Die Summe stimmt, aber eine Zeile widerspricht sich. Prüfe die Posten.' : 'The total matches, but a line contradicts itself. Check the items.';
  String get items => de ? 'Posten' : 'Items';
  String get addItem => de ? 'Posten hinzufügen' : 'Add item';
  String get name => de ? 'Name' : 'Name';
  String get amount => de ? 'Betrag' : 'Amount';
  String get quantity => de ? 'Menge' : 'Quantity';
  String get delete => de ? 'Löschen' : 'Delete';
  String get save => de ? 'Speichern' : 'Save';
  String get unsure => de ? 'unsicher' : 'unsure';
  String suggestions(String s) => de ? 'Andere Lesungen: $s' : 'Other readings: $s';
  String get next => de ? 'Weiter' : 'Next';
  String get back => de ? 'Zurück' : 'Back';
  // people
  String get whoWasThere => de ? 'Wer war dabei?' : 'Who was there?';
  String get addPerson => de ? 'Name eingeben' : 'Enter a name';
  String get add => de ? 'Hinzufügen' : 'Add';
  String get recent => de ? 'Zuletzt dabei' : 'Recently';
  String get needPeople => de ? 'Mindestens zwei Personen' : 'At least two people';
  String get me => de ? 'Ich' : 'Me';
  // assign
  String get assign => de ? 'Zuordnen' : 'Assign';
  String get focus => de ? 'Fokus' : 'Focus';
  String get list => de ? 'Liste' : 'List';
  String get receipt => de ? 'Bon' : 'Receipt';
  String get cards => de ? 'Karten' : 'Cards';
  String get everyone => de ? 'Alle' : 'Everyone';
  String get evenly => de ? 'Alles gleich teilen' : 'Split everything evenly';
  String open(int n) => de ? (n == 1 ? 'Noch 1 Posten offen' : 'Noch $n Posten offen') : (n == 1 ? '1 item open' : '$n items open');
  String get allAssigned => de ? 'Alles zugeordnet' : 'Everything assigned';
  String get whoHad => de ? 'Wer hatte das?' : 'Who had this?';
  String get pieces => de ? 'Stück je Person' : 'Pieces per person';
  String get swipeHint => de ? 'Wische nach links für den nächsten Posten.' : 'Swipe left for the next item.';
  String get tapItem => de ? 'Tippe einen Posten im Bon an.' : 'Tap an item on the receipt.';
  // pay
  String get whoPaid => de ? 'Wer hat bezahlt?' : 'Who paid?';
  String get result => de ? 'Ergebnis' : 'Result';
  String owes(String a, String b, String m) => de ? '$a zahlt $b $m' : '$a pays $b $m';
  String get notAssigned => de ? 'Nicht zugeordnet' : 'Not assigned';
  String get exportCsv => de ? 'Als Tabelle teilen (CSV)' : 'Share as table (CSV)';
  String get shareText => de ? 'Ergebnis teilen' : 'Share result';
  String get shareLog => de ? 'Protokoll teilen' : 'Share log';
  String get logConsent => de
      ? 'Das Protokoll enthält die gelesenen Zeilen, Zeiten und Gerätedaten, kein Foto. Du entscheidest, wohin es geht.'
      : 'The log contains the lines read, timings and device data, no photo. You decide where it goes.';
  String get share => de ? 'Teilen' : 'Share';
  String get done => de ? 'Fertig' : 'Done';
  String get advance => de ? 'Anzahlung schon bezahlt' : 'Advance already paid';
  String get differenceSpread => de ? 'Differenz zum Bon (anteilig verteilt)' : 'Difference to receipt (spread proportionally)';
  String perPerson(String n) => de ? '$n hatte' : '$n had';
  String get deleteBill => de ? 'Rechnung löschen' : 'Delete bill';
  String get edit => de ? 'Bearbeiten' : 'Edit';
}
