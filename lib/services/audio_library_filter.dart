import '../models/song.dart';

const audioExtensions = {'mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg', 'wma', 'opus'};
bool isAudioFile(String name) => audioExtensions.contains(name.split('.').last.toLowerCase());

List<Song> filterLocalSongs(List<Song> songs, String query) {
  final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
  return songs.where((song) {
    final text = '${song.title} ${song.artist}'.toLowerCase();
    return words.every(text.contains);
  }).toList();
}
