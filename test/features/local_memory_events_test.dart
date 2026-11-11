import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/core/memory/local_memory_store.dart';
import 'package:agent_voice_app/core/api/voice_protocol.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'voice_session_controller_test.dart' show FakeAudioBridge, waitUntil;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('negotiated local mode sends references and durably applies only accepted input', () async {
    final previousHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousHttp);
    final folder = await Directory.systemTemp.createTemp(
      'local-memory-events-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('agent_voice/local_memory'),
          (call) async => folder.path,
        );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final config = AppConfig(
      baseUrl: 'http://127.0.0.1:${server.port}',
      accessToken: 'test-token',
      userId: '42',
    );
    final store = LocalMemoryStore.forConfig(config);
    await store.save('用户希望简短回答', 'profile');
    final received = <Map<String, dynamic>>[];
    final bodies = <Map<String, dynamic>>[];
    WebSocket? socket;
    var extractions = 0;
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        socket = await WebSocketTransformer.upgrade(request);
        socket!.listen((raw) {
          final event = jsonDecode(raw as String) as Map<String, dynamic>;
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
          'input_modes': ['conversation', 'text'],
          'local_memory': {'enabled': true, 'version': 1},
        };
      } else if (request.uri.path == '/local-memories/extract') {
        extractions++;
        final body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        expect(request.headers.value('Authorization'), 'Bearer test-token');
        expect(request.uri.queryParameters['user_id'], '42');
        data = {
          'source_id': body['source_id'],
          'revision': (body['context'] as Map)['revision'],
          'epoch': (body['context'] as Map)['epoch'],
          'proposals': [
            {
              'action': 'add',
              'category': 'project',
              'text': '旅行短片采用暖色',
              'evidence': '旅行短片采用暖色',
              'requires_confirmation': false,
            },
          ],
        };
      } else {
        if (request.method == 'POST') {
          bodies.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
        }
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
    final controller = VoiceSessionController(config: config, audio: audio);
    addTearDown(() async {
      controller.dispose();
      await audio.close();
      await socket?.close();
      await server.close(force: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('agent_voice/local_memory'),
            null,
          );
      await folder.delete(recursive: true);
    });
    await controller.connect(
      agentId: 'chatbot',
      voice: 'Cherry',
      inputMode: 'text',
    );
    expect(bodies.single['memory_mode'], 'local');
    final response = newEventId();
    socket!.add(
      jsonEncode({
        'type': 'memory.context.request',
        'response_id': response,
        'text': '你好',
      }),
    );
    await waitUntil(
      () => received.any((event) => event['type'] == 'memory.context'),
    );
    final reference = received.firstWhere(
      (event) => event['type'] == 'memory.context',
    );
    expect((reference['context'] as Map)['memories'], hasLength(1));
    expect(extractions, 0);
    final source = newEventId();
    socket!.add(
      jsonEncode({
        'type': 'input.accepted',
        'turn_id': source,
        'text': '旅行短片采用暖色',
        'memory_eligible': true,
        'duplicate': false,
      }),
    );
    await waitUntil(() => store.entries.length == 2);
    socket!.add(
      jsonEncode({
        'type': 'input.accepted',
        'turn_id': source,
        'text': '旅行短片采用暖色',
        'memory_eligible': true,
        'duplicate': true,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(extractions, 1);
    expect(store.queued, 0);
    await controller.disconnect();
  });
}
