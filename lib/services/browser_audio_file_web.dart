import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

// URLs remain valid for this document, including a track removed while playing.
// The browser releases them on document unload; never persist them to storage.
String createAudioUrl(Uint8List bytes) =>
    web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));

/// Bytes behind a blob URL created for an imported file (same document).
/// Used once per played song to measure its real duration.
Future<Uint8List?> readBlobUrl(String url) async {
  if (!url.startsWith('blob:')) return null;
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) return null;
    final buffer = await response.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  } catch (_) {
    return null;
  }
}
