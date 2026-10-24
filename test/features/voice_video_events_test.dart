import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/video_reference_test.dart' show videoListSummary, videoSummary;
import 'voice_session_controller_test.dart' show FakeAudioBridge, waitUntil;

void main() {
  test('voice video events attach to the right reply, deduplicate and reject cancelled results', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    WebSocket? socket;
    final received = <Map<String, dynamic>>[];
    final wan = {
      ...videoSummary(),
      'model': 'wan3.0-video',
      'first_frame_url': 'https://cdn.example/first.png',
      'last_frame_url': 'https://cdn.example/last.png',
    };
    Object historyVideo = wan;
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        socket = await WebSocketTransformer.upgrade(request);
        socket!.listen((message) {
          if (message is String) {
            final event = jsonDecode(message) as Map<String, dynamic>;
            received.add(event);
            if (event['type'] == 'session.configure') {
              socket!.add(
                jsonEncode({
                  'type': 'session.ready',
                  'connection_id': '00112233-4455-6677-8899-aabbccddeeff',
                }),
              );
            }
          }
        });
        return;
      }
      Object data;
      if (request.uri.path == '/voice/capabilities') {
        data = {
          'enabled': true,
          'protocol_version': 1,
          'voices': ['Cherry'],
          'default_voice': 'Cherry',
        };
      } else if (request.uri.path.endsWith('/history')) {
        data = {
          'messages': [
            {
              'type': 'ai',
              'content': '这是刚才的视频',
              'response_metadata': {'video': historyVideo},
            },
          ],
        };
      } else if (request.method == 'POST') {
        data = {
          'session_id': 'session-1',
          'thread_id': 'thread-1',
          'agent_id': 'chatbot',
          'voice': 'Cherry',
          'expires_at': '2099-01-01T00:00:00Z',
        };
      } else {
        data = {'status': 'closing'};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'code': 200, 'data': data}));
      await request.response.close();
    });
    final audio = FakeAudioBridge();
    final controller = VoiceSessionController(
      config: AppConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        accessToken: 'test-token',
        userId: '42',
      ),
      audio: audio,
    );
    addTearDown(() async {
      controller.dispose();
      await audio.close();
      await server.close(force: true);
    });
    await controller.connect(agentId: 'chatbot', voice: 'Cherry');
    void emit(
      String type,
      String response, [
      Map<String, Object?> data = const {},
    ]) => socket!.add(
      jsonEncode({'type': type, 'response_id': response, ...data}),
    );
    emit('response.started', 'reply-1');
    emit('text.delta', 'reply-1', {'text': '查到了。'});
    emit('agent.custom', 'reply-1', {
      'data': {'type': 'video.task', 'video': wan},
    });
    emit('agent.custom', 'reply-1', {
      'data': {'type': 'video.task', 'video': wan},
    });
    emit('text.delta', 'reply-1', {'text': '点击卡片播放。'});
    await waitUntil(
      () =>
          controller.messages.isNotEmpty &&
          controller.messages.last.text.endsWith('播放。'),
    );
    expect(controller.messages.length, 1);
    expect(controller.messages.single.video!.recordId, 42);
    expect(controller.messages.single.video!.modelLabel, '万相 3.0 · 标准版');
    expect(
      controller.messages.single.video!.firstFrameUrl,
      wan['first_frame_url'],
    );
    expect(controller.messages.single.video!.playableUri, isNotNull);
    emit('response.cancelled', 'reply-1');
    emit('agent.custom', 'reply-1', {
      'data': {'type': 'video.task', 'video': videoSummary(status: 'RUNNING')},
    });
    emit('agent.custom', 'reply-2', {
      'data': {
        'type': 'video.task',
        'video': videoSummary(
          status: 'RUNNING',
          storage: 'NOT_READY',
          url: null,
        ),
      },
    });
    emit('response.started', 'reply-2');
    emit('text.delta', 'reply-2', {'text': '还在生成。'});
    await waitUntil(
      () =>
          controller.messages.length == 2 &&
          controller.messages.last.text == '还在生成。',
    );
    expect(controller.messages.first.video!.status, 'SUCCEEDED');
    expect(controller.messages.last.video!.status, 'RUNNING');
    emit('agent.custom', 'reply-2', {
      'data': {'type': 'other.task', 'video': videoSummary()},
    });
    emit('agent.custom', 'reply-2', {
      'data': {
        'type': 'video.task',
        'video': {'record_id': 'bad'},
      },
    });
    emit('text.delta', 'reply-2', {'text': '请稍候。'});
    await waitUntil(() => controller.messages.last.text.endsWith('请稍候。'));
    expect(controller.messages.last.video!.status, 'RUNNING');
    expect(controller.error, isNull);
    emit('agent.custom', 'search-reply', {'data': videoListSummary()});
    emit('response.started', 'search-reply');
    emit('agent.custom', 'search-reply', {'data': videoListSummary()});
    emit('text.delta', 'search-reply', {'text': '找到八个视频，先给你最近五个。'});
    await waitUntil(() => controller.messages.last.text.contains('八个视频'));
    expect(controller.messages.length, 3);
    expect(
      controller.messages.last.videoResults!.items.map((v) => v.recordId),
      [42, 43],
    );
    expect(controller.messages.last.videoResults!.total, 8);
    expect(
      controller.messages.last.videoResults!.items.last.playableUri.toString(),
      'https://cdn.example/second.mp4',
    );
    emit('agent.custom', 'search-reply', {
      'data': {...videoListSummary(), 'items': 'bad'},
    });
    emit('response.cancelled', 'search-reply');
    emit('agent.custom', 'search-reply', {
      'data': {...videoListSummary(), 'items': [], 'total': 0},
    });
    emit('response.started', 'empty-reply');
    emit('agent.custom', 'empty-reply', {
      'data': {
        ...videoListSummary(),
        'items': [],
        'total': 0,
        'total_pages': 0,
      },
    });
    emit('text.delta', 'empty-reply', {'text': '没有找到视频。'});
    await waitUntil(() => controller.messages.last.text == '没有找到视频。');
    expect(controller.messages[2].videoResults!.items.length, 2);
    expect(controller.messages.last.videoResults!.items, isEmpty);
    expect(controller.error, isNull);
    await controller.disconnect();
    await controller.loadHistory('chatbot', 'thread-1');
    expect(controller.messages.single.video!.playableUri, isNotNull);
    expect(
      controller.messages.single.video!.lastFrameUrl,
      wan['last_frame_url'],
    );
    historyVideo = videoListSummary();
    await controller.loadHistory('chatbot', 'thread-1');
    expect(controller.messages.single.videoResults!.items.length, 2);
    expect(controller.messages.single.videoResults!.total, 8);
    expect(received.where((e) => e['type'] == 'input.text'), isEmpty);
  });
}
