import 'package:flutter_test/flutter_test.dart';
import 'package:fasan_split/collab/bill_changes.dart';
import 'package:fasan_split/ui/history.dart';

ChangeRecord rec(String? app, DateTime at) => ChangeRecord(at: at, group: 'g', billId: 'b', title: 'Bon', who: 'Mia', whoKey: 'k', lines: const [], app: app);

void main() {
  final now = DateTime(2026, 11, 12);
  test('old APK build is reported, web and new builds are not', () {
    expect(staleAppOf([rec('0.1.83', now)], now: now), '0.1.83');
    expect(staleAppOf([rec('web abc1234', now), rec('0.1.112', now), rec(null, now)], now: now), isNull);
    expect(staleAppOf([rec('0.1.83', now.subtract(const Duration(days: 30)))], now: now), isNull);
  });
}
