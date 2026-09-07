/// Model representing a song found on YouTube or from local storage
class Song {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final int? durationSeconds;
  final String? thumbnailUrl;
  final String? audioStreamUrl;
  final DateTime? publishedAt;

  /// True if this song comes from the local device storage
  final bool isLocal;

  /// Absolute path to the local audio file (only set when isLocal = true)
  final String? localPath;

  /// True if this song is an embedded asset track (e.g. demo song)
  final bool isAsset;

  /// Asset path (only set when isAsset = true)
  final String? assetPath;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.durationSeconds,
    this.thumbnailUrl,
    this.audioStreamUrl,
    this.publishedAt,
    this.isLocal = false,
    this.localPath,
    this.isAsset = false,
    this.assetPath,
  });

  factory Song.fromYoutubeExplode(dynamic video) {
    return Song(
      id: video.id.value,
      title: video.title,
      artist: video.author,
      durationSeconds: video.duration?.inSeconds,
      thumbnailUrl: video.thumbnails.highResUrl,
      publishedAt: video.uploadDate,
      isLocal: false,
    );
  }

  /// Creates a Song from a local file path
  factory Song.fromLocalFile(String path) {
    final fileName = path.split(RegExp(r'[\\/]')).last;
    final nameWithoutExt = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    // Try to split "Artist - Title" pattern
    final parts = nameWithoutExt.split(' - ');
    final artist = parts.length >= 2 ? parts.first.trim() : 'Unknown Artist';
    final title = parts.length >= 2 ? parts.sublist(1).join(' - ').trim() : nameWithoutExt;

    return Song(
      id: 'local_$path',
      title: title,
      artist: artist,
      isLocal: true,
      localPath: path,
    );
  }

  /// Creates a Song from an embedded asset track (e.g. demo song)
  factory Song.demo({
    required String id,
    required String title,
    required String artist,
    required String assetPath,
    int? durationSeconds,
  }) {
    return Song(
      id: id,
      title: title,
      artist: artist,
      durationSeconds: durationSeconds ?? 24,
      isLocal: false,
      isAsset: true,
      assetPath: assetPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      if (album != null) 'album': album,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (audioStreamUrl != null) 'audioStreamUrl': audioStreamUrl,
      if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
      'isLocal': isLocal,
      if (localPath != null) 'localPath': localPath,
      'isAsset': isAsset,
      if (assetPath != null) 'assetPath': assetPath,
    };
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String?,
      durationSeconds: json['durationSeconds'] as int?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      audioStreamUrl: json['audioStreamUrl'] as String?,
      publishedAt: json['publishedAt'] != null
          ? DateTime.tryParse(json['publishedAt'] as String)
          : null,
      isLocal: json['isLocal'] as bool? ?? false,
      localPath: json['localPath'] as String?,
      isAsset: json['isAsset'] as bool? ?? false,
      assetPath: json['assetPath'] as String?,
    );
  }

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
    String? thumbnailUrl,
    String? audioStreamUrl,
    DateTime? publishedAt,
    bool? isLocal,
    String? localPath,
    bool? isAsset,
    String? assetPath,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      audioStreamUrl: audioStreamUrl ?? this.audioStreamUrl,
      publishedAt: publishedAt ?? this.publishedAt,
      isLocal: isLocal ?? this.isLocal,
      localPath: localPath ?? this.localPath,
      isAsset: isAsset ?? this.isAsset,
      assetPath: assetPath ?? this.assetPath,
    );
  }

  @override
  String toString() => 'Song(title: $title, artist: $artist, isLocal: $isLocal, isAsset: $isAsset)';
}

