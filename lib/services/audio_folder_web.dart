import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../models/song.dart';
import 'audio_library_filter.dart';

Future<List<Song>?> pickAudioFolder() async {
  final result = Completer<List<Song>?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true;
  input.setAttribute('webkitdirectory', '');
  input.style.display = 'none';
  input.addEventListener('change', ((web.Event event) {
    final files = input.files;
    final songs = <Song>[];
    if (files != null) {
      for (var i = 0; i < files.length; i++) {
        final file = files.item(i)!;
        if (!isAudioFile(file.name)) continue;
        // Keep browser File objects as blobs without reading the entire folder
        // into Dart memory before playback.
        final url = web.URL.createObjectURL(file);
        songs.add(Song.fromLocalFile(file.name).copyWith(id: 'local_$url', localPath: url));
      }
    }
    if (!result.isCompleted) result.complete(songs);
    input.remove();
  }).toJS);
  input.addEventListener('cancel', ((web.Event event) {
    if (!result.isCompleted) result.complete(null);
    input.remove();
  }).toJS);
  web.document.body!.appendChild(input);
  input.click();
  return result.future;
}
