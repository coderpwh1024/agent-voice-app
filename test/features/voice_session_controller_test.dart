import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agent_voice_app/core/audio/audio_bridge.dart';
import 'package:agent_voice_app/core/audio/wake_word_detector.dart';
import 'package:agent_voice_app/core/api/voice_protocol.dart';
import 'package:agent_voice_app/core/api/api_models.dart';
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
  final List<AudioCaptureMode> startedModes = <AudioCaptureMode>[];
  Future<void> Function()? onPermissionRequest;
  int pauseCalls = 0;
  int resumeCalls = 0;

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
  Future<void> pause() async => pauseCalls++;

  @override
  Future<bool> requestMicrophonePermission() async {
    await onPermissionRequest?.call();
    return true;
  }

  @override
  Future<void> resume() async => resumeCalls++;

  @override
  Future<AudioProcessingState> start(AudioCaptureMode mode) async {
    startedModes.add(mode);
    return AudioProcessingState(
      mode: mode,
      aecAvailable: true,
      aecEnabled: mode == AudioCaptureMode.conversation,
      noiseSuppressionAvailable: true,
      noiseSuppressionEnabled: true,
    );
  }

  @override
  Future<void> stop() async {}

  Future<void> close() async {
    await microphone.close();
    await playback.close();
  }
}

class FakeWakeWordDetector implements WakeWordDetector {
  final StreamController<WakeDetection> controller =
      StreamController<WakeDetection>.broadcast();
  final List<Uint8List> frames = <Uint8List>[];
  final List<WakeWordConfig> configs = <WakeWordConfig>[];

  @override
  Stream<WakeDetection> get detections => controller.stream;

  @override
  void addPcm(Uint8List pcm) => frames.add(Uint8List.fromList(pcm));

  @override
  Future<void> initialize(WakeWordConfig config) async {
    configs.add(config);
  }

  @override
  void reset() {}

  void trigger() => controller.add(const WakeDetection(keyword: '小美小美'));

