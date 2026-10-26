import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/file_api.dart';
import '../../../core/api/video_reference.dart';
import 'video_models.dart';

class PickedVideoImage {
  const PickedVideoImage(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

class VideoImagePicker {
  final _picker = ImagePicker();
  Future<PickedVideoImage?> pick() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    if (await file.length() > FileApi.maxImageBytes) {
      throw const FormatException('图片不能超过 20 MB，请选择更小的图片');
    }
    return PickedVideoImage(await file.readAsBytes(), file.name);
  }
}

class VideoImageFile {
  const VideoImageFile(this.bytes, this.name, this.contentType);
  final Uint8List bytes;
  final String name, contentType;

  static Future<VideoImageFile> validate(
    PickedVideoImage file, {
    bool forFrame = true,
  }) async {
    final b = file.bytes;
    if (b.isEmpty) throw const FormatException('这张图片是空文件，请重新选择');
    if (b.length > FileApi.maxImageBytes) {
      throw const FormatException('图片不能超过 20 MB，请选择更小的图片');
    }
    String? type;
    if (b.length >= 3 && b[0] == 255 && b[1] == 216 && b[2] == 255) {
      type = 'image/jpeg';
    }
    if (b.length >= 26 &&
        b[0] == 137 &&
        String.fromCharCodes(b.sublist(1, 4)) == 'PNG') {
      type = 'image/png';
      var offset = 8;
      while (offset + 12 <= b.length) {
        final length = ByteData.sublistView(b).getUint32(offset);
        final chunk = String.fromCharCodes(b.sublist(offset + 4, offset + 8));
        if (forFrame && (b[25] == 4 || b[25] == 6 || chunk == 'tRNS')) {
          throw const FormatException('请使用不含透明通道的图片，或选择 JPG 图片');
        }
        if (chunk == 'IDAT' || length > b.length - offset - 12) break;
        offset += length + 12;
      }
    }
    if (b.length >= 12 &&
        String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
      type = 'image/webp';
    }
    if (!forFrame &&
        b.length >= 6 &&
        ['GIF87a', 'GIF89a'].contains(String.fromCharCodes(b.sublist(0, 6)))) {
      type = 'image/gif';
    }
    if (b.length >= 2 && b[0] == 66 && b[1] == 77) type = 'image/bmp';
    if (type == null) throw const FormatException('请选择 JPG、PNG、WebP 或 BMP 图片');
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(b);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      if (w < (forFrame ? 240 : 1) ||
          h < (forFrame ? 240 : 1) ||
          w > 8000 ||
          h > 8000) {
        throw FormatException(
          forFrame ? '图片宽高需要在 240–8000 像素之间' : '封面宽高不能超过 8000 像素',
        );
      }
      if (forFrame && (w / h > 8 || h / w > 8)) {
        throw const FormatException('图片过长，请选择宽高比不超过 8:1 的图片');
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无法读取这张图片，请重新选择');
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
    final name = file.name.replaceAll('\\', '/').split('/').last.trim();
    if (name.isEmpty ||
        name.runes.length > 255 ||
        name.runes.any((r) => r < 32 || r == 127)) {
      throw const FormatException('图片文件名无效，请重命名后重新选择');
    }
    return VideoImageFile(b, name, type);
  }
}

/// Owns the selected image independently of a collapsed or hidden input widget.
class VideoImageAttachment extends ChangeNotifier {
  VideoImageAttachment(this.url, {this.forFrame = true})
    : previewUri = VideoReference.imageUri(url.text);
  final TextEditingController url;
  final bool forFrame;
  VideoImageFile? file;
  UploadedFileMetadata? uploaded;
  Uri? previewUri;
  String? error;
  bool busy = false, _disposed = false;
  bool get needsUpload => file != null && uploaded == null;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> pick(VideoImagePicker picker, FileApi api) async {
    if (busy) return;
    busy = true;
    error = null;
    _changed();
    try {
      final picked = await picker.pick();
      if (picked == null || _disposed) return;
      final image = await VideoImageFile.validate(picked, forFrame: forFrame);
      if (_disposed) return;
      file = image;
      uploaded = null;
      previewUri = null;
      url.clear();
      _changed();
      await _upload(api);
    } catch (e) {
      error = e is FormatException ? e.message : '无法读取相册，请检查照片访问权限后重试';
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> retry(FileApi api) async {
    if (busy || file == null) return;
    busy = true;
    error = null;
    _changed();
    try {
      await _upload(api);
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _upload(FileApi api) async {
    try {
      final image = file!;
      final result = await api.upload(
        bytes: image.bytes,
        name: image.name,
        contentType: image.contentType,
      );
      if (_disposed) return;
      if (VideoDraft.frameError(result.url, '图片') != null) {
        throw const FormatException('上传图片地址不可用');
      }
      uploaded = result;
      url.text = result.url;
      previewUri = VideoReference.imageUri(result.url);
    } catch (e) {
      if (!_disposed) error = fileUploadError(e);
    }
    _changed();
  }

  void addressChanged() {
    file = null;
    uploaded = null;
    previewUri = null;
    error = null;
    _changed();
  }

  void previewAddress({String label = '图片', bool cover = false}) {
    error = cover
        ? VideoDraft.coverError(url.text)
        : VideoDraft.frameError(url.text, label);
    previewUri = error == null ? VideoReference.imageUri(url.text) : null;
    _changed();
  }

  void clear() {
    if (busy) return;
    file = null;
    uploaded = null;
    previewUri = null;
    error = null;
    url.clear();
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
