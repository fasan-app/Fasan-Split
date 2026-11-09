// SPDX-License-Identifier: MPL-2.0
// Fasan Split – Nostr events (NIP-01) and relay connections. MPL-2.0
//
// Rules (Beschluss 02.11./03.11.): nothing is sent to a relay unless the user has set up a group and uses it. Tests run against
// MemoryRelay only; public relays are never contacted by tests.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'crypto.dart';
import 'ws_connect.dart';

class NostrEvent {
  NostrEvent({required this.id, required this.pubkey, required this.createdAt, required this.kind, required this.tags, required this.content, required this.sig});

  final String id, pubkey, content, sig;
  final int createdAt, kind;
  final List<List<String>> tags;

  static Uint8List _hash(String pubkey, int createdAt, int kind, List<List<String>> tags, String content) => sha256(utf8.encode(jsonEncode([0, pubkey, createdAt, kind, tags, content])));

  static NostrEvent create(KeyPair key, {required int kind, required List<List<String>> tags, required String content, int? createdAt}) {
    final t = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final h = _hash(key.pub, t, kind, tags, content);
    return NostrEvent(id: toHex(h), pubkey: key.pub, createdAt: t, kind: kind, tags: tags, content: content, sig: schnorrSign(h, key.priv));
  }

  /// Events whose signature was checked and found valid (id + signature + public key). A relay sends every stored event again on each
  /// reconnect and for each new subscription; the check costs tens of milliseconds on the screen thread in the browser (CryptoStats), so
  /// it runs once per event. The id is still recomputed from the content every time, and the key includes signature and public key, so
  /// a changed content or signature never passes through the cache. Only valid results are kept.
  static final Set<String> _checked = <String>{};
  static const _checkedMax = 4000;

  /// Id matches the content and the signature is valid for the public key.
  bool get valid {
    try {
      final h = _hash(pubkey, createdAt, kind, tags, content);
      if (toHex(h) != id) return false;
      final key = '$id$sig$pubkey';
      if (_checked.contains(key)) return true;
      if (!schnorrVerify(h, sig, pubkey)) return false;
      if (_checked.length >= _checkedMax) _checked.clear();
      _checked.add(key);
      return true;
    } catch (_) {
      return false;
    }
  }

  String? tag(String name) {
    for (final t in tags) {
      if (t.isNotEmpty && t[0] == name && t.length > 1) return t[1];
    }
    return null;
  }

  Map<String, Object?> toJson() => {'id': id, 'pubkey': pubkey, 'created_at': createdAt, 'kind': kind, 'tags': tags, 'content': content, 'sig': sig};

  static NostrEvent fromJson(Map<String, dynamic> j) => NostrEvent(
        id: j['id'] as String,
        pubkey: j['pubkey'] as String,
        createdAt: (j['created_at'] as num).toInt(),
        kind: (j['kind'] as num).toInt(),
        tags: [for (final t in j['tags'] as List) [for (final x in t as List) '$x']],
        content: j['content'] as String,
        sig: j['sig'] as String,
      );
}

/// Subset of NIP-01 filters we use.
class Filter {
  const Filter({this.kinds, this.authors, this.tags = const {}, this.since});

  final List<int>? kinds;
  final List<String>? authors;
  final Map<String, List<String>> tags; // tag name → accepted values („t“, „p“, „d“)
  final int? since;

  bool matches(NostrEvent e) {
    if (kinds != null && !kinds!.contains(e.kind)) return false;
    if (authors != null && !authors!.contains(e.pubkey)) return false;
    if (since != null && e.createdAt < since!) return false;
    for (final t in tags.entries) {
      if (!e.tags.any((x) => x.length > 1 && x[0] == t.key && t.value.contains(x[1]))) return false;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
        if (kinds != null) 'kinds': kinds,
        if (authors != null) 'authors': authors,
        for (final t in tags.entries) '#${t.key}': t.value,
        if (since != null) 'since': since,
      };
}

/// Relays used for new groups. Not checked for availability here – the user can change them per group later.
// FASAN_RELAYS (compile-time, comma-separated) replaces them for the end-to-end test against a local relay only.
const String _relaysOverride = String.fromEnvironment('FASAN_RELAYS');
final List<String> defaultRelays = _relaysOverride.isEmpty ? const ['wss://relay.damus.io', 'wss://nos.lol', 'wss://relay.primal.net'] : _relaysOverride.split(',');

/// What a group needs from a relay: publish an event, listen for events (stored ones first, then live).
abstract class Relay {
  /// Completes with true if the relay accepted the event.
  Future<bool> publish(NostrEvent e);
  Stream<NostrEvent> subscribe(Filter f);
  Future<void> close();
  String get name;

  /// The app came back to the front (iPhone: the browser froze the connections while another app was in front): connect again
  /// at once instead of waiting for the next retry. Default: nothing to do.
  void wake() {}
}

/// In-process relay for tests: addressable events (kind 30000–39999) replace older ones with the same author and d tag.
class MemoryRelay implements Relay {
  MemoryRelay(this.hub, {this.name = 'memory'});

  final MemoryRelayHub hub;
  @override
  final String name;
  final List<StreamSubscription<NostrEvent>> _subs = [];

  @override
  Future<bool> publish(NostrEvent e) async => hub.accept(e);

  @override
  void wake() {}

  @override
  Stream<NostrEvent> subscribe(Filter f) {
    late StreamController<NostrEvent> c;
    StreamSubscription<NostrEvent>? live;
    c = StreamController<NostrEvent>(onListen: () {
      for (final e in hub.stored.toList()) {
        if (f.matches(e)) c.add(e);
      }
      live = hub.live.stream.where(f.matches).listen(c.add);
      _subs.add(live!);
    }, onCancel: () => live?.cancel());
    return c.stream;
  }

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
  }
}

