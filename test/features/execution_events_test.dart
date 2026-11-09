import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'execution_progress_test.dart' show executionFixture;
import 'voice_session_controller_test.dart' show FakeAudioBridge, waitUntil;

void main() {
  test('execution events deduplicate, restore without replay and refresh one video per id', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    WebSocket? socket;
    final received = <Map<String, dynamic>>[];
    var snapshots = <Object?>[];
    var videoQueries = 0;
    var snapshotQueries = 0;
    final video = {
      'record_id': 7,
      'status': 'RUNNING',
      'storage_status': 'NOT_READY',
      'title': '海边',
    };
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        socket = await WebSocketTransformer.upgrade(request);
        socket!.listen((message) {
          if (message is! String) return;
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
      } else if (request.uri.path.endsWith('/executions')) {
        snapshotQueries++;
        data = {'executions': snapshots};
      } else if (request.uri.path == '/videos/7') {
        videoQueries++;
        data = {
          'id': 7,
          'status': 'SUCCEEDED',
          'storage_status': 'STORED',
          'qiniu_video_url': 'https://cdn.example/video.mp4',
        };
      } else if (request.uri.path.endsWith('/history')) {
        data = {'messages': []};
      } else {
        data = {
          'session_id': 'session-1',
          'thread_id': 'thread-1',
          'agent_id': 'chatbot',
          'voice': 'Cherry',
          'expires_at': '2099-01-01T00:00:00Z',
        };
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
    await controller.connect(
      agentId: 'chatbot',
      voice: 'Cherry',
      threadId: 'thread-1',
    );
    await waitUntil(() => snapshotQueries > 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    void emit(String type, [Map<String, Object?> extra = const {}]) => socket!
        .add(jsonEncode({'type': type, 'response_id': 'response-1', ...extra}));
    emit('response.started');
    emit('agent.custom', {'data': executionFixture(sequence: 2)});
    emit('agent.custom', {
      'data': executionFixture(sequence: 1, status: 'failed'),
    });
    emit('text.delta', {'text': '已处理'});
    emit('agent.custom', {
      'data': executionFixture(sequence: 3, status: 'succeeded', video: video),
    });
    emit('response.done', {'status': 'completed', 'audio_status': 'completed'});
    await waitUntil(
      () =>
          controller.messages.isNotEmpty &&
          controller.messages.single.execution?.sequence == 3 &&
          !controller.messages.single.isStreaming,
    );
    expect(controller.messages.single.text, '已处理');
    expect(controller.messages.single.execution!.status, 'succeeded');
    snapshots = [
      executionFixture(sequence: 3, status: 'succeeded', video: video),
    ];
    await controller.refreshExecutionState();
    expect(controller.messages.length, 1);
    expect(controller.messages.single.video!.playableUri, isNotNull);
    expect(videoQueries, 1);
    await controller.refreshExecutionState();
    expect(videoQueries, 1);
    emit('agent.custom', {
      'data': executionFixture(
        sequence: 4,
        status: 'waiting_confirmation',
        confirmation: true,
      ),
    });
    await waitUntil(
      () => controller.messages.single.execution?.confirmation != null,
    );
    controller.submitMemoryConfirmation('a' * 64, true);
    controller.submitMemoryConfirmation('a' * 64, true);
    await waitUntil(
      () => received.any((event) => event['type'] == 'memory.confirm'),
    );
    expect(
      received.where((event) => event['type'] == 'memory.confirm').length,
      1,
    );
    snapshots = [
      executionFixture(sequence: 5, status: 'succeeded', video: video),
    ];
    await controller.disconnect();
    await controller.loadHistory('chatbot', 'thread-1');
    expect(controller.messages.single.execution!.sequence, 5);
    expect(controller.messages.single.text, '已处理');
    expect(audio.operations.where((item) => item == 'audio'), isEmpty);
    controller.setBackgroundActive(false);
    final before = snapshotQueries;
    await controller.refreshExecutionState();
    expect(snapshotQueries, before);
  });
}
