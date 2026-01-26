import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class SampleAudioPlatform {
  static Future<String> ensureSampleAudio() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/sample_note.wav');
    if (await file.exists()) {
      return file.path;
    }
    final bytes = _buildWavBytes(
      durationSeconds: 12,
      frequencyHz: 440,
      amplitude: 0.12,
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Uint8List _buildWavBytes({
    required int durationSeconds,
    required int frequencyHz,
    required double amplitude,
  }) {
    const sampleRate = 44100;
    const bitsPerSample = 16;
    const numChannels = 1;
    final totalSamples = sampleRate * durationSeconds;
    final bytesPerSample = bitsPerSample ~/ 8;
    final dataSize = totalSamples * bytesPerSample;

    final builder = BytesBuilder();
    builder.add(_ascii('RIFF'));
    builder.add(_u32le(36 + dataSize));
    builder.add(_ascii('WAVE'));
    builder.add(_ascii('fmt '));
    builder.add(_u32le(16));
    builder.add(_u16le(1));
    builder.add(_u16le(numChannels));
    builder.add(_u32le(sampleRate));
    builder.add(_u32le(sampleRate * numChannels * bytesPerSample));
    builder.add(_u16le(numChannels * bytesPerSample));
    builder.add(_u16le(bitsPerSample));
    builder.add(_ascii('data'));
    builder.add(_u32le(dataSize));

    final fadeSamples = (sampleRate * 0.2).round();
    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final envelope = _envelope(i, totalSamples, fadeSamples);
      final sample = sin(2 * pi * frequencyHz * t) * amplitude * envelope;
      final intSample = (sample * 32767).round();
      builder.add(_i16le(intSample));
    }

    return builder.toBytes();
  }

  static double _envelope(int index, int totalSamples, int fadeSamples) {
    if (fadeSamples == 0) {
      return 1;
    }
    if (index < fadeSamples) {
      return index / fadeSamples;
    }
    final tail = totalSamples - index;
    if (tail < fadeSamples) {
      return tail / fadeSamples;
    }
    return 1;
  }

  static List<int> _ascii(String value) => value.codeUnits;

  static List<int> _u32le(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> _u16le(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> _i16le(int value) {
    final data = ByteData(2)..setInt16(0, value, Endian.little);
    return data.buffer.asUint8List();
  }
}
