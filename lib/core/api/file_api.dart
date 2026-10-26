import 'dart:typed_data';

import '../config/app_config.dart';
import 'api_client.dart';
import 'video_reference.dart';

class UploadedFileMetadata {
  const UploadedFileMetadata({
    required this.id,
    required this.url,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    required this.uploadedAt,
  });
  final int id, sizeBytes;
  final String url, name, contentType;
  final DateTime uploadedAt;

  factory UploadedFileMetadata.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final size = json['size_bytes'];
    final url = json['url'];
    final name = json['original_name'];
    final type = json['content_type'];
    final at = json['uploaded_at'];
    if (id is! int ||
        id <= 0 ||
        size is! int ||
        size <= 0 ||
        url is! String ||
        VideoReference.imageUri(url) == null ||
        name is! String ||
        name.trim().isEmpty ||
        type is! String ||
        at is! String ||
        DateTime.tryParse(at) == null) {
      throw const FormatException('Invalid uploaded file metadata');
    }
    return UploadedFileMetadata(
      id: id,
      url: url,
      name: name,
      contentType: type,
      sizeBytes: size,
      uploadedAt: DateTime.parse(at),
    );
  }
}

class FileApi {
  FileApi(AppConfig config, {AgentApiClient? client})
    : _client = client ?? AgentApiClient(config),
      _ownsClient = client == null;
  final AgentApiClient _client;
  final bool _ownsClient;
  static const maxImageBytes = 20 * 1024 * 1024;

  Future<UploadedFileMetadata> upload({
    required Uint8List bytes,
    required String name,
    required String contentType,
  }) async {
    if (bytes.length > maxImageBytes) {
      throw const ApiException(413, '图片不能超过 20 MB');
    }
    try {
      return UploadedFileMetadata.fromJson(
        await _client.uploadFileJson(
          bytes: bytes,
          name: name,
          contentType: contentType,
        ),
      );
    } on FormatException {
      throw const ApiException(502, '上传结果无法确认，请重新上传');
    }
  }

  Future<UploadedFileMetadata> get(int id) async {
    if (id < 1) throw const ApiException(422, '文件编号无效');
    try {
      return UploadedFileMetadata.fromJson(
        await _client.requestJson('GET', '/files/$id/url'),
      );
    } on FormatException {
      throw const ApiException(502, '文件信息暂不可用');
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

String fileUploadError(Object error) => error is ApiException
    ? switch (error.statusCode) {
        401 => '登录已过期，请重新登录后上传',
        403 => '当前账号没有文件上传权限',
        404 => '找不到这张已上传图片，请重新选择',
        413 => '图片超过上传大小限制，请选择更小的图片',
        422 => '图片文件无效，请重新选择',
        502 => '图片上传未确认，请重试或更换图片',
        503 => '图片上传服务暂不可用，请稍后重试',
        _ => error.message,
      }
    : '图片上传失败，请检查网络后重试';
