import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Title, artist and duration embedded in an audio file.
class AudioTags {
  final String? title;
  final String? artist;
  final int? durationSeconds;
  const AudioTags({this.title, this.artist, this.durationSeconds});

  bool get isEmpty => title == null && artist == null && durationSeconds == null;
}

/// Reads ID3v2 (2.2 / 2.3 / 2.4) and ID3v1 tags from MP3 files, so local
/// songs can be looked up on LRCLIB with their real title and artist rather
/// than a guess from the file name. Reads at most the tag header area.
class AudioTagReader {
  static const int _maxTagBytes = 512 * 1024;

  static Future<AudioTags?> read(String path) async {
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final length = await file.length();
      final head = await file.read(length < _maxTagBytes ? length : _maxTagBytes);
      var tags = parseId3v2(head);
      if ((tags == null || tags.title == null) && length >= 128) {
        await file.setPosition(length - 128);
        final v1 = parseId3v1(await file.read(128));
        if (v1 != null) {
          tags = AudioTags(
            title: tags?.title ?? v1.title,
            artist: tags?.artist ?? v1.artist,
            durationSeconds: tags?.durationSeconds,
          );
        }
      }
      return tags == null || tags.isEmpty ? null : tags;
    } catch (_) {
      return null;
    } finally {
      await file?.close();
    }
  }

  /// Parses an ID3v2 tag at the start of [bytes], or returns null.
  static AudioTags? parseId3v2(Uint8List bytes) {
    if (bytes.length < 10 || bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) {
      return null; // "ID3"
    }
    final version = bytes[3];
    if (version < 2 || version > 4) return null;
    final flags = bytes[5];
    final tagSize = _syncsafe(bytes, 6);
    final end = (10 + tagSize).clamp(0, bytes.length);
    var pos = 10;
    if (version >= 3 && (flags & 0x40) != 0 && pos + 4 <= end) {
      // Extended header: skip it.
      final extSize = version == 4 ? _syncsafe(bytes, pos) : _int32(bytes, pos) + 4;
      pos += extSize;
    }
    final idLength = version == 2 ? 3 : 4;
    final headerLength = version == 2 ? 6 : 10;
    String? title, artist;
    int? durationMs;
    while (pos + headerLength <= end) {
      final id = ascii.decode(bytes.sublist(pos, pos + idLength), allowInvalid: true);
      if (id.codeUnits.every((c) => c == 0)) break; // padding
      final size = version == 2
          ? (bytes[pos + 3] << 16) | (bytes[pos + 4] << 8) | bytes[pos + 5]
          : version == 4
              ? _syncsafe(bytes, pos + 4)
              : _int32(bytes, pos + 4);
      final dataStart = pos + headerLength;
      final dataEnd = dataStart + size;
      if (size <= 0 || dataEnd > end) break;
      final data = bytes.sublist(dataStart, dataEnd);
      switch (id) {
        case 'TIT2':
        case 'TT2':
          title = _text(data);
        case 'TPE1':
        case 'TP1':
          artist = _text(data);
        case 'TLEN':
        case 'TLE':
          durationMs = int.tryParse(_text(data) ?? '');
      }
      pos = dataEnd;
    }
    final tags = AudioTags(
      title: title,
      artist: artist,
      durationSeconds: durationMs != null && durationMs > 0 ? (durationMs / 1000).round() : null,
    );
    return tags.isEmpty ? null : tags;
  }

  /// Parses the 128-byte ID3v1 block found at the end of an MP3 file.
  static AudioTags? parseId3v1(Uint8List bytes) {
    if (bytes.length < 128 || bytes[0] != 0x54 || bytes[1] != 0x41 || bytes[2] != 0x47) {
      return null; // "TAG"
    }
    String? field(int start, int length) {
      final raw = bytes.sublist(start, start + length);
      final cut = raw.indexOf(0);
      final value = latin1.decode(cut >= 0 ? raw.sublist(0, cut) : raw).trim();
      return value.isEmpty ? null : value;
    }

    final tags = AudioTags(title: field(3, 30), artist: field(33, 30));
    return tags.isEmpty ? null : tags;
  }

  static int _syncsafe(Uint8List b, int o) =>
      ((b[o] & 0x7f) << 21) | ((b[o + 1] & 0x7f) << 14) | ((b[o + 2] & 0x7f) << 7) | (b[o + 3] & 0x7f);

  static int _int32(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  /// Decodes an ID3 text frame (encoding byte + text).
  static String? _text(Uint8List data) {
    if (data.isEmpty) return null;
    final body = data.sublist(1);
    String value;
    switch (data[0]) {
      case 1: // UTF-16 with BOM
      case 2: // UTF-16BE
        var bigEndian = data[0] == 2;
        var start = 0;
        if (body.length >= 2 && body[0] == 0xFF && body[1] == 0xFE) {
          bigEndian = false;
          start = 2;
        } else if (body.length >= 2 && body[0] == 0xFE && body[1] == 0xFF) {
          bigEndian = true;
          start = 2;
        }
        final units = <int>[];
        for (var i = start; i + 1 < body.length; i += 2) {
          final unit = bigEndian ? (body[i] << 8) | body[i + 1] : body[i] | (body[i + 1] << 8);
          if (unit == 0) break;
          units.add(unit);
        }
        value = String.fromCharCodes(units);
      case 3:
        value = utf8.decode(body, allowMalformed: true);
      default:
        value = latin1.decode(body);
    }
    final cut = value.indexOf('\u0000');
    if (cut >= 0) value = value.substring(0, cut);
    value = value.trim();
    return value.isEmpty ? null : value;
  }
}
