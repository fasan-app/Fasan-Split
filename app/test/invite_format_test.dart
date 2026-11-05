// Invitation link format (v2, 05.11.): short, checked, tolerant to how people copy it. A link that is cut must never open anything
// wrong – it must be recognised as cut. MPL-2.0
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fasan_split/collab/crypto.dart';
import 'package:fasan_split/collab/group.dart';
import 'package:fasan_split/collab/nostr.dart' show defaultRelays;
import 'package:flutter_test/flutter_test.dart';

Uint8List _rnd(Random r, int n) => Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));

Invite _make(Random r, {bool key = true, bool auto = true, bool direct = false, String? person, List<String>? relays, String name = 'Lisboa 26'}) {
  final k = _rnd(r, 32);
  final secret = GroupSecret(key: k, adminPub: toHex(_rnd(r, 32)), name: name, relays: relays ?? defaultRelays, direct: direct);
  return Invite(
    tag: key ? secret.tag : toHex(_rnd(r, 16)),
    secret: _rnd(r, 32),
    adminPub: secret.adminPub,
    relays: secret.relays,
    expires: DateTime.fromMillisecondsSinceEpoch(1893456000000 + r.nextInt(100000) * 1000),
    name: name,
    person: person,
    auto: auto,
    groupKey: key ? k : null,
    direct: direct,
  );
}

void _same(Invite a, Invite b) {
  expect(b.tag, a.tag);
  expect(toHex(b.secret), toHex(a.secret));
  expect(b.adminPub, a.adminPub);
  expect(b.relays, a.relays);
  expect(b.expires.millisecondsSinceEpoch ~/ 1000, a.expires.millisecondsSinceEpoch ~/ 1000);
  expect(b.name, a.name);
  expect(b.person, a.person);
  expect(b.auto, a.auto);
  expect(b.direct, a.direct);
  expect(b.groupKey == null ? null : toHex(b.groupKey!), a.groupKey == null ? null : toHex(a.groupKey!));
}

