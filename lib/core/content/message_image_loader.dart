import 'dart:io';
import 'dart:typed_data';

import 'message_content.dart';

class MessageImageLoader {
  static const maxBytes = 8 * 1024 * 1024;
  HttpClient? _client;

  Future<Uint8List> load(Uri uri) async {
    if (messageUri(uri.toString(), baseUrl: uri.toString()) == null) {
      throw const FormatException('图片地址不可用');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    _client = client;
    try {
      return await _read(client, uri).timeout(const Duration(seconds: 15));
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }

  Future<Uint8List> _read(HttpClient client, Uri uri) async {
    for (var redirects = 0; redirects <= 3; redirects++) {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'image/*');
      final response = await request.close();
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        final next = location == null
            ? null
            : messageUri(uri.resolve(location).toString(), baseUrl: uri.origin);
        if (next == null) throw const FormatException('图片地址不可用');
        await response.listen((_) {}).cancel();
        uri = next;
        continue;
      }
      if (response.statusCode != 200 || response.contentLength > maxBytes) {
        throw const FormatException('图片暂不可用或超过 8 MB');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (builder.length + chunk.length > maxBytes) {
          throw const FormatException('图片超过 8 MB');
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      final raster =
          bytes.length >= 12 &&
          ((bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) ||
              (bytes[0] == 0x89 &&
                  String.fromCharCodes(bytes.sublist(1, 4)) == 'PNG') ||
              [
                'GIF87a',
                'GIF89a',
              ].contains(String.fromCharCodes(bytes.sublist(0, 6))) ||
              (String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
                  String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') ||
              (bytes[0] == 66 && bytes[1] == 77));
      if (!raster) throw const FormatException('此资源可通过链接查看');
      return bytes;
    }
    throw const FormatException('图片跳转次数过多');
  }

  void close() => _client?.close(force: true);
}
