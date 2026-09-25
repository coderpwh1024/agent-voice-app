import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../config/app_config.dart';
import 'api_models.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => statusCode == 0 ? message : 'HTTP $statusCode: $message';
}

class AgentApiClient {
  AgentApiClient(this.config, {HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  final AppConfig config;
  final HttpClient _httpClient;

  Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(config.baseUrl.trim());
    final normalizedPath =
        '${base.path.replaceAll(RegExp(r'/$'), '')}/'
        '${path.replaceFirst(RegExp(r'^/'), '')}';
    return base.replace(path: normalizedPath, queryParameters: query);
  }

  Future<EmailCodeAccepted> requestEmailCode(String email) async {
    return EmailCodeAccepted.fromJson(
      await _request(
        'POST',
        '/auth/email/code',
        body: <String, Object?>{'email': email.trim().toLowerCase()},
        authenticated: false,
      ),
    );
  }

  Future<EmailAuthResult> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    return EmailAuthResult.fromJson(
      await _request(
        'POST',
        '/auth/email/verify',
        body: <String, Object?>{
          'email': email.trim().toLowerCase(),
          'code': code.trim(),
        },
        authenticated: false,
      ),
    );
  }

  Future<VoiceCapabilities> capabilities() async {
    return VoiceCapabilities.fromJson(
      await _request('GET', '/voice/capabilities'),
    );
  }

  Future<AuthUser> currentUser() async {
    return AuthUser.fromJson(await _request('GET', '/users/me'));
  }

  Future<AuthUser> updateCurrentUser({
    String? nickname,
    Uint8List? imageBytes,
    String? imageName,
    String? imageContentType,
  }) async {
    if (nickname == null && imageBytes == null) {
      throw const ApiException(0, '昵称或头像至少需要修改一项');
    }

    final boundary =
        '----AgentVoice${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final multipart = BytesBuilder(copy: false);

    void addText(String value) => multipart.add(utf8.encode(value));

    if (nickname != null) {
      addText('--$boundary\r\n');
      addText('Content-Disposition: form-data; name="nickname"\r\n\r\n');
      addText('$nickname\r\n');
    }
    if (imageBytes != null) {
      final safeName = (imageName ?? 'avatar.jpg').replaceAll(
        RegExp(r'[\r\n"]'),
        '_',
      );
      addText('--$boundary\r\n');
      addText(
        'Content-Disposition: form-data; name="image"; '
        'filename="$safeName"\r\n',
      );
      addText(
        'Content-Type: ${imageContentType ?? 'application/octet-stream'}\r\n\r\n',
      );
      multipart.add(imageBytes);
      addText('\r\n');
    }
    addText('--$boundary--\r\n');
    final payload = multipart.takeBytes();

    try {
      final request = await _httpClient.openUrl('PATCH', uri('/users/me'));
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${config.accessToken.trim()}',
      );
      request.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: <String, String>{'boundary': boundary},
      );
      request.contentLength = payload.length;
      request.add(payload);
      return AuthUser.fromJson(await _decodeResponse(await request.close()));
    } on ApiException {
      rethrow;
    } on SocketException catch (error) {
      throw ApiException(0, '无法连接后端：${error.message}');
    } on HandshakeException catch (error) {
      throw ApiException(0, 'TLS 握手失败：${error.message}');
    }
  }

  Future<VoiceSession> createVoiceSession({
    required String agentId,
    required String voice,
    String? threadId,
    String activation = 'tap',
    String? wakeWord,
    String? wakeEngine,
    int? preRollSamples,
  }) async {
    final body = <String, Object?>{
      'agent_id': agentId,
      'voice': voice,
      'language': 'zh',
      'turn_detection': 'server_vad',
      'activation': activation,
    };
    if (threadId != null) {
      body['thread_id'] = threadId;
    }
    if (activation == 'wake_word') {
      body['wake_word'] = wakeWord;
      body['wake_engine'] = wakeEngine;
      body['pre_roll_samples'] = preRollSamples ?? 0;
    }
    return VoiceSession.fromJson(
      await _request('POST', '/voice/sessions', body: body),
    );
  }

  Future<void> closeVoiceSession(String sessionId) async {
    await _request('DELETE', '/voice/sessions/$sessionId');
  }

  Future<List<ThreadSummary>> threads(String agentId) async {
    if (config.userId.trim().isEmpty) {
      throw const ApiException(0, '查看历史需要在设置中填写 user_id');
    }
    final json = await _request(
      'GET',
      '/$agentId/threads',
      query: <String, String>{'user_id': config.userId.trim(), 'limit': '50'},
    );
    return (json['threads'] as List<dynamic>? ?? const [])
        .map((item) => ThreadSummary.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<ChatItem>> history(String agentId, String threadId) async {
    final json = await _request(
      'POST',
      '/$agentId/history',
      body: <String, Object?>{'thread_id': threadId},
    );
    return (json['messages'] as List<dynamic>? ?? const [])
        .map((item) => ChatItem.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Uri websocketUri(String sessionId) {
    final httpUri = uri('/voice/sessions/$sessionId/ws');
    return httpUri.replace(scheme: httpUri.scheme == 'https' ? 'wss' : 'ws');
  }

  Map<String, dynamic> websocketHeaders() => <String, dynamic>{
    HttpHeaders.authorizationHeader: 'Bearer ${config.accessToken.trim()}',
  };

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    try {
      final request = await _httpClient.openUrl(method, uri(path, query));
      if (authenticated) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${config.accessToken.trim()}',
        );
      }
      request.headers.contentType = ContentType.json;
      if (body != null) {
        request.write(jsonEncode(body));
      }
      return await _decodeResponse(await request.close());
    } on ApiException {
      rethrow;
    } on SocketException catch (error) {
      throw ApiException(0, '无法连接后端：${error.message}');
    } on HandshakeException catch (error) {
      throw ApiException(0, 'TLS 握手失败：${error.message}');
    }
  }

  Future<Map<String, dynamic>> _decodeResponse(
    HttpClientResponse response,
  ) async {
    final text = await utf8.decoder.bind(response).join();
    final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _errorMessage(decoded, text);
      throw ApiException(response.statusCode, detail);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object');
    }
    if (decoded.containsKey('code') && decoded.containsKey('data')) {
      final code = decoded['code'];
      if (code != 200) {
        throw ApiException(
          response.statusCode,
          decoded['message']?.toString() ?? '请求失败',
        );
      }
      final data = decoded['data'];
      if (data == null) {
        return <String, dynamic>{};
      }
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Expected response data to be an object');
      }
      return data;
    }
    return decoded;
  }

  String _errorMessage(Object? decoded, String fallback) {
    if (decoded is! Map<String, dynamic>) {
      return fallback.isEmpty ? '请求失败' : fallback;
    }
    final detail = decoded['detail'];
    if (detail is String && detail.isNotEmpty) {
      return detail;
    }
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map<String, dynamic>) {
        return first['msg']?.toString() ?? '请求参数不正确';
      }
    }
    return decoded['message']?.toString() ??
        (fallback.isEmpty ? '请求失败' : fallback);
  }

  void close() => _httpClient.close(force: true);
}
