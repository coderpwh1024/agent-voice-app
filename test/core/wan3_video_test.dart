import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/api/video_reference.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/videos/data/video_api.dart';
import 'package:agent_voice_app/features/videos/data/video_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_api_test.dart' show videoJson;

void main() {
  test('provider rejection is actionable and does not poll or play', () {
    const video = VideoReference(
      recordId: 42,
      status: 'FAILED',
      storageStatus: 'NOT_READY',
      model: 'wan3.0-video',
      errorCode: 'SUBMISSION_REJECTED',
    );
    expect(video.description, contains('权限与配置'));
    expect(video.shouldPoll, isFalse);
    expect(video.playableUri, isNull);
  });

  test('Wan models validate text, image modes and Unicode boundaries', () {
    for (final model in ['wan3.0-video', 'wan3.0-video-prime']) {
      for (final duration in [-1, 2, 30]) {
        expect(
          VideoDraft(
            prompt: '😀' * 20000,
            model: model,
            duration: duration,
            seed: -1,
            ratio: 'adaptive',
          ).validationError,
          isNull,
        );
      }
      expect(
        VideoDraft(prompt: '😀' * 20001, model: model).validationError,
        isNotNull,
      );
      expect(
        VideoDraft(prompt: '中' * 3000, model: model).validationError,
        isNull,
      );
      expect(
        VideoDraft(
          prompt: '',
          model: model,
          firstFrameUrl: ' https://cdn.example/a.png ',
        ).validationError,
        isNull,
      );
      for (final draft in [
        VideoDraft(prompt: '', model: model),
        VideoDraft(
          prompt: 'x',
          model: model,
          lastFrameUrl: 'https://cdn.example/b.png',
        ),
        VideoDraft(prompt: 'x', model: model, duration: 1),
        VideoDraft(prompt: 'x', model: model, duration: 31),
        VideoDraft(prompt: 'x', model: model, duration: -2),
        VideoDraft(prompt: 'x', model: model, seed: -2),
        VideoDraft(prompt: 'x', model: model, seed: 2147483648),
        for (final ratio in ['4:5', '5:4', '9:21'])
          VideoDraft(prompt: 'x', model: model, ratio: ratio),
        for (final url in [
          'file:///a.png',
          'https://user:pass@example.com/a.png',
          'http://',
          'https://example.com/${'😀' * 2048}',
        ])
          VideoDraft(prompt: 'x', model: model, firstFrameUrl: url),
      ]) {
        expect(draft.validationError, isNotNull, reason: '${draft.toJson()}');
      }
    }
  });

  test(
    'HappyHorse rejects Wan-only fields and preserves old serialization',
    () {
      for (final draft in [
        const VideoDraft(prompt: 'x', audio: false),
        const VideoDraft(prompt: 'x', promptExtend: true),
        const VideoDraft(
          prompt: 'x',
          firstFrameUrl: 'https://cdn.example/a.png',
        ),
        const VideoDraft(prompt: 'x', ratio: 'adaptive'),
      ]) {
        expect(draft.validationError, isNotNull);
      }
      final old = const VideoDraft(prompt: 'x').toJson();
      expect(old.keys, isNot(contains('audio')));
      expect(old.keys, isNot(contains('first_frame_url')));
      expect(VideoTask.fromJson(videoJson()).model, isNull);
      expect(
        VideoReference.tryParse({
          'record_id': 1,
          'status': 'RUNNING',
          'storage_status': 'NOT_READY',
        })!.modelLabel,
        isNull,
      );
    },
  );

  test(
    'Wan create, model filter and detail retain the backend response',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final api = VideoApi(
        AppConfig(
          baseUrl: 'http://127.0.0.1:${server.port}',
          accessToken: 'test',
          userId: '7',
        ),
      );
      addTearDown(() async {
        api.close();
        await server.close(force: true);
      });
      const draft = VideoDraft(
        prompt: '',
        model: 'wan3.0-video-prime',
        duration: -1,
        ratio: 'adaptive',
        seed: -1,
        audio: false,
        promptExtend: false,
        firstFrameUrl: ' https://cdn.example/first.png ',
        lastFrameUrl: 'https://cdn.example/last.png',
      );
      final data = {
        ...videoJson(),
        'model': draft.model,
        'first_frame_url': draft.firstFrameUrl!.trim(),
        'last_frame_url': draft.lastFrameUrl,
      };
      final keys = <String?>[];
      server.listen((request) async {
        expect(request.headers.value('authorization'), 'Bearer test');
        Object response = data;
        if (request.method == 'POST') {
          keys.add(request.headers.value('idempotency-key'));
          expect(
            jsonDecode(await utf8.decoder.bind(request).join()),
            draft.toJson(),
          );
          request.response.statusCode = 202;
        } else if (request.uri.path == '/videos') {
          expect(request.uri.queryParameters, {
            'page': '1',
            'page_size': '20',
            'model': draft.model,
            'status': 'PENDING',
          });
          response = {
            'items': [data],
            'total': 1,
            'page': 1,
            'total_pages': 1,
          };
        }
        request.response.write(jsonEncode({'code': 200, 'data': response}));
        await request.response.close();
      });
      final created = await api.create(draft, 'wan-same-key');
      await api.create(draft, 'wan-same-key');
      final listed = (await api.list(
        model: draft.model,
        status: 'PENDING',
      )).items.single;
      final detail = await api.detail(created.id);
      for (final item in [created, listed, detail]) {
        expect(item.model, draft.model);
        expect(item.modelLabel, '万相 3.0 · 高速版');
        expect(item.firstFrameUri.toString(), draft.firstFrameUrl!.trim());
        expect(item.lastFrameUri.toString(), draft.lastFrameUrl);
        expect(item.coverUrl, 'https://cdn.example/cover.jpg');
      }
      expect(keys, ['wan-same-key', 'wan-same-key']);
      final history = ChatItem.fromJson({
        'type': 'ai',
        'content': '视频',
        'response_metadata': {
          'video': {...data, 'record_id': 42},
        },
      });
      expect(history.video!.model, draft.model);
      expect(history.video!.firstFrameUrl, draft.firstFrameUrl!.trim());
      final page = VideoResultPage.tryParse({
        'type': 'video.list',
        'items': [
          {...data, 'record_id': 42},
        ],
        'total': 1,
        'page': 1,
        'total_pages': 1,
      })!;
      expect(page.items.single.lastFrameUrl, draft.lastFrameUrl);
    },
  );
}
