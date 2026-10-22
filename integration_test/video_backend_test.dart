import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/auth/auth_session_store.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/videos/data/video_api.dart';
import 'package:agent_voice_app/features/videos/data/video_models.dart';
import 'package:agent_voice_app/features/videos/video_create_page.dart';
import 'package:agent_voice_app/features/videos/video_detail_page.dart';
import 'package:agent_voice_app/features/videos/video_studio_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('USB phone: authenticated video API and existing features', (
    tester,
  ) async {
    const baseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000',
    );
    const bridge = String.fromEnvironment('VIDEO_TEST_AUTH_BRIDGE');
    late final AppConfig config;
    if (bridge.isNotEmpty) {
      final uri = Uri.parse(bridge);
      expect(uri.host, '127.0.0.1');
      final http = HttpClient();
      try {
        final response = await (await http.getUrl(uri)).close();
        expect(response.statusCode, 200);
        final data = jsonDecode(
          await utf8.decoder.bind(response).join(),
        ) as Map<String, dynamic>;
        config = AppConfig(
          baseUrl: baseUrl,
          accessToken: data['access_token'] as String,
          userId: data['user_id'] as String,
        );
      } finally {
        http.close(force: true);
      }
    } else {
      final session = await const AuthSessionStore().read();
      expect(session, isNotNull, reason: '请先在真机 App 中登录，然后重新运行视频联调');
      config = session!.config.copyWith(baseUrl: baseUrl);
    }
    final client = AgentApiClient(config);
    final api = VideoApi(config, client: client);
    addTearDown(client.close);
    if (bridge.isEmpty) {
      final user = await client.currentUser();
      expect(user.id.toString(), config.userId);
    }
    final capabilities = await client.capabilities();
    expect(capabilities.agents, isNotEmpty);
    await client.chatRecords(
      capabilities.defaultAgentId ?? capabilities.agents.first.id,
    );
    await client.memories(limit: 1);
    final before = await api.list();
    expect(before.total, greaterThanOrEqualTo(0));

    Widget wrap(Widget page) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffaa496b)),
      ),
      home: page,
    );
    await tester.pumpWidget(wrap(VideoStudioPage(config: config, api: api)));
    await tester.pump(const Duration(seconds: 2));
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('video-studio');
    await tester.pumpWidget(wrap(VideoCreatePage(config: config, api: api)));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('video-create');
    await tester.pumpWidget(const SizedBox.shrink());
    const draft = VideoDraft(
      prompt: '夕阳下的海岸，浪花轻轻拍打沙滩，镜头缓慢横移，暖色胶片质感，宁静而浪漫。',
      resolution: '480P',
      duration: 3,
    );
    final task = await api.create(draft, 'app-video-usb-20261022-01');
    final repeated = await api.create(draft, 'app-video-usb-20261022-01');
    expect(repeated.id, task.id, reason: '相同幂等键必须返回同一任务');
    final after = await api.list();
    expect(after.items.any((item) => item.id == task.id), isTrue);
    var latest = await api.detail(task.id);
    var deadline = DateTime.now().add(const Duration(minutes: 8));
    while (latest.shouldPoll && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 10));
      latest = await api.detail(task.id);
    }
    binding.reportData ??= {};
    binding.reportData!.addAll({
      'record_id': latest.id,
      'status': latest.status,
      'storage_status': latest.storageStatus,
      'existing_profile': bridge.isEmpty,
      'isolated_test_identity': bridge.isNotEmpty,
      'existing_capabilities': true,
      'existing_chat_records': true,
      'existing_memories': true,
    });
    await tester.pumpWidget(
      wrap(
        VideoDetailPage(
          config: config,
          recordId: latest.id,
          initialTask: latest,
          api: api,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    if (latest.playableUri != null) {
      for (
        var attempt = 0;
        attempt < 60 && find.byType(VideoPlayer).evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.byType(VideoPlayer), findsOneWidget);
      await tester.tap(find.byTooltip('播放影片').first);
      await tester.pump(const Duration(seconds: 2));
      final player = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      expect(player.value.position, greaterThan(Duration.zero));
      await player.pause();
      await tester.pump();
      binding.reportData!['native_playback'] = true;
    }
    await binding.takeScreenshot('video-detail');
    expect(tester.takeException(), isNull);
    if (latest.playableUri != null) {
      final http = HttpClient();
      try {
        final response = await (await http.getUrl(latest.playableUri!)).close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      } finally {
        http.close(force: true);
      }
    }
    expect(latest.status, 'SUCCEEDED', reason: '实际模型生成失败，请检查后端模型服务');
    expect(latest.storageStatus, 'STORED', reason: '生成完成后应转存成功');
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 12)));
}
