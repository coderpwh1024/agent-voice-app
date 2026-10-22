import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/features/voice_session/voice_home_page.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

import 'support/backend_auth.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'voice query shows an archived video and resumes the original thread after playback',
    (tester) async {
      final config = await backendTestConfig();
      final controller = VoiceSessionController(config: config);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.disableWakeWord();
        await controller.disconnect();
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: const Scaffold(body: Center(child: Text('准备视频对话联调…'))),
        ),
      );
      await controller.loadCapabilities();
      final capabilities = controller.capabilities!;
      await controller.connect(
        agentId: capabilities.defaultAgentId ?? capabilities.agents.first.id,
        voice: capabilities.defaultVoice!,
      );
      final originalThread = controller.session!.threadId;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xffd87568),
            ),
          ),
          home: VoiceHomePage(
            controller: controller,
            user: AuthUser(
              id: int.parse(config.userId),
              nickname: '视频联调',
              email: '',
            ),
            onOpenProfile: (_) async {},
            onOpenSettings: (_) async {},
          ),
        ),
      );
      controller.sendText('查询第 1 号视频');
      for (
        var attempt = 0;
        attempt < 120 &&
            !controller.messages.any((e) => e.video?.playableUri != null);
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(
        controller.messages.any((e) => e.video?.playableUri != null),
        isTrue,
        reason: '后端语音通道应返回已转存视频的结构化结果',
      );
      final reference = controller.messages
          .firstWhere((e) => e.video?.playableUri != null)
          .video!;
      expect(reference.recordId, 1);
      await tester.ensureVisible(find.text('播放视频'));
      await tester.pump(const Duration(milliseconds: 500));
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('voice-video-card');
      await tester.tap(find.text('播放视频'));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.isConnected, isFalse, reason: '看视频之前必须停止语音收音和播报');
      for (
        var attempt = 0;
        attempt < 60 && find.byType(VideoPlayer).evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.byType(VideoPlayer), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      final player = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      expect(player.value.position, greaterThan(Duration.zero));
      await player.pause();
      await tester.pump();
      await binding.takeScreenshot('voice-video-playing');
      await tester.tap(find.byTooltip('返回对话'));
      for (
        var attempt = 0;
        attempt < 60 && !controller.isConnected;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(controller.isConnected, isTrue);
      expect(controller.session!.threadId, originalThread);
      expect(
        controller.messages
            .where((e) => e.role == 'human' && e.text == '查询第 1 号视频')
            .length,
        1,
        reason: '恢复语音不应重复提交查询',
      );
      expect(tester.takeException(), isNull);
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'record_id': reference.recordId,
        'voice_video_event': true,
        'native_playback': true,
        'voice_stopped_for_video': true,
        'original_thread_resumed': true,
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
