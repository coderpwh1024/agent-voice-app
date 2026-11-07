import 'dart:io';
import 'dart:typed_data';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/api/voice_protocol.dart';
import 'package:agent_voice_app/core/api/voice_socket.dart';
import 'package:agent_voice_app/core/audio/audio_bridge.dart';
import 'package:agent_voice_app/features/videos/data/video_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

import 'audio_playback_test.dart' as playback;
import 'support/backend_auth.dart';

void main() {
  playback.main();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('USB local backend with the saved app login and real providers', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final config = await backendTestConfig();
    expect(Uri.parse(config.baseUrl).host, '127.0.0.1');
    final api = AgentApiClient(config);
    addTearDown(api.close);
    final user = await api.currentUser();
    expect(user.id.toString(), config.userId);
    final metadata = await api.requestJson('GET', '/info');
    expect((metadata['agents'] as List).map((item) => item['key']).toList(), [
      'mem0-chatbot',
    ]);
    final capabilities = await api.capabilities();
    expect(capabilities.enabled, isTrue);
    expect(capabilities.defaultAgentId, 'mem0-chatbot');
    expect(capabilities.defaultVoice, isNotNull);
    await api.chatRecords('mem0-chatbot');
    await api.memories(limit: 1);
    final videos = VideoApi(config, client: api);
    final page = await videos.list();

    for (final endpoint in ['/files', '/videos', '/skills/email/send']) {
      await expectLater(
        api.requestJson('POST', endpoint, body: {}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)),
      );
    }
    final threadId = 'usb-local-${newEventId()}';
    final result = await api
        .requestJson(
          'POST',
          '/mem0-chatbot/invoke',
          body: {
            'thread_id': threadId,
            'message': '这是一次本地接口联调，请只回答收到，不保存任何个人信息。',
          },
        )
        .timeout(const Duration(seconds: 120));
    expect((result['content'] as String).trim(), isNotEmpty);
    final history = await api.history('mem0-chatbot', threadId);
    expect(history.where((item) => item.role == 'ai'), isNotEmpty);
    expect(
      (await api.threads('mem0-chatbot'))
          .any((item) => item.threadId == threadId),
      isTrue,
    );
    final voice = VoiceSession.fromJson(
      await api.requestJson(
        'POST',
        '/voice/sessions',
        body: {
          'agent_id': 'mem0-chatbot',
          'voice': capabilities.defaultVoice,
          'language': 'zh',
          'turn_detection': 'manual',
        },
      ),
    );
    addTearDown(() => api.closeVoiceSession(voice.sessionId));
    final socket = await VoiceSocket.connect(
      api.websocketUri(voice.sessionId),
      headers: api.websocketHeaders(),
    );
    addTearDown(socket.close);
    final audio = NativeAudioBridge();
    addTearDown(audio.stop);
    expect(await audio.requestMicrophonePermission(), isTrue);
    await audio.start(AudioCaptureMode.conversation);
    var microphoneFrames = 0;
    final microphone = audio.microphoneFrames.listen((_) => microphoneFrames++);
    addTearDown(microphone.cancel);
    final finishedPlayback = <String>{};
    final playbackEvents = audio.playbackEvents.listen((event) {
      if (event['type'] == 'response.finished') {
        final id = event['responseId'] as String;
        finishedPlayback.add(id);
        socket.sendJson(clientEvent('playback.finished', {'response_id': id}));
      } else if (event['type'] == 'segment.finished') {
        socket.sendJson(
          clientEvent('playback.progress', {
            'response_id': event['responseId'],
            'segment_index': event['segmentIndex'],
            'played_samples': event['playedSamples'],
          }),
        );
      }
    });
    addTearDown(playbackEvents.cancel);
    final events = <Map<String, dynamic>>[];
    var audioFrames = 0;
    String? transportError;
    final messages = socket.messages
        .asyncMap((message) async {
          if (message is VoiceSocketAudioMessage) {
            final frame = decodeOutputAudioFrame(message.bytes);
            audioFrames++;
            await audio.enqueue(
              frame.pcm,
              responseId: frame.responseId,
              segmentIndex: frame.segmentIndex,
            );
          } else if (message is VoiceSocketEventMessage) {
            final event = message.event;
            events.add(event);
            if (event['type'] == 'audio.segment.done') {
              await audio.completeSegment(
                responseId: event['response_id'] as String,
                segmentIndex: event['segment_index'] as int,
                samples: event['samples'] as int,
              );
            } else if (event['type'] == 'response.done') {
              await audio.completeResponse(event['response_id'] as String);
            } else if (event['type'] == 'error') {
              transportError = event['code']?.toString() ?? 'voice_error';
            }
          }
        })
        .listen(
          null,
          onError: (Object error) {
            transportError = error.runtimeType.toString();
          },
        );
    addTearDown(messages.cancel);
    socket.sendJson(
      clientEvent('session.configure', {
        'protocol_version': 1,
        'input_format': 'pcm16_16000_mono',
        'output_format': 'pcm16_24000_mono',
      }),
    );
    await _wait(() => events.any((e) => e['type'] == 'session.ready'));
    socket.sendJson(
      clientEvent('input.text', {'text': '这是语音联调，请只回答你好，不保存个人信息。'}),
    );
    await _wait(() => events.any((e) => e['type'] == 'response.done'));
    final firstDone = events.lastWhere((e) => e['type'] == 'response.done');
    expect(transportError, isNull);
    expect(firstDone['execution_status'], 'completed');
    expect(firstDone['audio_status'], 'completed');
    expect(audioFrames, greaterThan(0));
    await _wait(() => finishedPlayback.contains(firstDone['response_id']));
    expect(microphoneFrames, greaterThan(0));

    const fixtureUrl = String.fromEnvironment(
      'ASR_FIXTURE_URL',
      defaultValue: 'http://127.0.0.1:18766/asr-test.pcm',
    );
    final http = HttpClient();
    late Uint8List pcm;
    try {
      final response = await (await http.getUrl(Uri.parse(fixtureUrl))).close();
      expect(response.statusCode, 200);
      final bytes = BytesBuilder();
      await response.forEach(bytes.add);
      pcm = bytes.takeBytes();
    } finally {
      http.close(force: true);
    }
    final connectionId =
        events.firstWhere((e) => e['type'] == 'session.ready')['connection_id']
            as String;
    var sequence = 0;
    for (var offset = 0; offset < pcm.length; offset += 1280) {
      final end = (offset + 1280).clamp(0, pcm.length);
      socket.sendAudio(
        encodeInputAudioFrame(
          pcm: Uint8List.sublistView(pcm, offset, end),
          connectionId: connectionId,
          sequence: sequence++,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    socket.sendJson(clientEvent('input.commit'));
    await _wait(
      () => events.any(
        (e) =>
            e['type'] == 'transcript.final' &&
            (e['text'] as String? ?? '').contains('联调'),
      ),
    );
    await _wait(
      () => events.where((e) => e['type'] == 'response.done').length >= 2,
    );
    final lastDone = events.lastWhere((e) => e['type'] == 'response.done');
    expect(transportError, isNull);
    expect(lastDone['execution_status'], 'completed');
    expect(lastDone['audio_status'], 'completed');
    await _wait(() => finishedPlayback.contains(lastDone['response_id']));
    socket.sendJson(clientEvent('session.close'));
    await _wait(() => events.any((e) => e['type'] == 'session.closed'));

    var videoPlayback = false;
    for (final task in page.items) {
      if (task.playableUri == null) continue;
      final latest = await videos.detail(task.id);
      final player = VideoPlayerController.networkUrl(latest.playableUri!);
      try {
        await player.initialize().timeout(const Duration(seconds: 30));
        await player.play();
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(player.value.position, greaterThan(Duration.zero));
        videoPlayback = true;
      } finally {
        await player.dispose();
      }
      break;
    }
    binding.reportData = {
      'local_backend': config.baseUrl,
      'saved_login': true,
      'profile': true,
      'single_mem0_agent': true,
      'chat_invoke_history_threads': true,
      'memory_list': true,
      'video_list': true,
      'existing_video_native_playback': videoPlayback,
      'validation_guards': true,
      'real_asr_synthetic_pcm': true,
      'real_model_tts': true,
      'native_microphone_frames': microphoneFrames,
      'received_pcm_frames': audioFrames,
      'native_playback_completions': finishedPlayback.length,
      'email_sent': false,
      'video_generated': false,
    };
  }, timeout: const Timeout(Duration(minutes: 8)));
}

Future<void> _wait(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for a live backend or native playback event');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
