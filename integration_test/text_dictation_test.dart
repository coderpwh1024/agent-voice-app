import 'dart:io';
import 'dart:typed_data';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/api/voice_protocol.dart';
import 'package:agent_voice_app/core/api/voice_socket.dart';
import 'package:agent_voice_app/core/audio/audio_bridge.dart';
import 'package:agent_voice_app/core/auth/auth_session_store.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/backend_auth.dart';

class PlaybackAudit extends NativeAudioBridge {
  int permissions = 0;
  int bytesPlayed = 0;
  final modes = <AudioCaptureMode>[];

  @override
  Future<bool> requestMicrophonePermission() async {
    permissions++;
    return super.requestMicrophonePermission();
  }

  @override
  Future<AudioProcessingState> start(AudioCaptureMode mode) {
    modes.add(mode);
    return super.start(mode);
  }

  @override
  Future<void> enqueue(
    Uint8List pcm, {
    required String responseId,
    required int segmentIndex,
  }) {
    bytesPlayed += pcm.length;
    return super.enqueue(
      pcm,
      responseId: responseId,
      segmentIndex: segmentIndex,
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'USB text readiness, synthetic dictation and playback without capture',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      debugPrint('CHECK stage=secure-login');
      final config = await backendTestConfig();
      debugPrint('CHECK stage=capabilities');
      expect(config.baseUrl, 'http://127.0.0.1:8000');
      final api = AgentApiClient(config);
      addTearDown(api.close);
      final caps = await api.capabilities();
      expect(
        caps.inputModes,
        containsAll(['conversation', 'text', 'transcription']),
      );
      final audio = PlaybackAudit();
      final controller = VoiceSessionController(config: config, audio: audio);
      addTearDown(() async {
        await controller.disconnect();
        controller.dispose();
      });
      var micFrames = 0;
      final microphone = audio.microphoneFrames.listen((_) => micFrames++);
      addTearDown(microphone.cancel);
      final played = <String>{};
      final playback = audio.playbackEvents.listen((event) {
        if (event['type'] == 'response.finished') {
          played.add(event['responseId'] as String);
        }
      });
      addTearDown(playback.cancel);
      const liveAgent = bool.fromEnvironment('LIVE_AGENT_TEST');
      debugPrint('CHECK stage=native-playback');
      await audio.start(AudioCaptureMode.playback);
      const localPlayback = '00000000-0000-4000-8000-000000000001';
      await audio.enqueue(
        Uint8List(24000),
        responseId: localPlayback,
        segmentIndex: 1,
      );
      await audio.completeSegment(
        responseId: localPlayback,
        segmentIndex: 1,
        samples: 12000,
      );
      await audio.completeResponse(localPlayback);
      await _wait(() => played.contains(localPlayback));
      await audio.stop();
      debugPrint('CHECK stage=text-ready');
      final thread = 'usb-text-dictation-${newEventId()}';
      await controller.connect(
        agentId: caps.defaultAgentId!,
        voice: caps.defaultVoice!,
        threadId: thread,
        inputMode: 'text',
      );
      if (liveAgent) {
        controller.sendText('这是文字输入联调，请只回答收到，不保存个人信息，不调用业务工具。');
        await _wait(() => played.length == 2);
        expect(
          controller.messages.where((item) => item.role == 'ai').last.text,
          isNotEmpty,
        );
      }
      expect(controller.state, VoiceConnectionState.ready);
      expect(audio.permissions, 0);
      expect(micFrames, 0);
      await controller.disconnect();
      debugPrint('CHECK stage=transcription');
      final before = await api.history(caps.defaultAgentId!, thread);
      final session = await api.createVoiceSession(
        agentId: caps.defaultAgentId!,
        voice: caps.defaultVoice!,
        threadId: thread,
        inputMode: 'transcription',
      );
      final socket = await VoiceSocket.connect(
        api.websocketUri(session.sessionId),
        headers: api.websocketHeaders(),
      );
      final events = <Map<String, dynamic>>[];
      final incoming = socket.messages.listen((message) {
        if (message is VoiceSocketEventMessage) events.add(message.event);
      });
      String? text;
      try {
        socket.sendJson(clientEvent('session.configure'));
        await _wait(
          () => events.any((event) => event['type'] == 'session.ready'),
        );
        final ready = events.firstWhere(
          (event) => event['type'] == 'session.ready',
        );
        final fixtureClient = HttpClient();
        late Uint8List wav;
        try {
          final response = await (await fixtureClient.getUrl(
            Uri.parse('http://127.0.0.1:8766/with_command.wav'),
          )).close();
          expect(response.statusCode, 200);
          wav = Uint8List.fromList(
            await response.expand((chunk) => chunk).toList(),
          );
        } finally {
          fixtureClient.close(force: true);
        }
        final data = ByteData.sublistView(wav);
        var offset = 12;
        Uint8List? pcm;
        while (offset + 8 <= wav.length) {
          final length = data.getUint32(offset + 4, Endian.little);
          if (String.fromCharCodes(wav.sublist(offset, offset + 4)) == 'data') {
            pcm = Uint8List.sublistView(wav, offset + 8, offset + 8 + length);
            break;
          }
          offset += 8 + length + length % 2;
        }
        expect(pcm, isNotNull);
        var sequence = 0;
        for (var start = 0; start < pcm!.length; start += 1280) {
          final end = (start + 1280).clamp(0, pcm.length);
          socket.sendAudio(
            encodeInputAudioFrame(
              pcm: Uint8List.sublistView(pcm, start, end),
              connectionId: ready['connection_id'] as String,
              sequence: sequence++,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        socket.sendJson(clientEvent('input.commit'));
        await _wait(
          () => events.any((event) => event['type'] == 'transcript.final'),
        );
        debugPrint('CHECK stage=transcript-received');
        text =
            events.lastWhere(
                  (event) => event['type'] == 'transcript.final',
                )['text']
                as String;
        expect(text.trim(), isNotEmpty);
        expect(
          events.where((event) => event['type'] == 'response.started'),
          isEmpty,
        );
        expect(events.where((event) => event['type'] == 'error'), isEmpty);
        final after = await api.history(caps.defaultAgentId!, thread);
        expect(after.length, before.length);
      } finally {
        socket.sendJson(clientEvent('session.close'));
        await incoming.cancel();
        await socket.close();
        await api.closeVoiceSession(session.sessionId);
      }
      await controller.connect(
        agentId: caps.defaultAgentId!,
        voice: caps.defaultVoice!,
        threadId: thread,
        inputMode: 'text',
      );
      if (liveAgent) {
        controller.sendText('$text 这是转写编辑发送联调，请只回答收到，不保存信息，不调用工具。');
        await _wait(() => played.length == 3);
        final finalHistory = await api.history(caps.defaultAgentId!, thread);
        expect(
          finalHistory.where((item) => item.role == 'human').length,
          before.where((item) => item.role == 'human').length + 1,
        );
      }
      expect(audio.permissions, 0);
      expect(micFrames, 0);
      expect(audio.modes, everyElement(AudioCaptureMode.playback));
      await const AuthSessionStore().updateBaseUrl(config.baseUrl);
      binding.reportData = {
        'backend': config.baseUrl,
        'text_session_ready': true,
        'live_agent_tts_verified': liveAgent,
        'native_playback_verified': played.contains(localPlayback),
        'transcription_waits_for_send': true,
        'shared_thread': true,
        'microphone_permission_requests': audio.permissions,
        'microphone_frames': micFrames,
        'played_pcm_bytes': audio.bytesPlayed,
        'played_responses': played.length,
      };
    },
  );
}

Future<void> _wait(bool Function() condition) async {
  final timer = Stopwatch()..start();
  while (!condition()) {
    if (timer.elapsed > const Duration(seconds: 100)) {
      fail('Local voice integration timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
