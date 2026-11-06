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
  String inviteFor(String p) => de ? '$p einladen' : 'Invite $p';
  String linkedTo(String m) => de ? 'Verknüpft mit $m' : 'Linked to $m';
  String get inTheApp => de ? 'In der App' : 'In the app';
  String get withoutApp => de ? 'Ohne App' : 'Without the app';
  String get personRights => de ? 'Rechte und Verwaltung' : 'Rights and admin';
  String get notLinked => de ? 'Noch nicht in der App' : 'Not in the app yet';
  String get linkMember => de ? 'Mit Mitglied verknüpfen' : 'Link to a member';
  String get unlink => de ? 'Verknüpfung lösen' : 'Unlink';
  String get linkPerson => de ? 'Person aus den Bons zuordnen' : 'Assign a person from the receipts';
  String countsWith(String p) => de ? 'zählt bei $p' : 'counts with $p';
  String get onlyAdminLinks => de ? 'Verknüpfen kann die Person, die die Gruppe verwaltet.' : 'The group admin links people.';
  String get founder => de ? 'Gründung, Verwaltung' : 'Founder, admin';
  String get giveAdmin => de ? 'Zur Verwaltung machen' : 'Make admin';
  String get takeAdmin => de ? 'Verwaltung entziehen' : 'Remove admin role';
  String get trustAboutMe => de ? 'Darf meine Anteile ändern' : 'May change my shares';
  String get trustAboutMeSub => de ? 'Aus: Änderungen an deinen Anteilen, deiner Person oder wer bezahlt hat kommen als Vorschlag.' : 'Off: changes to your shares, your person or who paid arrive as suggestions.';
  String get confirmsAboutMe => de ? 'Änderungen über mich bestätige ich' : 'I confirm changes about me';
  String get confirmAllTitle => de ? 'Änderungen anderer über mich bestätigen' : 'Confirm changes of others about me';
  String get removeMemberSub => de ? 'Die Gruppe bekommt einen neuen Schlüssel. Wer entfernt ist, sieht nichts Neues mehr.' : 'The group gets a new key. The removed person sees nothing new.';
  String get heldTitle => de ? 'Vorschläge' : 'Suggestions';
  String get heldNone => de ? 'Keine Vorschläge offen.' : 'No open suggestions.';
  String get heldPayer => de ? 'wer bezahlt hat' : 'who paid';
  String get heldShare => de ? 'dein Anteil' : 'your share';
  String get heldPerson => de ? 'deine Person' : 'your person';
  String get heldAccept => de ? 'Annehmen' : 'Accept';
  String get heldDecline => de ? 'Ablehnen' : 'Decline';
}
