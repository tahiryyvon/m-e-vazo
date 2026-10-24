import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

// URLs remain valid for this document, including a track removed while playing.
// The browser releases them on document unload; never persist them to storage.
String createAudioUrl(Uint8List bytes) =>
    web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));
