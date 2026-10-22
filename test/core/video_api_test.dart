import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/videos/data/video_api.dart';
import 'package:agent_voice_app/features/videos/data/video_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> videoJson({
  String status = 'PENDING',
  String storage = 'NOT_READY',
  String? url,
}) => {
  'id': 42,
  'user_id': 7,
  'task_id': 'upstream-1',
  'status': status,
  'storage_status': storage,
  'qiniu_video_url': url,
  'aliyun_video_url': 'https://temporary.example/private',
  'qiniu_object_key': null,
  'error_code': null,
  'create_time': '2026-10-22T01:00:00Z',
  'update_time': '2026-10-22T01:01:00Z',
};

void main() {
  late HttpServer server;
  late AgentApiClient client;
  late VideoApi api;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = AgentApiClient(
      AppConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        accessToken: 'test-token',
        userId: '7',
      ),
    );
    api = VideoApi(client.config, client: client);
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test('create, filtered pagination and detail follow the running backend contract', () async {
    final calls = <String>[];
    server.listen((request) async {
      expect(request.headers.value('authorization'), 'Bearer test-token');
      expect(request.uri.queryParameters.containsKey('user_id'), isFalse);
      calls.add('${request.method} ${request.uri.path}');
      Object data = videoJson();
      if (request.method == 'POST') {
        expect(request.headers.value('idempotency-key'), 'same-request');
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'prompt': '海边日落',
          'model': 'happyhorse-1.1-t2v',
          'resolution': '1080P',
          'ratio': '16:9',
          'duration': 5,
          'watermark': true,
          'seed': 42,
        });
        request.response.statusCode = 202;
      } else if (request.uri.path == '/videos') {
        expect(request.uri.queryParameters, {
          'page': '2',
          'page_size': '20',
          'status': 'SUCCEEDED',
          'storage_status': 'STORED',
        });
        data = {
          'items': [videoJson()],
          'total': 21,
          'page': 2,
          'page_size': 20,
          'total_pages': 2,
        };
      }
      request.response.write(
        jsonEncode({'code': 200, 'message': 'success', 'data': data}),
      );
      await request.response.close();
    });
    expect(
      (await api.create(
        const VideoDraft(prompt: ' 海边日落 ', seed: 42),
        'same-request',
      )).id,
      42,
    );
    final list = await api.list(
      page: 2,
      status: 'SUCCEEDED',
      storageStatus: 'STORED',
    );
    expect(list.total, 21);
    expect(list.hasMore, isFalse);
    expect((await api.detail(42)).status, 'PENDING');
    expect(calls, ['POST /videos', 'GET /videos', 'GET /videos/42']);
  });

  test(
    'retry uses the supplied key and never retries a POST automatically',
    () async {
      final keys = <String?>[];
      server.listen((request) async {
        keys.add(request.headers.value('idempotency-key'));
        await request.drain<void>();
        request.response.statusCode = keys.length == 1 ? 503 : 202;
        request.response.write(
          jsonEncode(
            keys.length == 1
                ? {'detail': 'unavailable'}
                : {'code': 200, 'data': videoJson()},
          ),
        );
        await request.response.close();
      });
      await expectLater(
        api.create(const VideoDraft(prompt: '海边日落'), 'same-request'),
        throwsA(isA<ApiException>()),
      );
      expect(keys, ['same-request']);
      await api.create(const VideoDraft(prompt: '海边日落'), 'same-request');
      expect(keys, ['same-request', 'same-request']);
    },
  );

  test('validates Unicode, model-specific resolution and numeric bounds', () {
    expect(VideoDraft(prompt: '😀' * 5000).validationError, isNull);
    expect(VideoDraft(prompt: '😀' * 5001).validationError, isNotNull);
    expect(VideoDraft(prompt: '中' * 2501).validationError, isNotNull);
    for (final draft in [
      const VideoDraft(prompt: ' '),
      const VideoDraft(
        prompt: 'x',
        model: 'happyhorse-1.0-t2v',
        resolution: '480P',
      ),
      const VideoDraft(prompt: 'x', duration: 2),
      const VideoDraft(prompt: 'x', duration: 16),
      const VideoDraft(prompt: 'x', seed: -1),
      const VideoDraft(prompt: 'x', seed: 2147483648),
    ]) {
      expect(draft.validationError, isNotNull);
    }
  });

  test('only archived successful HTTP(S) URLs are playable; statuses remain distinct', () {
    for (final data in [
      videoJson(status: 'SUCCEEDED', storage: 'FAILED'),
      videoJson(
        status: 'RUNNING',
        storage: 'STORED',
        url: 'https://cdn.example/a.mp4',
      ),
      videoJson(status: 'SUCCEEDED', storage: 'STORED', url: 'javascript:evil'),
    ]) {
      expect(VideoTask.fromJson(data).playableUri, isNull);
    }
    final task = VideoTask.fromJson(
      videoJson(
        status: 'SUCCEEDED',
        storage: 'STORED',
        url: 'https://cdn.example/a.mp4',
      ),
    );
    expect(task.playableUri!.host, 'cdn.example');
    expect(task.shouldPoll, isFalse);
    expect(
      VideoTask.fromJson(videoJson(status: 'SUCCEEDED', storage: 'FAILED'))
          .shouldPoll,
      isTrue,
    );
    expect(
      VideoTask.fromJson(videoJson(status: 'SUBMISSION_UNKNOWN')).shouldPoll,
      isFalse,
    );
  });
  for (final status in [401, 403, 404, 409, 422, 503]) {
    test('preserves HTTP $status', () async {
      server.listen((request) async {
        request.response.statusCode = status;
        request.response.write(jsonEncode({'detail': 'unavailable'}));
        await request.response.close();
      });
      await expectLater(
        api.detail(42),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', status),
        ),
      );
    });
  }
}