  @override
  Future<void> dispose() => controller.close();
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
  test('restoring history preserves the backend memory result', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.uri.path, '/mem0-chatbot/history');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer test-token',
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': 200,
          'data': {
            'messages': [
              {'type': 'human', 'content': '记住我的偏好'},
              {
                'type': 'ai',
                'content': '已完成本轮回答',
                'response_metadata': {'memory_status': 'write_failed'},
              },
            ],
          },
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
    try {
      await controller.loadHistory('mem0-chatbot', 'mem0-thread');
      expect(controller.messages.first.memoryStatus, isNull);
      expect(controller.messages.last.memoryStatus, MemoryStatus.writeFailed);
      expect(
        controller.messages.last.copyWith(text: '新文本').memoryStatus,
        MemoryStatus.writeFailed,
      );
      controller.clearConversation();
      expect(controller.messages, isEmpty);
    } finally {
      controller.dispose();
      await audio.close();
      await server.close(force: true);
    }
  });

  test(
    'refreshes model voices before creating a session after an upgrade',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var reads = 0;
      String? submittedVoice;
      server.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          socket.listen((message) {
            final event = jsonDecode(message as String) as Map<String, dynamic>;
            if (event['type'] == 'session.configure') {
              socket.add(
                jsonEncode({
                  'type': 'session.ready',
                  'connection_id': '00112233-4455-6677-8899-aabbccddeeff',
                }),
              );
            }
          });
          return;
        }
        request.response.headers.contentType = ContentType.json;
        Map<String, Object?> data;
        if (request.uri.path == '/voice/capabilities') {
          reads += 1;
          final voice = reads == 1 ? 'Cherry' : 'longanhuan_v3.1';
          data = {
            'enabled': true,
            'protocol_version': 1,
            'voices': [voice],
            'default_voice': voice,
          };
        } else if (request.method == 'POST') {
          final body = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
          submittedVoice = body['voice'] as String;
          data = {
            'session_id': '11111111-2222-4333-8444-555555555555',
            'thread_id': 'thread-1',
            'agent_id': 'chatbot',
            'voice': submittedVoice,
            'expires_at': '2099-01-01T00:00:00Z',
          };
        } else {
          data = {'status': 'closing'};
        }
        request.response.write(
          jsonEncode({'code': 200, 'message': 'success', 'data': data}),
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
      try {
        await controller.loadCapabilities();
        expect(controller.capabilities!.defaultVoice, 'Cherry');
        await controller.connect(agentId: 'chatbot', voice: 'Cherry');
        expect(reads, 2);
        expect(submittedVoice, 'longanhuan_v3.1');
        expect(controller.session!.voice, 'longanhuan_v3.1');
        expect(controller.isConnected, isTrue);
      } finally {
        controller.dispose();
        await audio.close();
        await server.close(force: true);
      }
    },
  );

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
          'client_vad': <String, Object?>{
            'enabled': true,
            'rms_dbfs': -42,
            'speech_frames': 3,
          },
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
    addTearDown(() async {
      controller.dispose();
      await audio.close();
      await server.close(force: true);
    });
    Future<void> expectIgnoredPunctuation(VoiceConnectionState state) async {
      const noise = <String>[
        '。',
        '.',
        '...',
        '．',
        '，？！',
        '；：',
        '——',
        '“”',
        '（ ）',
        '嗯。',
      ];
      final partials = <String>[];
      void recordPartial() => partials.add(controller.partialTranscript);
      controller.addListener(recordPartial);
      try {
        for (final text in noise) {
          socket!.add(jsonEncode({'type': 'transcript.partial', 'text': text}));
          socket!.add(jsonEncode({'type': 'transcript.final', 'text': text}));
        }
        socket!.add(
          jsonEncode({'type': 'transcript.partial', 'text': '正常字幕。'}),
        );
        await waitUntil(() => controller.partialTranscript == '正常字幕。');
        expect(partials.where(noise.contains), isEmpty);
        expect(
          controller.messages.where((entry) => entry.role == 'human'),
          isEmpty,
        );
        expect(controller.state, state);
        socket!.add(jsonEncode({'type': 'transcript.final', 'text': ''}));
        await waitUntil(() => controller.partialTranscript.isEmpty);
      } finally {
        controller.removeListener(recordPartial);
      }
    }

    await expectIgnoredPunctuation(VoiceConnectionState.listening);
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
    await waitUntil(
      () =>
          controller.messages.isNotEmpty &&
          controller.messages.last.text == '完整回答',
    );
    expect(controller.state, VoiceConnectionState.thinking);
    await expectIgnoredPunctuation(VoiceConnectionState.thinking);
    socket!.add(jsonEncode(<String, Object?>{'type': 'input.started'}));
    socket!.add(
      jsonEncode(<String, Object?>{'type': 'transcript.final', 'text': ''}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.state, VoiceConnectionState.thinking);
    socket!.add(
      jsonEncode(<String, Object?>{
        'type': 'playback.resume',
        'response_id': responseId,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.state, VoiceConnectionState.thinking);
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
        'latency_ms': <String, int>{'text_to_audio_ms': 30},
      }),
    );

    await waitUntil(() => audio.completedResponses.contains(responseId));
    expect(controller.responseLatencyMs['first_text_ms'], isNonNegative);
    expect(controller.responseLatencyMs['text_to_audio_ms'], isNonNegative);
    expect(controller.responseLatencyMs['native_enqueue_ms'], isNonNegative);
    expect(controller.responseLatencyMs['server_text_to_audio_ms'], 30);
    expect(audio.operations, <String>['audio', 'segment', 'response']);
    expect(controller.state, VoiceConnectionState.speaking);
    expect(controller.currentResponseId, responseId);
    final loudFrame = Uint8List(1280);
    final samples = ByteData.sublistView(loudFrame);
    for (var index = 0; index < 640; index++) {
      samples.setInt16(index * 2, 3000, Endian.little);
    }
    for (var index = 0; index < 3; index++) {
      audio.microphone.add(loudFrame);
    }
    await waitUntil(
      () => clientEvents.any((event) => event['type'] == 'input.speech_hint'),
    );
    expect(
      audio.pauseCalls,
      0,
      reason: 'RMS alone must not interrupt playback',
    );
    await controller.speechHint();
    expect(audio.pauseCalls, 1, reason: 'An explicit interruption pauses now');
    final resumesBeforeTimeout = audio.resumeCalls;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(audio.resumeCalls, greaterThan(resumesBeforeTimeout));
    await expectIgnoredPunctuation(VoiceConnectionState.speaking);
    expect(
      controller.messages.where((entry) => entry.role == 'human'),
      isEmpty,
    );

    audio.playback.add(<String, dynamic>{
      'type': 'response.finished',
      'responseId': '99999999-8888-4777-8666-555555555555',
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
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
    socket!.add(
      jsonEncode({'type': 'transcript.final', 'text': 'C++ 的 1.5 版本，怎么用？'}),
    );
    await waitUntil(
      () => controller.messages.any((entry) => entry.role == 'human'),
    );
    expect(controller.messages.last.text, 'C++ 的 1.5 版本，怎么用？');

    socket!.add(jsonEncode(<String, Object?>{'type': 'session.closed'}));
    await waitUntil(
      () => controller.state == VoiceConnectionState.disconnected,
    );
  });

  for (final wakeCase
      in <({String transcript, String? command, String expected})>[
        (
          transcript: '小美，小美，小美，介绍一下你自己',
          command: '介绍一下你自己',
          expected: '介绍一下你自己',
        ),
        (transcript: '小美小美小美', command: '', expected: ''),
        (transcript: ' 小 美，小美、小美，介绍一下你自己', command: null, expected: '介绍一下你自己'),
        (transcript: '小美，小美，小美。', command: null, expected: ''),
        (transcript: '小美小美。', command: '。', expected: ''),
      ]) {
    test(
      'wake confirmation strips repeated calls: ${wakeCase.transcript}',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final createdBodies = <Map<String, dynamic>>[];
        final receivedPcm = <int>[];
        var capabilityReads = 0;
        WebSocket? wakeSocket;
        server.listen((request) async {
          if (WebSocketTransformer.isUpgradeRequest(request)) {
            wakeSocket = await WebSocketTransformer.upgrade(request);
            wakeSocket!.listen((message) {
              if (message is List<int>) {
                receivedPcm.addAll(message.skip(audioHeaderBytes));
              }
            });
            await Future<void>.delayed(const Duration(milliseconds: 10));
            wakeSocket!.add(
              jsonEncode(<String, Object?>{
                'type': 'session.ready',
                'connection_id': '00112233-4455-6677-8899-aabbccddeeff',
              }),
            );
            return;
          }
          if (request.uri.path == '/voice/capabilities') capabilityReads++;
          if (request.method == 'POST') {
            createdBodies.add(
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>,
            );
          }
          request.response.headers.contentType = ContentType.json;
          final data = switch ((request.method, request.uri.path)) {
            ('GET', '/voice/capabilities') => <String, Object?>{
              'enabled': true,
              'protocol_version': 1,
              'voices': <String>['Cherry'],
              'default_voice': 'Cherry',
              'wake_word': <String, Object?>{
                'enabled': true,
                'keyword': '小美小美',
                'confirm_with_asr': true,
                'pre_roll_ms': 4000,
                'kws_score': capabilityReads == 1 ? 1.0 : 1.5,
                'kws_threshold': capabilityReads == 1 ? 0.5 : 0.25,
              },
              'client_vad': <String, Object?>{
                'enabled': true,
                'rms_dbfs': -42,
                'speech_frames': 3,
              },
              'audio_metrics_seconds': 5,
              'agents': <Object?>[],
            },
            ('POST', '/voice/sessions') => <String, Object?>{
              'session_id': '11111111-2222-4333-8444-555555555555',
              'thread_id': 'thread-1',
              'agent_id': 'chatbot',
              'voice': 'Cherry',
              'activation': 'wake_word',
              'wake_status': 'pending',
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
        final wake = FakeWakeWordDetector();
        final controller = VoiceSessionController(
          config: AppConfig(
            baseUrl: 'http://${server.address.host}:${server.port}',
            accessToken: 'test-token',
            userId: '42',
          ),
          audio: audio,
          wakeWordDetector: wake,
        );

        await controller.loadCapabilities();
        await controller.enableWakeWord(agentId: 'chatbot', voice: 'Cherry');
        for (var index = 0; index < 120; index++) {
          audio.microphone.add(Uint8List(1280)..fillRange(0, 1280, index));
        }
        await waitUntil(() => wake.frames.length == 120);
        await controller.loadCapabilities();
        expect(
          controller.isWakeListening,
          isTrue,
          reason: 'Refreshing capabilities must preserve armed wake listening',
        );
        expect(wake.configs.first.score, 1);
        expect(wake.configs.last.score, 1.5);
        expect(wake.configs.last.threshold, .25);
        audio.onPermissionRequest = () async {
          audio.microphone.add(Uint8List(1280)..fillRange(0, 1280, 250));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        };
        wake.trigger();
        wake.trigger();
        wake.trigger();
        await waitUntil(
          () => controller.state == VoiceConnectionState.listening,
        );

        expect(controller.isWakeActivating, isTrue);
        expect(audio.startedModes, <AudioCaptureMode>[
          AudioCaptureMode.standby,
          AudioCaptureMode.conversation,
        ]);
        expect(createdBodies.single['pre_roll_samples'], 64000);
        await waitUntil(() => receivedPcm.length >= 129280);
        expect(receivedPcm.length, 129280);
        expect(receivedPcm.take(1280), everyElement(20));
        expect(receivedPcm.skip(99 * 1280).take(1280), everyElement(119));
        expect(receivedPcm.skip(100 * 1280), everyElement(250));
        expect(createdBodies.single['activation'], 'wake_word');
        expect(createdBodies.single['wake_word'], '小美小美');
        expect(createdBodies.single['wake_engine'], 'sherpa-onnx-1.13.8');

        wakeSocket!.add(
          jsonEncode({'type': 'transcript.final', 'text': wakeCase.transcript}),
        );
        wakeSocket!.add(jsonEncode({'type': 'transcript.final', 'text': '.'}));
        wakeSocket!.add(
          jsonEncode({
            'type': 'wake.accepted',
            if (wakeCase.command != null) 'command': wakeCase.command,
          }),
        );
        wakeSocket!.add(
          jsonEncode({'type': 'wake.accepted', 'command': '重复事件'}),
        );
        const greetingId = '11111111-2222-4333-8444-555555555556';
        wakeSocket!.add(
          jsonEncode({'type': 'response.started', 'response_id': greetingId}),
        );
        wakeSocket!.add(
          jsonEncode({
            'type': 'text.delta',
            'response_id': greetingId,
            'text': '我在，小美随时为你服务。',
          }),
        );
        wakeSocket!.add(
          outputAudioFrame(
            connectionId: '00112233-4455-6677-8899-aabbccddeeff',
            responseId: greetingId,
          ),
        );
        await waitUntil(
          () => controller.state == VoiceConnectionState.speaking,
        );
        expect(
          controller.messages
              .where((message) => message.role == 'human')
              .map((message) => message.text),
          wakeCase.expected.isEmpty ? isEmpty : <String>[wakeCase.expected],
        );
        expect(controller.messages.length, wakeCase.expected.isEmpty ? 1 : 2);
        expect(controller.messages.last.text, '我在，小美随时为你服务。');
        expect(controller.isWakeActivating, isFalse);
        expect(audio.operations, contains('audio'));

        wakeSocket!.add(jsonEncode(<String, Object?>{'type': 'wake.rejected'}));
        await waitUntil(
          () => controller.state == VoiceConnectionState.wakeListening,
        );
        expect(controller.error, isNull);
        expect(controller.state, VoiceConnectionState.wakeListening);
        await controller.disableWakeWord();
        expect(controller.state, VoiceConnectionState.disconnected);
        controller.dispose();
        await audio.close();
        await server.close(force: true);
      },
    );
  }
}
