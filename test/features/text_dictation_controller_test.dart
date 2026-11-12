import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agent_voice_app/core/audio/audio_bridge.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/core/location/device_location.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'voice_session_controller_test.dart' show FakeAudioBridge, waitUntil;

class InputAudioBridge extends FakeAudioBridge {
  int permissionRequests = 0;
  bool permissionGranted = true;

  @override
  Future<bool> requestMicrophonePermission() async {
    permissionRequests++;
    return permissionGranted;
  }
}

class FakeDeviceLocationProvider implements DeviceLocationProvider {
  int requests = 0;
  DeviceLocationResult result = const DeviceLocationResult(
    DeviceLocationStatus.unavailable,
  );

  @override
  Future<DeviceLocationResult> currentLocation() async {
    requests++;
    return result;
  }
}

void main() {
  late HttpServer server;
  late InputAudioBridge audio;
  late FakeDeviceLocationProvider locationProvider;
  late VoiceSessionController controller;
  late List<Map<String, dynamic>> sessions;
  late List<Map<String, dynamic>> events;
  late List<WebSocket> sockets;
  late int audioFrames;
  late bool failTranscription;
  late String transcript;

  setUp(() async {
    sessions = [];
    events = [];
    sockets = [];
    audioFrames = 0;
    failTranscription = false;
    transcript = '嗯，帮我查一下。';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((message) {
          if (message is! String) {
            audioFrames++;
            return;
          }
          final event = jsonDecode(message) as Map<String, dynamic>;
          events.add(event);
          if (event['type'] == 'session.configure') {
            socket.add(
              jsonEncode({
                'type': 'session.ready',
                'connection_id': '00112233-4455-6677-8899-aabbccddeeff',
              }),
            );
          }
          if (event['type'] == 'input.commit') {
            socket.add(
              jsonEncode(
                failTranscription
                    ? {'type': 'error', 'code': 'asr_failed'}
                    : {'type': 'transcript.final', 'text': transcript},
              ),
            );
          }
        });
        return;
      }
      final Map<String, Object?> data;
      if (request.uri.path == '/voice/capabilities') {
        data = {
          'enabled': true,
          'protocol_version': 1,
          'voices': ['Cherry'],
          'input_modes': ['conversation', 'text', 'transcription'],
        };
      } else if (request.method == 'POST') {
        final body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        sessions.add(body);
        data = {
          'session_id': '11111111-2222-4333-8444-555555555555',
          'thread_id': body['thread_id'] ?? 'shared-thread',
          'agent_id': body['agent_id'],
          'voice': body['voice'],
          'input_mode': body['input_mode'] ?? 'conversation',
          'expires_at': '2099-01-01T00:00:00Z',
        };
      } else {
        data = request.uri.path.endsWith('/executions')
            ? {'executions': []}
            : {'status': 'closing'};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'code': 200, 'data': data}));
      await request.response.close();
    });
    audio = InputAudioBridge();
    locationProvider = FakeDeviceLocationProvider();
    controller = VoiceSessionController(
      config: AppConfig(
        baseUrl: 'http://${server.address.host}:${server.port}',
        accessToken: 'test-token',
        userId: '42',
      ),
      audio: audio,
      locationProvider: locationProvider,
    );
  });

  tearDown(() async {
    await controller.disconnect();
    controller.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await audio.close();
    await server.close(force: true);
  });

  test(
    'text connection plays answers without permission or audio upload',
    () async {
      audio.permissionGranted = false;
      await controller.connect(
        agentId: 'mem0-chatbot',
        voice: 'Cherry',
        inputMode: 'text',
      );
      expect(audio.permissionRequests, 0);
      expect(audio.startedModes, [AudioCaptureMode.playback]);
      expect(controller.state, VoiceConnectionState.ready);
      expect(sessions.single['input_mode'], 'text');
      expect(controller.session!.inputMode, 'text');
      audio.microphone.add(Uint8List(1280));
      controller.sendText('  用户输入  ');
      await waitUntil(
        () => events.any((event) => event['type'] == 'input.text'),
      );
      expect(
        events.lastWhere((event) => event['type'] == 'input.text')['text'],
        '用户输入',
      );
      expect(controller.messages.single.text, '用户输入');
      expect(audioFrames, 0);
      expect(() => controller.sendText('字' * 6001), throwsArgumentError);
      expect(controller.messages, hasLength(1));
    },
  );

  test('explicit current location sends one coordinate snapshot', () async {
    locationProvider.result = DeviceLocationResult(
      DeviceLocationStatus.ok,
      DeviceLocation(
        latitude: 39.9,
        longitude: 116.4,
        accuracyMeters: 12.5,
        capturedAt: DateTime.utc(2026, 11, 12, 8, 30),
      ),
    );
    await controller.connect(
      agentId: 'mem0-chatbot',
      voice: 'Cherry',
      inputMode: 'text',
    );

    expect(await controller.sendUserTextWithLocation('从当前位置出发去故宫'), isTrue);
    await waitUntil(() => events.any((event) => event['type'] == 'input.text'));
    final input = events.lastWhere((event) => event['type'] == 'input.text');
    expect(locationProvider.requests, 1);
    expect(input['device_location'], {
      'latitude': 39.9,
      'longitude': 116.4,
      'accuracy_meters': 12.5,
      'captured_at': '2026-11-12T08:30:00.000Z',
    });
    expect(controller.messages.single.text, '从当前位置出发去故宫');
  });

  test(
    'ordinary chat and named-place nearby query never request location',
    () async {
      await controller.connect(
        agentId: 'mem0-chatbot',
        voice: 'Cherry',
        inputMode: 'text',
      );
      expect(await controller.sendUserTextWithLocation('你好，今天天气怎么样'), isTrue);
      expect(await controller.sendUserTextWithLocation('王府井附近的咖啡店'), isTrue);
      await waitUntil(
        () =>
            events.where((event) => event['type'] == 'input.text').length == 2,
      );
      expect(locationProvider.requests, 0);
      expect(
        events
            .where((event) => event['type'] == 'input.text')
            .every((event) => !event.containsKey('device_location')),
        isTrue,
      );
    },
  );

  test('denied location still sends the original text', () async {
    locationProvider.result = const DeviceLocationResult(
      DeviceLocationStatus.denied,
      null,
      DeviceLocationFailure.permissionDenied,
    );
    await controller.connect(
      agentId: 'mem0-chatbot',
      voice: 'Cherry',
      inputMode: 'text',
    );
    expect(await controller.sendUserTextWithLocation('我附近有什么餐厅'), isTrue);
    await waitUntil(() => events.any((event) => event['type'] == 'input.text'));
    final input = events.lastWhere((event) => event['type'] == 'input.text');
    expect(locationProvider.requests, 1);
    expect(input['text'], '我附近有什么餐厅');
    expect(input.containsKey('device_location'), isFalse);
    expect(controller.locationNotice, contains('位置权限'));
  });

  test(
    'location timeout explains failure and still sends the original text',
    () async {
      locationProvider.result = const DeviceLocationResult(
        DeviceLocationStatus.unavailable,
        null,
        DeviceLocationFailure.timedOut,
      );
      await controller.connect(
        agentId: 'mem0-chatbot',
        voice: 'Cherry',
        inputMode: 'text',
      );

      expect(await controller.sendUserTextWithLocation('我现在在哪？'), isTrue);
      await waitUntil(
        () => events.any((event) => event['type'] == 'input.text'),
      );
      final input = events.lastWhere((event) => event['type'] == 'input.text');
      expect(input['text'], '我现在在哪？');
      expect(input.containsKey('device_location'), isFalse);
      expect(controller.locationNotice, contains('定位超时'));
    },
  );

  test('voice location request replies with status and coordinates', () async {
    locationProvider.result = DeviceLocationResult(
      DeviceLocationStatus.ok,
      DeviceLocation(
        latitude: 31.2,
        longitude: 121.5,
        accuracyMeters: 20,
        capturedAt: DateTime.utc(2026, 11, 12),
      ),
    );
    await controller.connect(agentId: 'mem0-chatbot', voice: 'Cherry');
    sockets.last.add(
      jsonEncode({'type': 'transcript.final', 'text': '我附近有什么'}),
    );
    await waitUntil(() => controller.messages.isNotEmpty);
    expect(locationProvider.requests, 0);
    sockets.last.add(
      jsonEncode({
        'type': 'location.request',
        'request_id': '11111111-2222-4333-8444-555555555555',
        'input_id': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      }),
    );
    await waitUntil(
      () => events.any((event) => event['type'] == 'location.result'),
    );
    final response = events.lastWhere(
      (event) => event['type'] == 'location.result',
    );
    expect(locationProvider.requests, 1);
    expect(response['status'], 'ok');
    expect(response['request_id'], '11111111-2222-4333-8444-555555555555');
    expect(response['event_id'], isA<String>());
    expect(response['device_location'], {
      'latitude': 31.2,
      'longitude': 121.5,
      'accuracy_meters': 20.0,
      'captured_at': '2026-11-12T00:00:00.000Z',
    });
    locationProvider.result = const DeviceLocationResult(
      DeviceLocationStatus.denied,
    );
    sockets.last.add(
      jsonEncode({
        'type': 'location.request',
        'request_id': 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff',
        'input_id': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      }),
    );
    await waitUntil(
      () =>
          events.where((event) => event['type'] == 'location.result').length ==
          2,
    );
    final denied = events.lastWhere(
      (event) => event['type'] == 'location.result',
    );
    expect(denied['status'], 'denied');
    expect(denied.containsKey('device_location'), isFalse);
  });

  test('background voice request never accesses device location', () async {
    await controller.connect(agentId: 'mem0-chatbot', voice: 'Cherry');
    controller.setBackgroundActive(false);
    sockets.last.add(
      jsonEncode({
        'type': 'location.request',
        'request_id': '11111111-2222-4333-8444-555555555555',
        'input_id': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      }),
    );
    await waitUntil(
      () => events.any((event) => event['type'] == 'location.result'),
    );
    final response = events.lastWhere(
      (event) => event['type'] == 'location.result',
    );
    expect(locationProvider.requests, 0);
    expect(response['status'], 'unavailable');
    expect(response.containsKey('device_location'), isFalse);
  });

  test(
    'failed answer without audio returns to text readiness and keeps input',
    () async {
      await controller.connect(
        agentId: 'mem0-chatbot',
        voice: 'Cherry',
        inputMode: 'text',
      );
      controller.sendText('测试失败保留输入');
      const responseId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
      for (final event in [
        {'type': 'response.started', 'response_id': responseId},
        {
          'type': 'error',
          'response_id': responseId,
          'code': 'agent_failed',
          'recoverable': true,
        },
        {
          'type': 'response.done',
          'response_id': responseId,
          'execution_status': 'failed',
          'audio_status': 'completed',
        },
      ]) {
        sockets.last.add(jsonEncode(event));
      }
      await waitUntil(() => controller.state == VoiceConnectionState.ready);
      expect(controller.currentResponseId, isNull);
      expect(controller.messages.first.text, '测试失败保留输入');
      expect(controller.error, contains('已保留你的输入'));
      expect(audio.completedResponses, [responseId]);
      controller.sendText('再次发送');
      expect(controller.messages.last.text, '再次发送');
      expect(controller.state, VoiceConnectionState.thinking);
    },
  );

  test(
    'dictation commits once, preserves fillers and waits for explicit send',
    () async {
      await controller.startDictation(agentId: 'mem0-chatbot', voice: 'Cherry');
      expect(controller.dictationState, DictationState.recording);
      expect(sessions.single['input_mode'], 'transcription');
      expect(sessions.single['turn_detection'], 'manual');
      expect(sessions.single['activation'], 'tap');
      sockets.last.add(
        jsonEncode({'type': 'transcript.partial', 'text': '嗯，'}),
      );
      await waitUntil(() => controller.partialTranscript == '嗯，');
      audio.microphone.add(Uint8List(1280));
      await waitUntil(() => audioFrames == 1);
      final draft = await controller.finishDictation();
      expect(draft, transcript);
      expect(controller.messages, isEmpty);
      expect(controller.isConnected, isFalse);
      expect(controller.dictationState, DictationState.idle);
      expect(
        events.where((event) => event['type'] == 'input.commit'),
        hasLength(1),
      );
      expect(events.where((event) => event['type'] == 'input.text'), isEmpty);
      await controller.connect(
        agentId: 'mem0-chatbot',
        voice: 'Cherry',
        inputMode: 'text',
      );
      expect(sessions.last['thread_id'], 'shared-thread');
      controller.sendText('$draft 编辑后发送');
      await waitUntil(
        () => events.any((event) => event['type'] == 'input.text'),
      );
      expect(controller.messages.single.text, '$draft 编辑后发送');
      expect(audio.permissionRequests, 1);
    },
  );

  test('empty dictation creates no chat message', () async {
    transcript = '';
    await controller.startDictation(agentId: 'mem0-chatbot', voice: 'Cherry');
    expect(await controller.finishDictation(), isEmpty);
    expect(controller.messages, isEmpty);
    expect(controller.isConnected, isFalse);
  });

  test(
    'dictation failure releases capture and keeps chat history intact',
    () async {
      failTranscription = true;
      await controller.startDictation(agentId: 'mem0-chatbot', voice: 'Cherry');
      await expectLater(controller.finishDictation(), throwsStateError);
      expect(controller.dictationState, DictationState.idle);
      expect(controller.isConnected, isFalse);
      expect(controller.messages, isEmpty);
      expect(controller.error, isNotNull);
    },
  );
}
