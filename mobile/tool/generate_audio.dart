import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() {
  final output = Directory('assets/audio')..createSync(recursive: true);
  _writeWav(File('${output.path}/place.wav'), const [380], triangle: true);
  _writeWav(File('${output.path}/invalid.wav'), const [130]);
  _writeWav(File('${output.path}/click.wav'), const [640]);
  _writeWav(File('${output.path}/match.wav'), const [660, 880, 660, 1046]);
  _writeWav(File('${output.path}/win.wav'), const [392, 494, 587, 784]);
}

void _writeWav(File file, List<double> frequencies, {bool triangle = false}) {
  const sampleRate = 44100;
  const note = .25;
  const gap = .13;
  final double duration = note + gap * (frequencies.length - 1);
  final int samples = (sampleRate * duration).ceil();
  final pcm = Int16List(samples);
  for (var i = 0; i < samples; i++) {
    final double time = i / sampleRate;
    var value = 0.0;
    for (var noteIndex = 0; noteIndex < frequencies.length; noteIndex++) {
      final double local = time - noteIndex * gap;
      if (local < 0 || local >= note) continue;
      final double attack = min(1, local / .005);
      final double release = exp(-26 * max(0, local - .01));
      final double frequency = triangle
          ? frequencies[noteIndex] *
                pow(100 / frequencies[noteIndex], local / .1).clamp(0, 1)
          : frequencies[noteIndex];
      final double phase = 2 * pi * frequency * local;
      final double wave = triangle ? 2 / pi * asin(sin(phase)) : sin(phase);
      value += wave * attack * release * (frequencies.length > 1 ? .18 : .28);
    }
    pcm[i] = (value.clamp(-1, 1) * 32767).round();
  }
  final int dataBytes = pcm.lengthInBytes;
  final bytes = ByteData(44 + dataBytes);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  bytes.buffer.asInt16List(44, pcm.length).setAll(0, pcm);
  file.writeAsBytesSync(bytes.buffer.asUint8List(), flush: true);
}
