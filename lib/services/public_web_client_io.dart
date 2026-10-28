import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Only globally routable addresses may receive external lyrics requests.
bool isPublicAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 16) {
    // Excludes mapped IPv4, loopback, ULA, link-local and multicast.
    return (b[0] & 0xe0) == 0x20 &&
        !(b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8);
  }
  if (b.length != 4) return false;
  return !(b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224 ||
      (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
      (b[0] == 169 && b[1] == 254) ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && (b[1] == 168 || b[1] == 0)) ||
      (b[0] == 198 && (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) ||
      (b[0] == 203 && b[1] == 0 && b[2] == 113));
}

http.Client createPublicWebClient() {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..maxConnectionsPerHost = 2
    ..findProxy = (_) => 'DIRECT';
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    if (uri.scheme != 'https' || uri.port != 443 || uri.userInfo.isNotEmpty) {
      throw const SocketException('Only public HTTPS lyrics pages are allowed');
    }
    final addresses = await InternetAddress.lookup(uri.host).timeout(const Duration(seconds: 6));
    if (addresses.isEmpty || addresses.any((address) => !isPublicAddress(address))) {
      throw const SocketException('Non-public lyrics destination refused');
    }
    // Connect to the checked IP itself: no second DNS lookup, so no
    // rebinding window. With a custom factory HttpClient does NOT add TLS on
    // direct connections: the factory must return a SecureSocket. The
    // looked-up InternetAddress keeps the hostname in `.host`, which
    // SecureSocket uses for SNI and certificate verification.
    return SecureSocket.startConnect(addresses.first, uri.port);
  };
  return IOClient(client);
}
