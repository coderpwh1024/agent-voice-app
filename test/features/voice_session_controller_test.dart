import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agent_voice_app/core/audio/audio_bridge.dart';
import 'package:agent_voice_app/core/api/voice_protocol.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAudioBridge implements AudioBridge {
  final StreamController<Uint8List> microphone =
      StreamController<Uint8List>.broadcast();
  final StreamController<Map<String, dynamic>> playback =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<String> completedResponses = <String>[];
  final List<String> operations = <String>[];

  @override
  Stream<Uint8List> get microphoneFrames => microphone.stream;

  @override
  Stream<Map<String, dynamic>> get playbackEvents => playback.stream;

  @override
  Future<void> cancel(String responseId) async {}

  @override
  Future<void> completeResponse(String responseId) async {
    completedResponses.add(responseId);
    operations.add('response');
  }

  @override
  Future<void> completeSegment({
    required String responseId,
    required int segmentIndex,
    required int samples,
  }) async {
    operations.add('segment');
  }

  @override
  Future<void> enqueue(
    Uint8List pcm, {
    required String responseId,
    required int segmentIndex,
  }) async {
    operations.add('audio');
  }

  @override
  Future<void> pause() async {}

  @override
  Future<bool> requestMicrophonePermission() async => true;

  @override
  Future<void> resume() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  Future<void> close() async {
    await microphone.close();
    await playback.close();
  }
}

Uint8List outputAudioFrame({
  required String connectionId,
  required String responseId,
}) {
  List<int> uuidBytes(String value) {
    final compact = value.replaceAll('-', '');
    return List<int>.generate(
      16,
      (index) =>
          int.parse(compact.substring(index * 2, index * 2 + 2), radix: 16),
    );
  }

  final frame = Uint8List(audioHeaderBytes + 2);
  frame.setRange(0, 4, 'VCE1'.codeUnits);
  frame[4] = 2;
  frame.setRange(5, 21, uuidBytes(connectionId));
  frame.setRange(21, 37, uuidBytes(responseId));
  final data = ByteData.sublistView(frame);
  data.setUint32(37, 1);
  data.setUint32(41, 1);
  frame.setRange(audioHeaderBytes, frame.length, <int>[0, 0]);
  return frame;
}

Future<void> waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not reached');
}

void main() {
  test('waits for native playback before returning to listening', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final clientEvents = <Map<String, dynamic>>[];
    WebSocket? socket;
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        socket = await WebSocketTransformer.upgrade(request);
        socket!.listen((message) {
          if (message is String) {
            clientEvents.add(jsonDecode(message) as Map<String, dynamic>);
          }
        });
        await waitUntil(() => clientEvents.isNotEmpty);
        socket!.add(
          jsonEncode(<String, Object?>{
            'type': 'session.ready',
            'connection_id': '00112233-4455-6677-8899-aabbccddeeff',
          }),
        );
        return;
      }
      request.response.headers.contentType = ContentType.json;
      final data = switch ((request.method, request.uri.path)) {
        ('GET', '/voice/capabilities') => <String, Object?>{
          'enabled': true,
          'protocol_version': 1,
          'voices': <String>['Cherry'],
          'default_voice': 'Cherry',
          'agents': <Object?>[],
        },
        ('POST', '/voice/sessions') => <String, Object?>{
          'session_id': '11111111-2222-4333-8444-555555555555',
          'thread_id': 'thread-1',
          'agent_id': 'chatbot',
          'voice': 'Cherry',
          'expires_at': '2099-01-01T00:00:00Z',
        },
        ('DELETE', _) => <String, Object?>{'status': 'closing'},
        _ => throw StateError(
          'Unexpected request: ${request.method} ${request.uri.path}',
        ),
      };
      request.response.write(
        jsonEncode(<String, Object?>{
          'code': 200,
          'message': 'success',
          'data': data,
        }),
      );
      await request.response.close();
    });
    final audio = FakeAudioBridge();
    final controller = VoiceSessionController(
      config: AppConfig(
        baseUrl: 'http://${server.address.host}:${server.port}',
        accessToken: 'test-token',
        userId: '42',
      ),
      audio: audio,
    );

    await controller.connect(agentId: 'chatbot', voice: 'Cherry');
    const connectionId = '00112233-4455-6677-8899-aabbccddeeff';
    const responseId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    socket!.add(
      jsonEncode(<String, Object?>{
        'type': 'response.started',
        'response_id': responseId,
      }),
    );
    socket!.add(
      jsonEncode(<String, Object?>{
        'type': 'text.delta',
        'response_id': responseId,
        'text': '完整回答',
      }),
    );
    socket!.add(
      outputAudioFrame(connectionId: connectionId, responseId: responseId),
    );
    socket!.add(
      jsonEncode(<String, Object?>{
        'type': 'audio.segment.done',
        'response_id': responseId,
        'segment_index': 1,
        'samples': 1,
      }),
    );
    socket!.add(
      jsonEncode(<String, Object?>{
        'type': 'response.done',
        'response_id': responseId,
        'status': 'completed',
        'execution_status': 'completed',
        'audio_status': 'completed',
        'error_code': null,
      }),
    );

    await waitUntil(() => audio.completedResponses.contains(responseId));
    expect(audio.operations, <String>['audio', 'segment', 'response']);
    expect(controller.state, VoiceConnectionState.speaking);
    expect(controller.currentResponseId, responseId);

    audio.playback.add(<String, dynamic>{
      'type': 'response.finished',
      'responseId': responseId,
    });
    await waitUntil(() => controller.state == VoiceConnectionState.listening);
    expect(controller.currentResponseId, isNull);
    expect(
      clientEvents.any(
        (event) =>
            event['type'] == 'playback.finished' &&
            event['response_id'] == responseId,
      ),
      isTrue,
    );

    socket!.add(jsonEncode(<String, Object?>{'type': 'session.closed'}));
    await waitUntil(
      () => controller.state == VoiceConnectionState.disconnected,
    );
    controller.dispose();
    await audio.close();
    await server.close(force: true);
  });
}
