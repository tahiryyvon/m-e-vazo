import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/services/local_audio_proxy_io.dart';

void main() {
  test('loopback proxy shares startup and rejects unauthenticated requests', () async {
    final proxy = LocalAudioProxy.instance;
    final client = HttpClient();
    addTearDown(() { client.close(force: true); proxy.dispose(); });
    final ports = await Future.wait([proxy.start(), proxy.start(), proxy.start()]);
    expect(ports.toSet().length, 1);
    expect(ports.first, greaterThan(0));
    for (final method in ['GET', 'POST', 'HEAD']) {
      final request = await client.openUrl(method,
          Uri.parse('http://127.0.0.1:${ports.first}/audio_dQw4w9WgXcQ.m4a'));
      final response = await request.close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    }
    await expectLater(proxy.getProxyStreamUrl('../invalid'), throwsArgumentError);
  });
}
