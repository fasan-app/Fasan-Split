// Fasan Split – texts of the collaboration screens (German and English, Du-Form, short sentences). MPL-2.0
import 'l10n.dart';

extension CollabTexts on S {
  String get collabTitle => de ? 'Konto und Zusammenarbeit' : 'Account and collaboration';
  String get collabLive => de ? 'Live' : 'Live';
  String get collabShare => de ? 'Live teilen' : 'Share live';
  String get collabShareText => de
      ? 'Alle in der Gruppe sehen Änderungen sofort und können gleichzeitig zuordnen, Notizen schreiben und chatten.'
      : 'Everyone in the group sees changes at once and can assign, write notes and chat at the same time.';
  String get consentTitle => de ? 'Verschlüsselt teilen' : 'Share encrypted';
  String get consentText => de
      ? 'Die Gruppe wird Ende-zu-Ende verschlüsselt (ChaCha20-Poly1305, Schlüssel nur auf den Handys der Mitglieder) über öffentliche Nostr-Relays abgeglichen. Die Relays sehen nur verschlüsselte Daten, deren Größe und Zeitpunkt sowie die IP-Adresse. Inhalte, Namen und Beträge sehen sie nicht. Löschen aus Relays kann nicht garantiert werden.'
      : 'The group syncs end-to-end encrypted (ChaCha20-Poly1305, key only on the members\' phones) through public Nostr relays. Relays only see encrypted data, its size and time, and your IP address. They cannot see content, names or amounts. Deleting from relays cannot be guaranteed.';
  String get consentOk => de ? 'Verstanden, teilen' : 'Understood, share';
  String members(int n) => de ? '$n Mitglieder' : '$n members';
  String get membersTitle => de ? 'Mitglieder' : 'Members';
  String get notesTitle => de ? 'Notizen' : 'Notes';
  String get newNote => de ? 'Neue Notiz' : 'New note';
  String get noteTitle => de ? 'Titel' : 'Title';
  String get noteText => de ? 'Gemeinsam schreiben …' : 'Write together …';
  String get notesEmpty => de ? 'Noch keine Notiz. Tippe auf Neue Notiz. Alle sehen sie sofort.' : 'No note yet. Tap New note. Everyone sees it at once.';
  String get chatTitle => de ? 'Nachrichten' : 'Messages';
  String get chatHint => de ? 'Nachricht schreiben' : 'Write a message';
  String get chatEmpty => de ? 'Noch keine Nachricht. Schreib die erste.' : 'No message yet. Write the first one.';
  String get chatSend => de ? 'Senden' : 'Send';
  String get inviteCreate => de ? 'Einladung erstellen' : 'Create invitation';
  String inviteLive(String g) => de
      ? 'Wer diesen Link öffnet, bittet um Aufnahme in „$g“. Du bestätigst jede Person. Der Link gilt 2 Tage.'
      : 'Whoever opens this link asks to join „$g“. You confirm each person. The link is valid for 2 days.';
  String get inviteCopy => de ? 'Link kopieren' : 'Copy link';
  String get inviteShare => de ? 'Link teilen' : 'Share link';
  String get inviteCopied => de ? 'Link kopiert' : 'Link copied';
  String get inviteRevoke => de ? 'Alle Einladungen widerrufen' : 'Revoke all invitations';
  String get inviteRevoked => de ? 'Einladungen widerrufen. Neue Einladung erstellen?' : 'Invitations revoked. Create a new one?';
  String get requests => de ? 'Anfragen' : 'Requests';
  String get approve => de ? 'Aufnehmen' : 'Let in';
  String get decline => de ? 'Ablehnen' : 'Decline';
  String get noRequests => de ? 'Keine offene Anfrage.' : 'No open request.';
  String approved(String n) => de ? '$n ist jetzt in der Gruppe' : '$n is in the group now';
  String get removeMember => de ? 'Entfernen' : 'Remove';
  String get joinGroup => de ? 'Gruppe beitreten' : 'Join group';
  String get joinText => de ? 'Füge den Einladungslink ein. Die Person, die dich eingeladen hat, bestätigt dich.' : 'Paste the invitation link. The person who invited you will confirm.';
  String get joinLink => de ? 'Einladungslink' : 'Invitation link';
  String get joinName => de ? 'Dein Name in der Gruppe' : 'Your name in the group';
  String get joinPaste => de ? 'Aus Zwischenablage' : 'From clipboard';
  String get joinSend => de ? 'Beitritt anfragen' : 'Ask to join';
  String get joinSent => de ? 'Anfrage gesendet. Warte auf Bestätigung.' : 'Request sent. Waiting for confirmation.';
  String get joinBad => de ? 'Dieser Link ist ungültig.' : 'This link is not valid.';
  String get joinExpired => de ? 'Dieser Link ist abgelaufen. Bitte um einen neuen.' : 'This link has expired. Ask for a new one.';
  String get joinMember => de ? 'Du bist schon in dieser Gruppe.' : 'You are already in this group.';
  String get joinNoSend => de ? 'Die Anfrage kam bei keinem Relay an. Prüfe die Verbindung und versuche es erneut.' : 'The request reached no relay. Check your connection and try again.';
  String get joinWaiting => de ? 'Wartet auf Bestätigung' : 'Waiting for confirmation';
  String get joinTimeout => de ? 'Keine Antwort bekommen' : 'No answer received';
  String get cancel2 => de ? 'Abbrechen' : 'Cancel';
  String get leaveGroup => de ? 'Gruppe verlassen' : 'Leave group';
  String get leaveText => de ? 'Die Rechnungen bleiben auf diesem Handy, die Gruppe läuft bei den anderen weiter. Danach wird nichts mehr abgeglichen.' : 'The bills stay on this phone, the group continues for the others. Nothing syncs afterwards.';
  String get accountName => de ? 'Dein Name' : 'Your name';
  String get accountKey => de ? 'Dein Schlüssel' : 'Your key';
  String get accountWords => de ? 'Wiederherstellungswörter' : 'Recovery words';
  String get accountWordsText => de
      ? 'Mit diesen 12 Wörtern stellst du dein Konto auf einem neuen Handy wieder her. Schreib sie auf Papier und gib sie niemandem. Wer sie hat, ist du. Gehen Handy und Wörter verloren, ist das Konto weg. Die Gruppen laufen bei den anderen weiter.'
      : 'These 12 words restore your account on a new phone. Write them on paper and give them to no one. Whoever has them is you. If phone and words are lost, the account is gone. The groups continue for the others.';
  String get accountShow => de ? 'Wörter anzeigen' : 'Show words';
  String get accountHide => de ? 'Wörter verbergen' : 'Hide words';
  String get accountRestore => de ? 'Mit Wörtern wiederherstellen' : 'Restore with words';
  String get accountRestoreText => de
      ? 'Gib deine 12 Wörter ein. Der Schlüssel auf diesem Handy wird ersetzt. Gruppen kommen nicht von selbst zurück: Lass dich neu einladen, dann erscheinen die Rechnungen wieder.'
      : 'Enter your 12 words. The key on this phone is replaced. Groups do not come back by themselves: ask to be invited again, then the bills appear again.';
  String get accountRestoreOk => de ? 'Konto wiederhergestellt' : 'Account restored';
  String get accountRestoreBad => de ? 'Die Wörter passen nicht. Prüfe Schreibweise und Reihenfolge.' : 'The words do not match. Check spelling and order.';
  String get accountPubkey => de ? 'Öffentlicher Schlüssel' : 'Public key';
  String get accountOpen => de ? 'Konto, Wörter, Zusammenarbeit' : 'Account, words, collaboration';
  String get accountMissing => de ? 'Noch kein Konto. Es entsteht, sobald du eine Gruppe teilst oder beitrittst.' : 'No account yet. It is created when you share or join a group.';
  String get relaysTitle => de ? 'Relays' : 'Relays';
  String get relaysText => de ? 'Neue Gruppen nutzen diese öffentlichen Relays. Sie sehen nur verschlüsselte Daten.' : 'New groups use these public relays. They only see encrypted data.';
  String get you => de ? 'Du' : 'You';
  String get admin => de ? 'Admin' : 'Admin';
  String get shared => de ? 'Geteilt' : 'Shared';
  String get openGroup => de ? 'Gruppe öffnen' : 'Open group';
  String get newGroupOrJoin => de ? 'Neue Gruppe oder beitreten' : 'New group or join';
  String get newGroupLive => de ? 'Neue Gruppe (live)' : 'New group (live)';
  String get newGroupLocal => de ? 'Neue Gruppe (nur hier)' : 'New group (only here)';
}
