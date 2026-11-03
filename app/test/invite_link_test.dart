// Fasan Split – invitation links: https address of the web app, the old scheme still works. MPL-2.0
import 'dart:typed_data';

import 'package:fasan_split/collab/group.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/web_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final inv = Invite(tag: 't1', secret: Uint8List(32), adminPub: 'ab' * 32, relays: ['wss://relay.example'], expires: DateTime(2030), name: 'WG');

  test('Link ist eine https-Adresse unter /Fasan-Split/join/, Code nur nach „#“', () {
    final u = Uri.parse(inv.link);
    expect(u.scheme, 'https');
    expect(u.host, 'fasan-app.github.io');
    expect(u.path, '/Fasan-Split/join/');
    expect(u.query, isEmpty);
    expect(Invite.parse(inv.link)?.name, 'WG');
  });

  test('Alter Link fasansplit://join und nackter Code gehen weiter', () {
    expect(Invite.parse('fasansplit://join#${inv.encode()}')?.tag, 't1');
    expect(Invite.parse(inv.encode())?.tag, 't1');
  });

  test('Nur Einladungen öffnen den Beitreten-Schirm', () {
    expect(isInviteLink(Uri.parse(inv.link)), isTrue);
    expect(isInviteLink(Uri.parse('fasansplit://join#x')), isTrue);
    expect(isInviteLink(Uri.parse('https://fasan-app.github.io/Fasan-Split/')), isFalse);
    expect(isInviteLink(Uri.parse('https://example.org/Fasan-Split/join/#x')), isFalse);
  });

  test('Auf dem Handy gibt es keinen übergebenen Code', () {
    expect(takeJoinCode(), isNull);
  });
}
