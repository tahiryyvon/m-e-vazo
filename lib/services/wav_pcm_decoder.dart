import 'dart:typed_data';

/// PCM mono normalise [-1.0, 1.0] issu d'un fichier WAV.
class WavAudio {
  final Float32List samples;
  final int sampleRate;
  WavAudio(this.samples, this.sampleRate);
}

/// Decodeur WAV pur Dart. Supporte PCM lineaire 16-bit uniquement (mono ou
/// stereo, downmix vers mono). Retourne null si le format n'est pas gere
/// (compression, 8/24/32-bit, en-tete invalide) plutot que de lancer une
/// exception, pour permettre un fallback propre cote appelant.
class WavPcmDecoder {
  static WavAudio? decode(Uint8List bytes) {
    if (bytes.length < 44) return null;

    String tag(int offset) => String.fromCharCodes(bytes.sublist(offset, offset + 4));
    if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;

    final data = ByteData.sublistView(bytes);

    int offset = 12;
    int? sampleRate;
    int? bitsPerSample;
    int? numChannels;
    int? audioFormat;
    int? dataStart;
    int? dataLength;

    while (offset + 8 <= bytes.length) {
      final chunkId = tag(offset);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final chunkDataStart = offset + 8;
      if (chunkDataStart + chunkSize > bytes.length) break;

      if (chunkId == 'fmt ') {
        audioFormat = data.getUint16(chunkDataStart, Endian.little);
        numChannels = data.getUint16(chunkDataStart + 2, Endian.little);
        sampleRate = data.getUint32(chunkDataStart + 4, Endian.little);
        bitsPerSample = data.getUint16(chunkDataStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataStart = chunkDataStart;
        dataLength = chunkSize;
      }

      offset = chunkDataStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (sampleRate == null ||
        bitsPerSample == null ||
        numChannels == null ||
        dataStart == null ||
        dataLength == null ||
        numChannels == 0) {
      return null;
    }
    if (audioFormat != 1) return null; // seul le PCM non compresse est gere
    if (bitsPerSample != 16) return null; // MVP: 16-bit uniquement

    const bytesPerSample = 2;
    final safeLength = (dataStart + dataLength > bytes.length)
        ? bytes.length - dataStart
        : dataLength;
    final totalSamples = safeLength ~/ bytesPerSample;
    final frameCount = totalSamples ~/ numChannels;
    if (frameCount <= 0) return null;

    final mono = Float32List(frameCount);
    for (int f = 0; f < frameCount; f++) {
      double sum = 0;
      for (int c = 0; c < numChannels; c++) {
        final idx = dataStart + (f * numChannels + c) * bytesPerSample;
        if (idx + 1 >= bytes.length) break;
        sum += data.getInt16(idx, Endian.little) / 32768.0;
      }
      mono[f] = sum / numChannels;
    }

    return WavAudio(mono, sampleRate);
  }
}