class MemoryRelayHub {
  final List<NostrEvent> stored = [];
  final StreamController<NostrEvent> live = StreamController<NostrEvent>.broadcast(sync: true);

  /// What the relay operator could see: all events as they are stored (tests check that nothing readable is in there).
  bool accept(NostrEvent e) {
    if (!e.valid) return false;
    if (e.kind >= 30000 && e.kind < 40000) {
      final d = e.tag('d');
      final i = stored.indexWhere((x) => x.kind == e.kind && x.pubkey == e.pubkey && x.tag('d') == d);
      if (i >= 0) {
        if (stored[i].createdAt > e.createdAt) return true; // older than what we have: accepted, ignored
        stored[i] = e;
      } else {
        stored.add(e);
      }
    } else {
      if (stored.any((x) => x.id == e.id)) return true;
      stored.add(e);
    }
    live.add(e);
    return true;
  }
}

/// Local proxy for all relay connections ("127.0.0.1:8118" = Orbot), set at start from the settings; null = direct.
String? relayProxy;

/// A WebSocket connection to one relay (wss://). Reconnects with growing pauses and restores subscriptions.
class WsRelay implements Relay {
  WsRelay(this.url);

  final String url;
  @override
  String get name => url;

  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _in;
  bool _closed = false;
  int _subId = 0, _retry = 0;
  final Map<String, (Filter, StreamController<NostrEvent>)> _subs = {};
  final Map<String, Completer<bool>> _acks = {};
  Future<void>? _connecting;

  Future<void> _connect() => _connecting ??= () async {
        try {
          final ch = openRelaySocket(Uri.parse(url), relayProxy); // Tor via Orbot when switched on
          await ch.ready.timeout(const Duration(seconds: 10));
          _ch = ch;
          _retry = 0;
          _in = ch.stream.listen(_onMessage, onDone: _lost, onError: (_) => _lost(), cancelOnError: true);
          for (final s in _subs.entries) {
            ch.sink.add(jsonEncode(['REQ', s.key, s.value.$1.toJson()]));
          }
        } catch (_) {
          _ch = null;
          _scheduleReconnect();
        } finally {
          _connecting = null;
        }
      }();

  void _lost() {
    _in?.cancel();
    _ch = null;
    _scheduleReconnect();
  }

  @override
  void wake() {
    if (_closed || _subs.isEmpty && _acks.isEmpty) return;
    // after the system froze the connection it may look open and be dead: start a new one now, the subscriptions are sent again
    _retry = 0;
    _in?.cancel();
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    _connecting = null;
    _connect();
  }

  void _scheduleReconnect() {
    if (_closed || _subs.isEmpty) return;
    final wait = Duration(seconds: (1 << (_retry++).clamp(0, 5)).clamp(1, 30));
    Timer(wait, () {
      if (!_closed) _connect();
    });
  }

  void _onMessage(dynamic raw) {
    try {
      final m = jsonDecode(raw as String) as List;
      switch (m[0]) {
        case 'EVENT':
          final s = _subs[m[1]];
          if (s != null) s.$2.add(NostrEvent.fromJson((m[2] as Map).cast<String, dynamic>()));
        case 'OK':
          _acks.remove(m[1])?.complete(m[2] == true);
      }
    } catch (_) {
      // a relay sends something we do not understand: ignore, never crash
    }
  }

  @override
  Future<bool> publish(NostrEvent e) async {
    await _connect();
    final ch = _ch;
    if (ch == null) return false;
    final c = Completer<bool>();
    _acks[e.id] = c;
    ch.sink.add(jsonEncode(['EVENT', e.toJson()]));
    return c.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _acks.remove(e.id);
      return false;
    });
  }

  @override
  Stream<NostrEvent> subscribe(Filter f) {
    final id = 'fs${_subId++}';
    late StreamController<NostrEvent> c;
    c = StreamController<NostrEvent>(onListen: () async {
      _subs[id] = (f, c);
      await _connect();
      _ch?.sink.add(jsonEncode(['REQ', id, f.toJson()]));
    }, onCancel: () {
      _subs.remove(id);
      _ch?.sink.add(jsonEncode(['CLOSE', id]));
    });
    return c.stream;
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _in?.cancel();
    await _ch?.sink.close();
    for (final s in _subs.values) {
      await s.$2.close();
    }
    _subs.clear();
  }
}

/// Several relays as one: publish to all (true if at least one accepted), listen on all, drop duplicates.
class RelayPool implements Relay {
  RelayPool(this.relays);

  final List<Relay> relays;
  @override
  String get name => relays.map((r) => r.name).join(', ');

  @override
  Future<bool> publish(NostrEvent e) async {
    final r = await Future.wait(relays.map((x) => x.publish(e).catchError((_) => false)));
    return r.any((x) => x);
  }

  @override
  Stream<NostrEvent> subscribe(Filter f) {
    final seen = <String>{};
    final c = StreamController<NostrEvent>();
    final subs = <StreamSubscription<NostrEvent>>[];
    c.onListen = () {
      for (final r in relays) {
        subs.add(r.subscribe(f).listen((e) {
          if (seen.add(e.id)) c.add(e);
        }, onError: (_) {}));
      }
    };
    c.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return c.stream;
  }

  @override
  void wake() {
    for (final r in relays) {
      r.wake();
    }
  }

  @override
  Future<void> close() async {
    for (final r in relays) {
      await r.close();
    }
  }
}
