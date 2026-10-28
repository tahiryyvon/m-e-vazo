import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';
import 'audio_library_filter.dart';

const maxAudioFolderSongs = 5000;
const maxAudioFolderEntries = 50000;

Future<List<Song>?> pickAudioFolder() async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    final audio = await Permission.audio.request();
    if (!audio.isGranted) await Permission.storage.request();
  }
  final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Ajouter un dossier audio');
  if (path == null) return null;
  final songs = <Song>[];
  var scanned = 0;
  // A drive root or a huge tree must not freeze the app: stop after
  // [maxAudioFolderSongs] songs or [maxAudioFolderEntries] entries.
  try {
    await for (final entry in Directory(path).list(recursive: true, followLinks: false)) {
      if (++scanned > maxAudioFolderEntries || songs.length >= maxAudioFolderSongs) break;
      if (entry is File && isAudioFile(entry.path)) {
        songs.add(Song.fromLocalFile(entry.path));
      }
    }
  } on FileSystemException catch (e) {
    // Unreadable sub-folder (permissions): keep what was found so far.
    debugPrint('[AudioFolder] partial scan: $e');
  }
  songs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return songs;
}
