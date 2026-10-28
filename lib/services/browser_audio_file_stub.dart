import 'dart:typed_data';

String createAudioUrl(Uint8List bytes) => throw UnsupportedError('Browser only');

/// Bytes behind a browser blob URL; never called outside the browser.
Future<Uint8List?> readBlobUrl(String url) async => null;
