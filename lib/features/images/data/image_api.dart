import 'dart:async';
import 'dart:math';

import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';
import 'image_models.dart';

class ImageSubmission {
  ImageSubmission(this.draft, this.sourceImageId)
    : key =
          'image-${List.generate(24, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  static final _random = Random.secure();
  final ImageDraft draft;
  final int? sourceImageId;
  final String key;
}

class ImageApi {
  ImageApi(AppConfig config, {AgentApiClient? client})
    : _client = client ?? AgentApiClient(config),
      _ownsClient = client == null;

  final AgentApiClient _client;
  final bool _ownsClient;
  final Map<int?, ImageSubmission> pendingSubmissions = {};

  Future<T> _request<T>(
    String method,
    String path,
    T Function(Map<String, dynamic>) parse, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
  }) async {
    if (_client.config.accessToken.trim().isEmpty) {
      throw const ApiException(401, '请先登录');
    }
    try {
      final result = await _client
          .requestJson(method, path, query: query, body: body, headers: headers)
          .timeout(const Duration(seconds: 20));
      return parse(result);
    } on TimeoutException {
      throw const ApiException(504, '等待服务响应超时');
    } on FormatException {
      throw const ApiException(502, '服务返回异常');
    }
  }

  Future<ImageTaskPage> list({int page = 1}) => _request(
    'GET',
    '/images',
    ImageTaskPage.fromJson,
    query: {'page': '$page', 'page_size': '20'},
  );

  Future<ImageTask> detail(int id) =>
      _request('GET', '/images/$id', ImageTask.fromJson);

  Future<ImageTask> submit(ImageSubmission submission) async {
    final source = submission.sourceImageId;
    if (submission.draft.validate(hasSourceImage: source != null)
        case final error?) {
      throw ApiException(422, error);
    }
    return _request(
      'POST',
      source == null ? '/images' : '/images/$source/edits',
      ImageTask.fromJson,
      body: submission.draft.toJson(),
      headers: {'Idempotency-Key': submission.key},
    );
  }

  Future<ImageTask> rename(int id, String title) => _request(
    'PATCH',
    '/images/$id',
    ImageTask.fromJson,
    body: {'title': title.trim()},
  );

  Future<void> delete(int id) => _request('DELETE', '/images/$id', (result) {
    if (result['deleted'] != true) {
      throw const FormatException('Unconfirmed deletion');
    }
  });

  void close() {
    if (_ownsClient) _client.close();
  }
}

String imageError(Object error) => error is ApiException
    ? switch (error.statusCode) {
        0 => '网络连接中断，请检查网络后重试',
        401 => '登录已过期，请重新登录',
        403 => '当前账户没有访问权限',
        404 => '找不到这项图像任务',
        409 => '任务状态已变化，请刷新后再操作',
        422 => '提交内容不符合要求，请检查描述或参考图',
        429 => '正在处理的任务较多，请稍后再试',
        503 => '图像服务暂不可用，请稍后重试',
        504 => '等待服务响应超时，请稍后重试',
        _ => '图像服务暂时无法响应，请稍后重试',
      }
    : '操作未完成，请稍后重试';
