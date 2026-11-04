// Native: with a proxy (e.g. Orbot's HTTP tunnel 127.0.0.1:8118) the WebSocket goes through it. dart:io WebSocket.connect
// opens the URL with the given HttpClient (sdk lib/_http/websocket_impl.dart), and HttpClient tunnels https/wss with
// CONNECT through a „PROXY host:port“ (sdk lib/_http/http_impl.dart). Plain ws:// (.onion) is not tunnelled this way.
// MPL-2.0
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel openRelaySocket(Uri uri, String? proxy) {
  if (proxy == null || proxy.isEmpty) return WebSocketChannel.connect(uri);
  final client = HttpClient()..findProxy = (_) => 'PROXY $proxy';
  return IOWebSocketChannel.connect(uri, customClient: client);
}

/// Whether something listens on [proxy] (host:port), e.g. Orbot running.
Future<bool> proxyReachable(String proxy) async {
  final i = proxy.lastIndexOf(':');
  try {
    final s = await Socket.connect(proxy.substring(0, i), int.parse(proxy.substring(i + 1)), timeout: const Duration(seconds: 2));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

const bool proxySupported = true;
