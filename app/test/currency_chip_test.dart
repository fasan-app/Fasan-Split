// SPDX-License-Identifier: MPL-2.0
// The currency suggestion at the bill (Roadmap 2, 14.11.): „CHF?“ asks; „Bleibt EUR“ keeps the bill in the home currency and drops the
// suggestion; nothing changes the bill without the tap. Invented bill. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/currency_ui.dart';
import 'package:fasan_split/ui/scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Währungsvorschlag: fragt erst, „Bleibt EUR“ lässt den Bon in Euro und nimmt den Vorschlag weg', (tester) async {
    final b = Bill(id: 'c', created: DateTime(2026, 11, 14), total: 2400, purpose: 'Bergbeiz Erfunden', people: [Person('Pia', 0)], items: [BillItem(name: 'Rösti', amount: 2400, shares: {0: 1})])
      ..currencyGuess = 'CHF';
    final store = BillStore.memory([b]);
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: Center(child: CurrencyChip(bill: b))),
      ),
    ));
    expect(find.text('CHF?'), findsOneWidget);
    expect(b.currency, isNull, reason: 'ohne Tipp ändert sich nichts');
    await tester.tap(find.byKey(const ValueKey('currency-guess')));
    await tester.pumpAndSettle();
    expect(find.text('Bon in CHF?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('currency-guess-no')));
    await tester.pumpAndSettle();
    expect(b.currency, isNull);
    expect(b.currencyGuess, isNull);
    expect(find.text('CHF?'), findsNothing);
    expect(find.text('EUR'), findsOneWidget);
  });
}
