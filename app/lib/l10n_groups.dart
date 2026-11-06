// Fasan Split – texts for group members and balances. German and English, Du-Form, short sentences. MPL-2.0
import 'l10n.dart';

extension GroupTexts on S {
  String get groupPeople => text('groups.groupPeople');
  String get groupAddPerson => text('groups.groupAddPerson');
  String get groupNoPeople => text('groups.groupNoPeople');
  String get groupFromBills => text('groups.groupFromBills');
  String get groupSettle => text('groups.groupSettle');
  String get groupSettled => text('groups.groupSettled');
  String get groupBalanceHint => text('groups.groupBalanceHint');
  String allFromGroup(String g) => text('groups.allFromGroup', [g]);
  String inviteFor(String p) => text('groups.inviteFor', [p]);
  String linkedTo(String m) => text('groups.linkedTo', [m]);
  String get inTheApp => text('groups.inTheApp');
  String get withoutApp => text('groups.withoutApp');
  String get personRights => text('groups.personRights');
  String get notLinked => text('groups.notLinked');
  String get linkMember => text('groups.linkMember');
  String get unlink => text('groups.unlink');
  String get linkPerson => text('groups.linkPerson');
  String countsWith(String p) => text('groups.countsWith', [p]);
  String get onlyAdminLinks => text('groups.onlyAdminLinks');
  String get founder => text('groups.founder');
  String get giveAdmin => text('groups.giveAdmin');
  String get takeAdmin => text('groups.takeAdmin');
  String get trustAboutMe => text('groups.trustAboutMe');
  String get trustAboutMeSub => text('groups.trustAboutMeSub');
  String get confirmsAboutMe => text('groups.confirmsAboutMe');
  String get confirmAllTitle => text('groups.confirmAllTitle');
  String get removeMemberSub => text('groups.removeMemberSub');
  String get heldTitle => text('groups.heldTitle');
  String get heldNone => text('groups.heldNone');
  String get heldPayer => text('groups.heldPayer');
  String get heldShare => text('groups.heldShare');
  String get heldPerson => text('groups.heldPerson');
  String get heldAccept => text('groups.heldAccept');
  String get heldDecline => text('groups.heldDecline');
}
