import 'dart:typed_data';

/// The anthem plays this long, from the very first bars of the song.
const Duration anthemLength = Duration(seconds: 10);

/// The last moments fade out so the music does not stop dead.
const Duration anthemFade = Duration(milliseconds: 1500);

/// A small mono WAV of [samples] (-1 to 1), with [fade] at the end. WAV is plain
/// sound with nothing to decode, so every phone plays it the same.
Uint8List encodeWav(
  List<double> samples,
  int sampleRate, {
  Duration fade = anthemFade,
}) {
  const headerSize = 44;
  const bytesPerSample = 2;
  final dataSize = samples.length * bytesPerSample;
  final out = ByteData(headerSize + dataSize);

  void writeText(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      out.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  writeText(0, 'RIFF');
  out.setUint32(4, 36 + dataSize, Endian.little);
  writeText(8, 'WAVE');
  writeText(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little); // plain sound samples
  out.setUint16(22, 1, Endian.little); // one channel
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * bytesPerSample, Endian.little);
  out.setUint16(32, bytesPerSample, Endian.little);
  out.setUint16(34, 8 * bytesPerSample, Endian.little);
  writeText(36, 'data');
  out.setUint32(40, dataSize, Endian.little);

  final fadeSamples = sampleRate * fade.inMilliseconds ~/ 1000;
  final fadeStart = samples.length - fadeSamples;
  for (var i = 0; i < samples.length; i++) {
    final gain = i < fadeStart ? 1.0 : (samples.length - i) / fadeSamples;
    final value = (samples[i] * gain).clamp(-1.0, 1.0);
    out.setInt16(
      headerSize + i * bytesPerSample,
      (value * 32767).round(),
      Endian.little,
    );
  }
  return out.buffer.asUint8List();
}
