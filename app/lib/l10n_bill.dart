// SPDX-License-Identifier: MPL-2.0
// Fasan Split – texts about the direction of a bill (paid or refund). German and English, Du-Form, short sentences. MPL-2.0
import 'l10n.dart';

extension BillDirectionTexts on S {
  String get signTitle => text('billx.signTitle');
  String get signText => text('billx.signText');
  String get signPaid => text('billx.signPaid');
  String get signRefund => text('billx.signRefund');
  String get refundBadge => text('billx.refundBadge');
  String get refundHint => text('billx.refundHint');
}