void main() {
  test('Länge: der Link ist nur noch etwa ein Drittel so lang wie vorher (534 Zeichen)', () {
    final i = _make(Random(1));
    expect(i.link.length, lessThan(230), reason: i.link);
    // in the old format the same invitation was 3× as long
    final old = base64Url.encode(utf8.encode(jsonEncode({'v': 1, 't': i.tag, 's': toHex(i.secret), 'a': i.adminPub, 'r': i.relays, 'x': 1893456000, 'n': i.name, 'o': 1, 'k': toHex(i.groupKey!)}))).replaceAll('=', '');
    expect(old.length, greaterThan(450));
  });

  test('Rundreise: alle Kombinationen, Umlaute, Emoji, lange Namen, eigene Relays', () {
    final r = Random(2);
    for (final key in [true, false]) {
      for (final auto in [true, false]) {
        for (final direct in [true, false]) {
          for (final person in [null, 'Jörg', '你好 😀']) {
            for (final relays in [null, ['wss://relay.example.org', 'wss://ä.example.org/ws?x=1']]) {
              for (final name in ['Lisboa 26', '', 'Hütte am See – Sommer 2026 😀', 'x' * 300]) {
                final i = _make(r, key: key, auto: auto, direct: direct, person: person, relays: relays, name: name);
                final back = Invite.parse(i.link);
                expect(back, isNotNull, reason: 'key=$key auto=$auto direct=$direct person=$person relays=$relays name=${name.length}');
                // names longer than 100 bytes are cut at a character boundary
                final want = Invite(tag: i.tag, secret: i.secret, adminPub: i.adminPub, relays: i.relays, expires: i.expires, name: back!.name, person: i.person, auto: i.auto, groupKey: i.groupKey, direct: i.direct);
                _same(want, back);
                expect(i.name.startsWith(back.name), isTrue);
                expect(utf8.encode(back.name).length, lessThanOrEqualTo(100));
              }
            }
          }
        }
      }
    }
  });

  test('Alte Links (v1, JSON) öffnen weiter', () {
    final r = Random(3);
    final i = _make(r);
    final v1 = base64Url.encode(utf8.encode(jsonEncode({'v': 1, 't': i.tag, 's': toHex(i.secret), 'a': i.adminPub, 'r': i.relays, 'x': i.expires.millisecondsSinceEpoch ~/ 1000, 'n': i.name, 'o': 1, 'k': toHex(i.groupKey!)}))).replaceAll('=', '');
    for (final link in ['${Invite.inviteBase}#$v1', 'fasansplit://join#$v1', v1]) {
      final back = Invite.parse(link);
      expect(back, isNotNull, reason: link.substring(0, 30));
      _same(i, back!);
    }
  });

  test('Abgeschnitten: an jeder Stelle erkannt, nie ein falscher Beitritt; meist „unvollständig“', () {
    final r = Random(4);
    for (final i in [_make(r), _make(r, key: false, auto: false), _make(r, person: 'Jörg', relays: ['wss://a.example', 'wss://b.example'])]) {
      final link = i.link, hash = link.indexOf('#') + 1;
      var incomplete = 0;
      for (var n = hash; n < link.length; n++) {
        final cut = link.substring(0, n);
        final r2 = Invite.parseDetailed(cut);
        expect(r2.invite, isNull, reason: 'cut at ${n - hash} of ${link.length - hash}');
        if (r2.problem == 'incomplete') incomplete++;
        expect(['empty', 'incomplete', 'invalid'], contains(r2.problem));
      }
      expect(incomplete, greaterThan((link.length - hash) * 0.6), reason: 'most cuts say „incomplete“');
      // and the old format
      final v1 = base64Url.encode(utf8.encode(jsonEncode({'v': 1, 't': i.tag, 's': toHex(i.secret), 'a': i.adminPub, 'r': i.relays, 'x': 1893456000, 'n': i.name}))).replaceAll('=', '');
      for (var n = 8; n < v1.length; n += 7) {
        expect(Invite.parse('${Invite.inviteBase}#${v1.substring(0, n)}'), isNull, reason: 'v1 cut at $n');
      }
      expect(Invite.parseDetailed('${Invite.inviteBase}#${v1.substring(0, v1.length - 9)}').problem, 'incomplete');
    }
  });

  test('Verfälscht: ein geändertes Zeichen ergibt nie einen anderen gültigen Link', () {
    final r = Random(5);
    final i = _make(r);
    final link = i.link, hash = link.indexOf('#') + 1;
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    var accepted = 0;
    for (var n = hash; n < link.length; n++) {
      final orig = link[n];
      final alt = alphabet[(alphabet.indexOf(orig) + 1 + r.nextInt(60)) % 64];
      if (alt == orig) continue;
      final bad = link.substring(0, n) + alt + link.substring(n + 1);
      if (Invite.parse(bad) != null) accepted++;
    }
    // a 24-bit check: a changed character is accepted only with a chance of 1 in 16 million (and the last character carries only
    // padding bits, which do not change the data): at most one position may slip through
    expect(accepted, lessThanOrEqualTo(1));
  });

  test('Wie Leute Links weitergeben: umbrochen, in Text, in Klammern, mit Satzzeichen, als fasansplit://, mit %23', () {
    final i = _make(Random(6), person: 'Angi');
    final link = i.link, code = link.substring(link.indexOf('#') + 1);
    final half = code.length ~/ 2;
    final cases = <String>[
      link,
      '  $link  ',
      'Hallo! Hier ist die Einladung in „Lisboa 26“:\n$link\nViel Spaß!',
      'Link: <$link>',
      '($link)',
      'Komm in die Gruppe: $link.',
      'Komm in die Gruppe: $link!',
      '"$link"',
      '${Invite.inviteBase}#${code.substring(0, half)}\n${code.substring(half)}', // wrapped by a messenger
      '${Invite.inviteBase}#${code.substring(0, half)} ${code.substring(half)}',
      'fasansplit://join#$code',
      link.replaceFirst('#', '%23'),
      code,
      'Code: $code',
      '${Invite.inviteBase}#$code#',
      'https://fasan-app.github.io/Fasan-Split/join/#$code',
    ];
    for (final c in cases) {
      final back = Invite.parse(c);
      expect(back, isNotNull, reason: c.replaceAll(code, '<code>'));
      _same(i, back!);
    }
  });

  test('Zufall und Müll: nie eine Ausnahme, nie ein Treffer', () {
    final r = Random(7);
    const chars = 'abcXYZ019-_=#/:. \n%<>"😀ä';
    for (var n = 0; n < 4000; n++) {
      final s = String.fromCharCodes(List.generate(r.nextInt(120), (_) => chars.codeUnitAt(r.nextInt(chars.length))));
      final x = Invite.parseDetailed(s);
      expect(x.invite, isNull, reason: s);
    }
    for (final s in ['', ' ', '#', 'https://example.org/', 'null', '{}', 'eyJ2IjoxfQ', Invite.inviteBase, '${Invite.inviteBase}#']) {
      expect(Invite.parseDetailed(s).invite, isNull);
    }
    expect(Invite.parseDetailed('').problem, 'empty');
    expect(Invite.parseDetailed('hallo welt').problem, 'invalid');
  });

  test('Dieselbe Einladung, zwei Mal verschlüsselt: gleiche Länge, kein Muster der Schlüssel im Text', () {
    final r = Random(8);
    final a = _make(r), b = _make(r);
    expect(a.encode().length, b.encode().length);
    expect(a.link.contains(toHex(a.groupKey!).substring(0, 12)), isFalse, reason: 'keys are not written as readable hex');
  });
}
