// Fasan Split – texts about the direction of a bill (paid or refund). German and English, Du-Form, short sentences. MPL-2.0
import 'l10n.dart';

extension BillDirectionTexts on S {
  String get signTitle => de ? 'Bezahlt oder Geld zurück?' : 'Paid or money back?';
  String get signText => de
      ? 'Dieser Bon hat einen negativen Betrag. Schulden sind immer positiv. Sag, was passiert ist.'
      : 'This receipt has a negative amount. Debts are always positive. Tell me what happened.';
  String get signPaid => de ? 'Es wurde bezahlt' : 'It was paid';
  String get signRefund => de ? 'Geld kam zurück' : 'Money came back';
  String get refundBadge => de ? 'Erstattung' : 'Refund';
  String get refundHint => de ? 'Wer das Geld bekam, gibt es den anderen anteilig zurück.' : 'Whoever got the money gives it back to the others.';
}
