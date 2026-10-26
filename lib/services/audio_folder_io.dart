import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';
import 'audio_library_filter.dart';

Future<List<Song>?> pickAudioFolder() async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    final audio = await Permission.audio.request();
    if (!audio.isGranted) await Permission.storage.request();
  }
  final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Ajouter un dossier audio');
  if (path == null) return null;
  final songs = <Song>[];
  await for (final entry in Directory(path).list(recursive: true, followLinks: false)) {
    if (entry is File && isAudioFile(entry.path)) {
      songs.add(Song.fromLocalFile(entry.path));
    }
  }
  songs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return songs;
}
