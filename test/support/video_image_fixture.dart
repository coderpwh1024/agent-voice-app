import 'dart:typed_data';

/// A small opaque, valid 24-bit BMP without external files or personal photos.
Uint8List videoTestBmp({int width = 320, int height = 240}) {
  final stride = ((width * 3 + 3) ~/ 4) * 4;
  final bytes = Uint8List(54 + stride * height);
  final data = ByteData.sublistView(bytes);
  bytes[0] = 66;
  bytes[1] = 77;
  data.setUint32(2, bytes.length, Endian.little);
  data.setUint32(10, 54, Endian.little);
  data.setUint32(14, 40, Endian.little);
  data.setInt32(18, width, Endian.little);
  data.setInt32(22, height, Endian.little);
  data.setUint16(26, 1, Endian.little);
  data.setUint16(28, 24, Endian.little);
  data.setUint32(34, stride * height, Endian.little);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = 54 + y * stride + x * 3;
      bytes[offset] = 130;
      bytes[offset + 1] = 160 + (y * 60 ~/ height);
      bytes[offset + 2] = 100 + (x * 120 ~/ width);
    }
  }
  return bytes;
}
