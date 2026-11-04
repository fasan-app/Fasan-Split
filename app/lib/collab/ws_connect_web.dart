// Browser: no proxy from the page (Tor Browser routes everything itself). MPL-2.0
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel openRelaySocket(Uri uri, String? proxy) => WebSocketChannel.connect(uri);

Future<bool> proxyReachable(String proxy) async => false;

const bool proxySupported = false;
