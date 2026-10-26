import 'dart:async';
import 'dart:math';

import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';
import 'video_models.dart';

class VideoSubmission {
  const VideoSubmission(this.draft, this.key);
  final VideoDraft draft;
  final String key;
}

class VideoApi {
  VideoApi(AppConfig config, {AgentApiClient? client})
    : _client = client ?? AgentApiClient(config),
      _ownsClient = client == null;
  final AgentApiClient _client;
  final bool _ownsClient;
  VideoSubmission? pendingSubmission;
  static String newIdempotencyKey() {
    final random = Random.secure();
    return 'video-${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
  }) async {
    if (_client.config.accessToken.trim().isEmpty) {
      throw const ApiException(401, '请先登录');
    }
    try {
      return await _client
          .requestJson(method, path, query: query, body: body, headers: headers)
          .timeout(const Duration(seconds: 150));
    } on TimeoutException {
      throw const ApiException(504, '请求超时，请查询当前任务后再重试');
    } on FormatException {
      throw const ApiException(502, '服务返回异常，请稍后刷新');
    }
  }

  Future<VideoTask> create(VideoDraft draft, String idempotencyKey) async {
    if (draft.validationError case final error?) throw ApiException(422, error);
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(idempotencyKey)) {
      throw const ApiException(422, '请求标识无效');
    }
    return VideoTask.fromJson(
      await _request(
        'POST',
        '/videos',
        body: draft.toJson(),
        headers: {'Idempotency-Key': idempotencyKey},
      ),
    );
  }

  Future<VideoTaskPage> list({
    int page = 1,
    String? status,
    String? storageStatus,
    String? model,
  }) async {
    if (page < 1 || page > 2147483647) throw const ApiException(422, '页码无效');
    return VideoTaskPage.fromJson(
      await _request(
        'GET',
        '/videos',
        query: {
          'page': '$page',
          'page_size': '20',
          'status': ?status,
          'storage_status': ?storageStatus,
          'model': ?model,
        },
      ),
    );
  }

  Future<VideoTask> detail(int id) async {
    if (id < 1) throw const ApiException(422, '任务编号无效');
    return VideoTask.fromJson(await _request('GET', '/videos/$id'));
  }

  Future<VideoTask> updateMetadata(int id, VideoMetadataUpdate update) async {
    if (id < 1) throw const ApiException(422, '作品编号无效');
    if (update.validationError case final error?) {
      throw ApiException(422, error);
    }
    return VideoTask.fromJson(
      await _request('PATCH', '/videos/$id', body: update.toJson()),
    );
  }

  Future<void> delete(int id) async {
    if (id < 1) throw const ApiException(422, '作品编号无效');
    final result = await _request('DELETE', '/videos/$id');
    if (result['deleted'] != true) {
      throw const ApiException(502, '删除结果无法确认，请刷新作品列表核对');
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

String videoError(Object error) => error is ApiException
    ? switch (error.statusCode) {
        401 => '登录已过期，请返回个人主页重新登录',
        403 => '当前账号没有视频访问权限',
        404 => '没有找到该视频，请返回列表刷新',
        409 => '任务正在处理中，稍后刷新即可',
        503 => '视频服务暂未启用或正在维护，请稍后再试',
        504 => '查询超时，请稍后刷新。生成任务会在后台继续处理。',
        _ => error.message,
      }
    : '暂时无法连接视频服务，请检查网络后重试';
