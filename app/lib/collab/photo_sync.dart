// SPDX-License-Identifier: MPL-2.0
// Fasan Split – receipt photos for the whole group over the relays. MPL-2.0
//
// Beschluss 06.11. (Nutzer, Befragung 2/4): the relays carry a downscaled copy of the scan and of the original, encrypted
// with the group key, in pieces small enough for every relay (research docs/recherche/2026-11-02-gruppe-nostr.md §2: nos.lol
// refuses events from 64 KB, safe ≤ 48 KB per event). Full resolution over Blossom follows as a second channel.
//
// One piece = one addressable event (kind 30078): d = fs:<group tag>:ph:<hash>:<index>, t = <group tag>:ph:<hash>,
// content = ChaCha20-Poly1305(group key, d) of the raw bytes. The bill document names the photo in meta/photo (scan) and
// meta/orig (original) as {h, n, s}: hash, number of pieces, bytes. Relays see size and time, never content or bill.
// The hash is SHA-256 of the image bytes, so a device checks what it assembled before it shows it.
import 'dart:async';
import 'dart:typed_data';

import 'crypto.dart';
import 'group.dart';
import 'nostr.dart';

/// Reference to a photo stored in pieces on the relays.
class PhotoRef {
  const PhotoRef(this.hash, this.pieces, this.size);

  final String hash; // 32 hex characters (first 16 bytes of SHA-256)
  final int pieces;
  final int size;

  Map<String, Object> toJson() => {'h': hash, 'n': pieces, 's': size};

  static PhotoRef? fromJson(Object? j) {
    if (j is! Map) return null;
    final h = j['h'], n = j['n'], s = j['s'];
    if (h is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(h) || n is! num || s is! num) return null;
    if (n < 1 || n > PhotoSync.maxPieces || s < 1 || s > PhotoSync.maxPieces * PhotoSync.pieceBytes) return null;
    return PhotoRef(h, n.toInt(), s.toInt());
  }

  @override
  bool operator ==(Object other) => other is PhotoRef && other.hash == hash && other.pieces == pieces && other.size == size;

  @override
  int get hashCode => Object.hash(hash, pieces, size);
}

abstract final class PhotoSync {
  /// Raw bytes per piece: 29 000 → about 38.7 KB base64 content, the whole event stays below 40 KB (decision: ≤ 40 KB).
  static const pieceBytes = 29000;

  /// Upper bound against a document that names absurd photos (≈ 1.4 MB).
  static const maxPieces = 48;

  static String hashOf(Uint8List bytes) => toHex(sha256(bytes).sublist(0, 16));

  static String tagOf(GroupSecret s, String hash) => '${s.tag}:ph:$hash';
  static String dOf(GroupSecret s, String hash, int i) => 'fs:${s.tag}:ph:$hash:$i';

  /// The reference for [bytes] (without sending anything).
  static PhotoRef refOf(Uint8List bytes) => PhotoRef(hashOf(bytes), (bytes.length + pieceBytes - 1) ~/ pieceBytes, bytes.length);

  /// The signed, encrypted events for [bytes]. Throws if the photo is too large for [maxPieces].
  static List<NostrEvent> events(KeyPair me, GroupSecret s, Uint8List bytes) {
    final ref = refOf(bytes);
    if (ref.pieces > maxPieces) throw ArgumentError('photo too large for the relays: ${bytes.length} bytes');
    return [
      for (var i = 0; i < ref.pieces; i++)
        NostrEvent.create(me, kind: kindData, tags: [['d', dOf(s, ref.hash, i)], ['t', tagOf(s, ref.hash)]], content: aeadSealBytes(
          Uint8List.sublistView(bytes, i * pieceBytes, (i + 1) * pieceBytes > bytes.length ? bytes.length : (i + 1) * pieceBytes),
          s.key,
          dOf(s, ref.hash, i),
        )),
    ];
  }

  /// Sends all pieces; true if the relay took every one (a refused piece is sent again by the caller later).
  static Future<bool> send(Relay relay, KeyPair me, GroupSecret s, Uint8List bytes, {Duration pace = const Duration(milliseconds: 150)}) async {
    var all = true;
    for (final (i, e) in events(me, s, bytes).indexed) {
      // public relays limit bursts (rate-limited); a short pause between pieces (same reason as GroupSession.publishPace)
      if (i > 0 && pace > Duration.zero) await Future<void>.delayed(pace);
      if (!await relay.publish(e)) all = false;
    }
    return all;
  }

  /// Fetches and checks a photo; null if it did not complete in [timeout] or the pieces do not give the named hash.
  /// Only pieces from [authors] count (group members), so a stranger cannot slip in a wrong picture under a known hash
  /// (it would also fail the hash check).
  static Future<Uint8List?> fetch(Relay relay, GroupSecret s, PhotoRef ref, {Set<String>? authors, Duration timeout = const Duration(seconds: 25)}) async {
    final parts = <int, Uint8List>{};
    final done = Completer<Uint8List?>();
    late StreamSubscription<NostrEvent> sub;
    sub = relay.subscribe(Filter(kinds: const [kindData], tags: {'t': [tagOf(s, ref.hash)]})).listen((e) {
      if (done.isCompleted || !e.valid || (authors != null && !authors.contains(e.pubkey))) return;
      final d = e.tag('d');
      final prefix = 'fs:${s.tag}:ph:${ref.hash}:';
      if (d == null || !d.startsWith(prefix)) return;
      final i = int.tryParse(d.substring(prefix.length));
      if (i == null || i < 0 || i >= ref.pieces || parts.containsKey(i)) return;
      try {
        parts[i] = aeadOpenBytes(e.content, s.key, d);
      } catch (_) {
        return; // not for this key or damaged
      }
      if (parts.length < ref.pieces) return;
      final out = BytesBuilder(copy: false);
      for (var k = 0; k < ref.pieces; k++) {
        out.add(parts[k]!);
      }
      final bytes = out.takeBytes();
      done.complete(bytes.length == ref.size && hashOf(bytes) == ref.hash ? bytes : null);
    });
    final r = await done.future.timeout(timeout, onTimeout: () => null);
    await sub.cancel();
    return r;
  }
}
