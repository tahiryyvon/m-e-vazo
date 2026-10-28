import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/services/public_web_client_io.dart';

void main() {
  test('rejects internal, metadata, mapped and reserved addresses', () {
    for (final ip in ['127.0.0.1', '10.0.0.1', '172.16.0.1', '192.168.1.1',
      '169.254.169.254', '100.64.0.1', '0.0.0.0', '224.0.0.1', '192.0.2.1',
      '198.51.100.1', '203.0.113.1', '::1', '::ffff:127.0.0.1', 'fc00::1', 'fe80::1', '2001:db8::1']) {
      expect(isPublicAddress(InternetAddress(ip)), isFalse, reason: ip);
    }
    for (final ip in ['8.8.8.8', '1.1.1.1', '2606:4700:4700::1111']) {
      expect(isPublicAddress(InternetAddress(ip)), isTrue, reason: ip);
    }
  });

  test('client refuses plain HTTP and private destinations before sending', () async {
    final client = createPublicWebClient();
    addTearDown(client.close);
    for (final url in ['http://example.com/', 'https://127.0.0.1/', 'https://localhost/',
        'https://user:pw@example.com/', 'https://example.com:8443/']) {
      await expectLater(client.get(Uri.parse(url)), throwsA(anything), reason: url);
    }
  });
}
