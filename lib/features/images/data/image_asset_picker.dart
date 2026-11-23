import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class StudioImageAsset {
  const StudioImageAsset(this.bytes, this.name, this.contentType);

  final Uint8List bytes;
  final String name, contentType;
}

class StudioImagePicker {
  static const maxReferenceBytes = 10 * 1024 * 1024;

  final _picker = ImagePicker();

  Future<StudioImageAsset?> pick() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    if (await file.length() > maxReferenceBytes) {
      throw const FormatException('图片不能超过 10 MB');
    }
    final bytes = await file.readAsBytes();
    final type = _type(bytes);
    if (type == null) {
      throw const FormatException('请选择 JPG、PNG、WebP、BMP、TIFF 或 GIF 图片');
    }
    return StudioImageAsset(bytes, file.name, type);
  }

  String? _type(Uint8List bytes) {
    if (bytes.length < 12) return null;
    if (bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255) {
      return 'image/jpeg';
    }
    if (bytes[0] == 137 && String.fromCharCodes(bytes.sublist(1, 4)) == 'PNG') {
      return 'image/png';
    }
    if (String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    if (bytes[0] == 66 && bytes[1] == 77) return 'image/bmp';
    final start = String.fromCharCodes(bytes.sublist(0, 4));
    if (start == 'II*\x00' || start == 'MM\x00*') return 'image/tiff';
    final gifHeader = String.fromCharCodes(bytes.sublist(0, 6));
    if (gifHeader == 'GIF87a' || gifHeader == 'GIF89a') return 'image/gif';
    return null;
  }
}
